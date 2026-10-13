#!/bin/bash
# Sanity tests of the whole setup on this machine, with ONE command. After ocean_setup, from
# anywhere:
#
#     bash $OCEANANIGANS_DRAC_ROOT/tools/run_tests.sh              # 1, 2 and 4 GPUs
#     bash $OCEANANIGANS_DRAC_ROOT/tools/run_tests.sh --gpus "1 2"  # only 1 and 2 GPUs
#     bash $OCEANANIGANS_DRAC_ROOT/tools/run_tests.sh --list        # show the tests, run nothing
#
# pelee/rondeau: runs the tests one after another with tools/run_local.sh (a test that needs more
# GPUs than are free is SKIPPED, not failed). Alliance: submits one Slurm job that runs them all
# (the summary appears when the job ends).
#
# Output: a summary table in results/tests/<machine>_<date-time>.md (commit it: it is the record
# of what was tested, with which versions), plus one log per test in logs/.
#
# Tests (each prints PASS/FAIL and exits non-zero on failure):
#   check_env            environment and repository project (warnings reported, not failures)
#   load        1 GPU    packages load, versions, GPU works, MPI starts
#   grids       1 GPU    uniform / stretched / lat-lon / immersed grids on the GPU
#   hydrostatic n GPUs   HydrostaticFreeSurfaceModel steps; n > 1: matches the single-GPU run
#   single_mpi, cuda_aware_mpi, distributed_vs_serial, output   n GPUs: the checks/ scripts
#   nh_fft      n GPUs   NonhydrostaticModel (FFT pressure solver) steps, finite
#   nh_ft       1 GPU    NonhydrostaticModel, stretched z (Fourier-tridiagonal solver)
#   viz         CPU      viz environment: NetCDF, PNG and MP4 with CairoMakie

set -o pipefail
: "${OCEANANIGANS_DRAC_ROOT:?run ocean_setup first}"
ROOT="$OCEANANIGANS_DRAC_ROOT"
cd "$ROOT" || exit 1

gpus="1 2 4"; list_only=0; in_job=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --gpus) gpus="$2"; shift 2 ;;
        --list) list_only=1; shift ;;
        --in-job) in_job=1; shift ;;
        -h|--help) sed -n '2,27p' "$0"; exit 0 ;;
        *) echo "unknown option $1 (try --help)"; exit 1 ;;
    esac
done
maxgpu=$(tr ' ' '\n' <<<"$gpus" | sort -n | tail -1)

# ---- the test list: name | GPUs | project | script and arguments ----
tests=()
add() { tests+=("$1|$2|$3|$4"); }
add load 1 . tests/load.jl
add grids 1 . tests/grids.jl
for n in $gpus; do
    add hydrostatic "$n" . tests/hydrostatic.jl
    for c in single_mpi cuda_aware_mpi distributed_vs_serial output; do
        add "$c" "$n" . "checks/$c.jl"
    done
    add nh_fft "$n" . "benchmarks/nonhydrostatic_box.jl --size=128x128x64 --solver=FFT --steps=10 --windows=2 --warmup=3 --output=logs/tests_nh_fft_${n}gpu.json"
done
add nh_ft 1 . "benchmarks/nonhydrostatic_box.jl --size=128x128x64 --solver=FourierTridiagonal --steps=10 --windows=2 --warmup=3 --output=logs/tests_nh_ft_1gpu.json"
add viz 0 viz tests/viz.jl

if [[ $list_only -eq 1 ]]; then
    printf '%-24s %-5s %-6s %s\n' TEST GPUS ENV SCRIPT
    for t in "${tests[@]}"; do IFS='|' read -r name n proj cmd <<<"$t"; printf '%-24s %-5s %-6s %s\n' "$name" "$n" "$proj" "$cmd"; done
    exit 0
fi

# ---- Alliance: submit everything as one job, then stop ----
slurm=0
[[ -n "$CC_CLUSTER" ]] && command -v sbatch >/dev/null && slurm=1
if [[ $slurm -eq 1 && $in_job -eq 0 && -z "$SLURM_JOB_ID" ]]; then
    mkdir -p logs
    sbatch --job-name=tests --nodes=1 --ntasks-per-node="$maxgpu" --gpus-per-task=h100:1 \
           --cpus-per-task=4 --mem=128G --time=1:30:00 --output="logs/tests_%j.out" \
           --export=ALL "$0" --in-job --gpus "$gpus"
    echo "Submitted. When it ends: cat logs/tests_<jobid>.out, summary in results/tests/."
    exit 0
fi

