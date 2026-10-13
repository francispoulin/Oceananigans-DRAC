#!/bin/bash
# Platform sanity tests on this machine, with ONE command. After ocean_setup, from anywhere:
#
#     bash $OCEANANIGANS_DRAC_ROOT/tools/run_tests.sh              # 1, 2 and 4 GPUs
#     bash $OCEANANIGANS_DRAC_ROOT/tools/run_tests.sh --gpus "1 2"  # only 1 and 2 GPUs
#
# What runs, in order (each step is one process; tests/platform.jl lists its tests in detail):
#
#   check_env        environment and this repository's project (warnings, not failures)
#   platform, 1 GPU  load, grids, single_mpi, output, hydro_channel, hydro_box, checkpoint,
#                    nh_fft, nh_ft (saves the 1-GPU reference fields)
#   platform, 2 GPUs load, single_mpi, cuda_aware, halo, output, hydro_channel, hydro_box,
#                    checkpoint, nh_fft, nh_ft (compared with the 1-GPU reference)
#   platform, 4 GPUs the same as 2 GPUs
#   viz              viz environment: NetCDF, PNG and MP4 with CairoMakie (CPU)
#
# These test the platform only (environment, MPI, CUDA, Oceananigans and other libraries, viz);
# simulation repositories test their own physics. Proof of function, not performance: small grids,
# 10-30 steps. Expect ~3-5 min per GPU count (mostly loading and compiling, once per process).
#
# pelee/rondeau: one step after another via tools/run_local.sh; a step that needs more GPUs than are
# free is SKIPPED. Alliance: one Slurm job runs everything (the summary appears when it ends).
# Output: results/tests/<machine>_<date-time>.md (commit it: the record of what was tested, with
# which versions), and one log per step in logs/.

set -o pipefail
: "${OCEANANIGANS_DRAC_ROOT:?run ocean_setup first}"
ROOT="$OCEANANIGANS_DRAC_ROOT"
cd "$ROOT" || exit 1

gpus="1 2 4"; in_job=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --gpus) gpus="$2"; shift 2 ;;
        --in-job) in_job=1; shift ;;
        -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
        *) echo "unknown option $1 (try --help)"; exit 1 ;;
    esac
done
maxgpu=$(tr ' ' '\n' <<<"$gpus" | sort -n | tail -1)

# ---- Alliance: submit everything as one job, then stop ----
slurm=0
[[ -n "$CC_CLUSTER" ]] && command -v sbatch >/dev/null && slurm=1
if [[ $slurm -eq 1 && $in_job -eq 0 && -z "$SLURM_JOB_ID" ]]; then
    mkdir -p logs
    sbatch --job-name=tests --nodes=1 --ntasks-per-node="$maxgpu" --gpus-per-task=h100:1 \
           --cpus-per-task=4 --mem=128G --time=1:00:00 --output="logs/tests_%j.out" \
           --export=ALL "$0" --in-job --gpus "$gpus"
    echo "Submitted. When it ends: cat logs/tests_<jobid>.out; summary in results/tests/."
    exit 0
fi
if [[ $in_job -eq 1 ]]; then
    source "$ROOT/env/ocean_setup.sh" >/dev/null
    cd "$ROOT" || exit 1
fi

# ---- run ----
mkdir -p logs results/tests
stamp=$(date +%Y%m%d-%H%M)
machine="${OCEAN_MACHINE:-$(hostname -s)}"
summary="results/tests/${machine}_${stamp}.md"
export TEST_REF_DIR="$ROOT/logs/tests_ref_${stamp}"      # 1-GPU reference fields for this run
rows=(); npass=0; nfail=0; nskip=0

record() {   # test gpus result seconds detail log
    rows+=("| $1 | $2 | $3 | $4 | $5 | \`$6\` |")
    printf '%-15s %-4s %-5s %5ss  %s\n' "$1" "$2" "$3" "$4" "$5"
    case "$3" in PASS) npass=$((npass+1)) ;; FAIL) nfail=$((nfail+1)) ;; *) nskip=$((nskip+1)) ;; esac
}

