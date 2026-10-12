#!/bin/bash
# Run a Julia script in the background on a machine WITHOUT Slurm (pelee, rondeau): picks free
# GPUs, survives logout, and writes a log, like sbatch does on the Alliance. After ocean_setup,
# from your project folder:
#
#     bash $OCEANANIGANS_DRAC_ROOT/tools/run_local.sh -n 4 scripts/run.jl --arg=1   # 4 GPUs, MPI
#     bash $OCEANANIGANS_DRAC_ROOT/tools/run_local.sh -n 1 scripts/run.jl          # 1 GPU
#     bash $OCEANANIGANS_DRAC_ROOT/tools/run_local.sh -n 0 --viz scripts/make_movies.jl  # CPU, viz
#
# Options:
#   -n N        number of GPUs (= MPI ranks when N > 1); 0 = CPU only. Default 1.
#   -g 0,2      use exactly these GPUs instead of picking free ones
#   -p DIR      Julia project (default: current folder); --viz = the viz environment
#   -j NAME     run name for the log file (default: script name)
#   --dry-run   show what would run, start nothing
#
# Output goes to logs/<name>_<date-time>.out in the current folder. The command prints the
# process ID; stop the run with `kill <pid>` (stops all its ranks).
#
# With N > 1 all chosen GPUs are visible to every rank and Oceananigans' Distributed(GPU())
# gives each rank its own (node-local rank i -> i-th visible GPU), so CUDA-aware MPI can use
# NVLink between them.
#
# Free = no compute process on it now. Two runs started in the same second can still collide;
# check with `nvidia-smi` if in doubt.

set -eo pipefail
: "${OCEANANIGANS_DRAC_ROOT:?run ocean_setup first}"

ngpu=1; gpus=""; project="$PWD"; name=""; dry=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        -n) ngpu="$2"; shift 2 ;;
        -g) gpus="$2"; shift 2 ;;
        -p) project="$(cd "$2" && pwd)"; shift 2 ;;
        --viz) project="$OCEANANIGANS_DRAC_ROOT/viz"; shift ;;
        -j) name="$2"; shift 2 ;;
        --dry-run) dry=1; shift ;;
        -h|--help) sed -n '2,27p' "$0"; exit 0 ;;
        -*) echo "unknown option $1 (try --help)"; exit 1 ;;
        *) break ;;
    esac
done
[[ $# -ge 1 ]] || { echo "usage: run_local.sh [-n N] [-g list] [-p dir|--viz] [-j name] script.jl [args...]"; exit 1; }
script="$1"; shift
[[ -f "$script" ]] || { echo "no such script: $script (run from your project folder)"; exit 1; }
[[ -f "$project/Project.toml" ]] || { echo "no Project.toml in $project"; exit 1; }

# ---- choose GPUs ----
if [[ "$ngpu" -gt 0 ]]; then
    command -v nvidia-smi >/dev/null || { echo "nvidia-smi not found: no GPUs here? Use -n 0."; exit 1; }
    if [[ -z "$gpus" ]]; then
        busy="$(nvidia-smi --query-compute-apps=gpu_uuid --format=csv,noheader | sort -u)"
        free=()
        while IFS=', ' read -r idx uuid; do
            grep -q "$uuid" <<<"$busy" || free+=("$idx")
        done < <(nvidia-smi --query-gpu=index,uuid --format=csv,noheader)
        if [[ ${#free[@]} -lt $ngpu ]]; then
            echo "Only ${#free[@]} free GPU(s) (${free[*]:-none}); $ngpu requested. In use:"
            nvidia-smi --query-compute-apps=gpu_uuid,pid,used_memory --format=csv,noheader |
                while IFS=', ' read -r uuid pid mem; do
                    idx="$(nvidia-smi --query-gpu=index,uuid --format=csv,noheader | grep "$uuid" | cut -d, -f1)"
                    echo "  GPU $idx: pid $pid, user $(ps -o user= -p "$pid" 2>/dev/null || echo ?), $mem"
                done
            exit 1
        fi
        gpus="$(IFS=,; echo "${free[*]:0:$ngpu}")"
    fi
    export CUDA_VISIBLE_DEVICES="$gpus"
else
    export CUDA_VISIBLE_DEVICES=""
fi

# ---- command ----
jl=(julia --project="$project" "$script" "$@")
if [[ "$ngpu" -gt 1 ]]; then
    cmd=(mpiexec -n "$ngpu" --bind-to none "${jl[@]}")
else
    cmd=("${jl[@]}")
fi

name="${name:-$(basename "$script" .jl)}"
mkdir -p logs
log="logs/${name}_$(date +%Y%m%d-%H%M%S).out"

echo "machine:  ${OCEAN_MACHINE:-$(hostname -s)}"
echo "GPUs:     ${CUDA_VISIBLE_DEVICES:-none (CPU)}"
echo "project:  $project"
echo "command:  ${cmd[*]}"
echo "log:      $log"
[[ $dry -eq 1 ]] && { echo "(dry run: nothing started)"; exit 0; }

{
    echo "# $(date '+%F %T') on ${OCEAN_MACHINE:-$(hostname -s)}, user $USER"
    echo "# CUDA_VISIBLE_DEVICES=$CUDA_VISIBLE_DEVICES"
    echo "# ${cmd[*]}"
} > "$log"

# setsid + nohup: own process group, immune to logout. `kill <pid>` stops the whole group.
setsid nohup bash -c 'trap "echo \"# \$(date \"+%F %T\") stopped by kill\"; trap - TERM; kill 0" TERM
                      "$@" & wait $!; status=$?
                      echo "# $(date "+%F %T") finished, exit status $status"' _ "${cmd[@]}" >> "$log" 2>&1 < /dev/null &
pid=$!
echo "started:  pid $pid"
echo
echo "  follow:  tail -f $log"
echo "  stop:    kill $pid"