# ---- run ----
if [[ $in_job -eq 1 ]]; then
    source "$ROOT/env/ocean_setup.sh" >/dev/null     # modules inside the job
    cd "$ROOT" || exit 1
fi
mkdir -p logs results/tests
stamp=$(date +%Y%m%d-%H%M)
machine="${OCEAN_MACHINE:-$(hostname -s)}"
summary="results/tests/${machine}_${stamp}.md"
rows=()
npass=0; nfail=0; nskip=0

record() {   # name gpus result seconds detail log
    rows+=("| $1 | $2 | $3 | $4 | $5 | \`$6\` |")
    printf '%-28s %-4s %-5s %5ss  %s\n' "$1" "$2" "$3" "$4" "$5"
    case "$3" in PASS) npass=$((npass+1)) ;; FAIL) nfail=$((nfail+1)) ;; *) nskip=$((nskip+1)) ;; esac
}
detail_of() {  # last informative line of a log
    grep -E "PASS|FAIL|RESULT|ERROR|Error|error:|Only [0-9]+ free" "$1" 2>/dev/null | tail -1 | cut -c1-110 | tr '|' '/'
}

echo "Tests on $machine, $(date '+%F %T'), GPUs: $gpus"

# check_env (warnings are reported, not failures)
log="logs/tests_check_env_${stamp}.out"
bash tools/check_env.sh "$ROOT" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' > "$log"     # without colour codes
nw=$(grep -c "WARN" "$log")
if [[ $nw -eq 0 ]]; then record check_env - PASS 0 "all checks OK" "$log"
else record check_env - WARN 0 "$nw warning(s): $(grep WARN "$log" | head -1 | sed 's/.*WARN *//' | cut -c1-80)" "$log"; fi

# precompile once (both environments)
julia --project=. -e 'using Pkg; Pkg.precompile()' > "logs/tests_precompile_${stamp}.out" 2>&1
julia --project=viz -e 'using Pkg; Pkg.precompile()' >> "logs/tests_precompile_${stamp}.out" 2>&1

for t in "${tests[@]}"; do
    IFS='|' read -r name n proj cmd <<<"$t"
    label="$name"; [[ $n -gt 1 ]] && label="${name}_${n}gpu"
    log="logs/tests_${label}_${stamp}.out"
    if [[ $n -gt $maxgpu ]]; then record "$label" "$n" SKIP 0 "more GPUs than requested" "$log"; continue; fi
    start=$(date +%s)
    # shellcheck disable=SC2086   # $cmd is "script arg1 arg2 ..."
    if [[ $slurm -eq 1 ]]; then
        if [[ $n -eq 0 ]]; then
            julia --project="$proj" $cmd > "$log" 2>&1
        else
            srun --exact --ntasks="$n" --cpu-bind=none julia --project="$proj" $cmd > "$log" 2>&1
        fi
        status=$?
    else
        out=$(bash tools/run_local.sh --wait -n "$n" -p "$proj" -j "tests_${label}" $cmd 2>&1)
        status=$?
        runlog=$(sed -n 's/^log: *//p' <<<"$out")
        if [[ -n "$runlog" && -f "$runlog" ]]; then mv "$runlog" "$log"; else echo "$out" > "$log"; fi
        if [[ $status -ne 0 ]] && grep -q "free GPU" <<<"$out"; then
            record "$label" "$n" SKIP 0 "GPUs busy: $(grep -o 'Only [0-9]* free GPU(s)' <<<"$out")" "$log"; continue
        fi
    fi
    secs=$(( $(date +%s) - start ))
    if [[ $status -eq 0 ]]; then record "$label" "$n" PASS "$secs" "$(detail_of "$log")" "$log"
    else record "$label" "$n" FAIL "$secs" "$(detail_of "$log")" "$log"; fi
done

{
    echo "# Tests on $machine, $(date '+%F %T')"
    echo
    echo "Oceananigans-DRAC $(git -C "$ROOT" log -1 --format='%h %s'), GPUs tested: $gpus."
    echo "Versions: see the \`load\` log. **$npass passed, $nfail failed, $nskip skipped or warnings.**"
    echo
    echo "| Test | GPUs | Result | Seconds | Detail | Log |"
    echo "| --- | --- | --- | --- | --- | --- |"
    printf '%s\n' "${rows[@]}"
    echo
    echo '```'
    grep -E "^(julia|Oceananigans|CUDA|MPI|NCDatasets|JLD2|OpenMPI_jll|libmpi|GPU) " "logs/tests_load_${stamp}.out" 2>/dev/null
    echo '```'
} > "$summary"

echo
echo "$npass passed, $nfail failed, $nskip skipped/warnings. Summary: $summary"
[[ $nfail -eq 0 ]]