# Run one step: name gpus project script. Sets $status and $log.
run_step() {
    local name=$1 n=$2 proj=$3 script=$4
    log="logs/tests_${name}_${stamp}.out"
    if [[ $slurm -eq 1 ]]; then
        if [[ $n -eq 0 ]]; then julia --project="$proj" "$script" > "$log" 2>&1
        else srun --exact --ntasks="$n" --cpu-bind=none julia --project="$proj" "$script" > "$log" 2>&1; fi
        status=$?
    else
        local out runlog
        out=$(bash tools/run_local.sh --wait -n "$n" -p "$proj" -j "tests_${name}" "$script" 2>&1)
        status=$?
        runlog=$(sed -n 's/^log: *//p' <<<"$out")
        if [[ -n "$runlog" && -f "$runlog" ]]; then mv "$runlog" "$log"; else echo "$out" > "$log"; fi
        if [[ $status -ne 0 ]] && grep -q "free GPU" <<<"$out"; then status=99; fi   # GPUs busy
    fi
}

echo "Platform tests on $machine, $(date '+%F %T'), GPUs: $gpus"

# check_env (warnings are reported, not failures)
log="logs/tests_check_env_${stamp}.out"
bash tools/check_env.sh "$ROOT" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' > "$log"
nw=$(grep -c "WARN" "$log")
if [[ $nw -eq 0 ]]; then record check_env - PASS 0 "all checks OK" "$log"
else record check_env - WARN 0 "$nw warning(s): $(grep WARN "$log" | head -1 | sed 's/.*WARN *//' | cut -c1-80)" "$log"; fi

# precompile both environments once (not timed)
{ julia --project=. -e 'using Pkg; Pkg.precompile()'; julia --project=viz -e 'using Pkg; Pkg.precompile()'; } \
    > "logs/tests_precompile_${stamp}.out" 2>&1

for n in $gpus; do
    start=$(date +%s)
    run_step "platform_${n}gpu" "$n" . tests/platform.jl
    if [[ $status -eq 99 ]]; then
        record "(platform)" "$n" SKIP 0 "GPUs busy: $(grep -o 'Only [0-9]* free GPU(s)' "$log" | head -1)" "$log"
        continue
    fi
    found=0
    while read -r _ tname tstatus tsecs tdetail; do
        found=1
        record "$tname" "$n" "$tstatus" "$tsecs" "$(cut -c1-100 <<<"$tdetail" | tr '|' '/')" "$log"
    done < <(grep "^TEST " "$log")
    if [[ $found -eq 0 || ( $status -ne 0 && -z "$(grep '^SUMMARY' "$log")" ) ]]; then
        record "(platform)" "$n" FAIL $(( $(date +%s) - start )) \
               "$(grep -E 'ERROR|Error|error' "$log" | tail -1 | cut -c1-100 | tr '|' '/')" "$log"
    fi
    echo "                     (platform on $n GPU(s): $(( $(date +%s) - start )) s in total)"
done

start=$(date +%s)
run_step viz 0 viz tests/viz.jl
secs=$(( $(date +%s) - start ))
detail=$(grep -E "PASS|FAIL|ERROR" "$log" | tail -1 | cut -c1-100 | tr '|' '/')
if [[ $status -eq 0 ]]; then record viz CPU PASS "$secs" "$detail" "$log"; else record viz CPU FAIL "$secs" "$detail" "$log"; fi

{
    echo "# Platform tests on $machine, $(date '+%F %T')"
    echo
    echo "Oceananigans-DRAC $(git -C "$ROOT" log -1 --format='%h %s'). GPUs: $gpus."
    echo "**$npass passed, $nfail failed, $nskip skipped or warnings.**"
    echo
    echo "| Test | GPUs | Result | Seconds | Detail | Log |"
    echo "| --- | --- | --- | --- | --- | --- |"
    printf '%s\n' "${rows[@]}"
    echo
    echo '```'
    grep -hE "^(julia|Oceananigans|CUDA|MPI|NCDatasets|JLD2|OpenMPI_jll|GPU) " logs/tests_platform_*gpu_"${stamp}".out 2>/dev/null | sort -u
    echo '```'
} > "$summary"

echo
echo "$npass passed, $nfail failed, $nskip skipped/warnings. Summary: $summary"
[[ $nfail -eq 0 ]]
