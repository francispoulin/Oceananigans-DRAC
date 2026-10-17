#!/bin/bash
# Submit any GPU job script of this repository on N GPUs (one MPI rank per GPU), with the Slurm
# options right for the cluster: as few nodes as possible, --gpus-per-node equal to the ranks per
# node (every rank sees all of its node's GPUs; never --gpus-per-task, see jobs/gpu_request.sh),
# and --mem=0 when a node's GPUs are all used. From the repository root, after ocean_setup:
#
#     bash jobs/submit_gpu.sh jobs/checks.sh 2                 # 2 GPUs on one node
#     bash jobs/submit_gpu.sh jobs/checks.sh 16                # Nibi: 2 nodes; Fir, Rorqual: 4 nodes
#     bash jobs/submit_gpu.sh jobs/benchmark.sh 8 --time=2:00:00 --export=ALL,SIZE=2880x1440x200
#     DRYRUN=1 bash jobs/submit_gpu.sh jobs/checks.sh 8        # print the sbatch command only
#
# Arguments after the GPU count are passed to sbatch unchanged (and override the defaults).
# Settings: GPUS_PER_NODE (default from the cluster: 8 on Nibi, 4 elsewhere), MEM (memory per node
# when the node is not full, default 64G), JOB_NAME (default <script>_<N>gpu).
# Above one node, N must be a multiple of the GPUs per node. Logs: $JOB_LOGS/<name>_<jobid>.out
# (the repository's logs/, or $OCEAN_JOB_DIR/logs on Trillium).
#
# Without this wrapper (same result), e.g. 16 GPUs on Nibi:
#     sbatch --nodes=2 --ntasks-per-node=8 --gpus-per-node=h100:8 --mem=0 jobs/checks.sh

set -eo pipefail
OCEAN_HPC_ROOT="${OCEAN_HPC_ROOT:-${OCEANANIGANS_DRAC_ROOT:-}}"   # old name: environments set up before the rename
: "${OCEAN_HPC_ROOT:?run ocean_setup first}"
[[ $# -ge 2 && "$2" =~ ^[0-9]+$ && "$2" -ge 1 ]] || {
    echo "usage: bash jobs/submit_gpu.sh <job script> <number of GPUs> [sbatch options...]"; exit 1; }
script="$1"; n="$2"; shift 2
[[ -f "$script" ]] || { echo "no such job script: $script"; exit 1; }
[[ -n "$DRYRUN" ]] || command -v sbatch >/dev/null || {
    echo "no Slurm on this machine ($(hostname -s)): submit from an Alliance cluster;"
    echo "on pelee/rondeau use tools/run_local.sh instead (or DRYRUN=1 to see the sbatch command)"; exit 1; }

source "$OCEAN_HPC_ROOT/jobs/gpu_request.sh"
g="${GPUS_PER_NODE:-$(default_gpus_per_node)}"
if (( n <= g )); then
    nodes=1; per_node=$n
else
    (( n % g == 0 )) || { echo "$n GPUs: above one node, use a multiple of $g (GPUs per node here)"; exit 1; }
    nodes=$(( n / g )); per_node=$g
fi
gpu_request "$per_node" "${MEM:-64G}"
name="${JOB_NAME:-$(basename "$script" .sh)_${n}gpu}"

cmd=(sbatch --job-name="$name" --nodes="$nodes" --ntasks-per-node="$per_node" "${GPU_OPTS[@]}"
     --output="$JOB_LOGS/%x_%j.out" "$@" "$script")
echo "${cmd[*]}"
[[ -n "$DRYRUN" ]] || "${cmd[@]}"
