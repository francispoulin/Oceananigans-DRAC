#!/bin/bash
# Pressure solver alone at 1024^3 in Float32 (fits on ONE H100-80GB: ~38 GiB), MPI vs NCCL, on a
# cluster with 4 GPUs per node (Fir, Rorqual): 1 GPU, 2 and 4 GPUs on one node, 8 GPUs on 2 nodes.
# Strong scaling only (same 1024^3 grid on all). From the repository root, on a login node, after
# ocean_setup and bash setup/setup_nccl_env.sh (once per cluster):
#
#     bash jobs/submit_poisson_1024.sh                 # 7 jobs
#     MAXNODES=1 bash jobs/submit_poisson_1024.sh      # 1, 2, 4 GPUs only (5 jobs)
#     DRYRUN=1 bash jobs/submit_poisson_1024.sh        # show the sbatch commands only
#
# Results:  grep -ah "^RESULT poisson" logs/p1024_*.out
# Expected memory (from 512^3 on rondeau): ~38 GiB on 1 GPU, ~20 GiB per GPU on 2, ~11 on 4.

set -eo pipefail
: "${OCEANANIGANS_DRAC_ROOT:?run ocean_setup first}"
cd "$OCEANANIGANS_DRAC_ROOT"
G="${GPUS_PER_NODE:-4}"
MAXNODES="${MAXNODES:-2}"
SIZE="${SIZE:-1024x1024x1024}"
FLOAT="${FLOAT:-Float32}"
SOLVER="${SOLVER:-FourierTridiagonal}"
mkdir -p logs

submit() {   # name nodes tasks_per_node comm
    local mem="--mem=128G"
    [[ "$3" -eq "$G" ]] && mem="--mem=0"           # full node
    local cmd=(sbatch --job-name="$1" --nodes="$2" --ntasks-per-node="$3" "$mem"
               --output="logs/%x_%j.out"
               --export="ALL,SIZE=$SIZE,COMM=$4,SOLVER=$SOLVER,FLOAT=$FLOAT"
               jobs/benchmark_poisson.sh)
    if [[ -n "$DRYRUN" ]]; then echo "${cmd[*]}"; else "${cmd[@]}"; fi
}

submit p1024_1gpu 1 1 MPI
for comm in MPI NCCL; do
    for layout in "1 2" "1 $G" "2 $G"; do
        read -r nodes tasks <<<"$layout"
        (( nodes > MAXNODES )) && continue
        submit "p1024_${comm}_$(( nodes * tasks ))gpu" "$nodes" "$tasks" "$comm"
    done
done
echo "Submitted. Check with: squeue -u \$USER;  results: grep -ah '^RESULT poisson' logs/p1024_*.out"
