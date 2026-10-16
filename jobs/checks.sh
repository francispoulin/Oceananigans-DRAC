#!/bin/bash
# Multi-GPU checks, on any number of GPUs (one MPI rank per GPU). From the repository root:
#
#     bash jobs/submit_gpu.sh jobs/checks.sh 2      # 2 GPUs
#     bash jobs/submit_gpu.sh jobs/checks.sh 8      # a full Nibi node (2 nodes on Fir, Rorqual)
#     bash jobs/submit_gpu.sh jobs/checks.sh 16     # across nodes
#
# Without the wrapper, give --gpus-per-node equal to --ntasks-per-node (never --gpus-per-task),
# and --mem=0 when the job uses all of a node's GPUs, e.g. on Nibi:
#     sbatch --nodes=2 --ntasks-per-node=8 --gpus-per-node=h100:8 --mem=0 jobs/checks.sh
# Not for Trillium (read-only project space in jobs): use tools/run_tests.sh there.
#
# Each check prints PASS or FAIL; the job stops at the first failure.
#SBATCH --job-name=checks
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=2
#SBATCH --gpus-per-node=h100:2      # = ntasks-per-node; submit_gpu.sh sets both
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --time=0:30:00
#SBATCH --output=%x_%j.out

cd "$SLURM_SUBMIT_DIR"
source env/ocean_setup.sh
set -eo pipefail          # after loading modules, as module commands can return harmless errors
echo "Job ${SLURM_JOB_ID}: ${SLURM_NTASKS} GPU(s) on ${SLURM_JOB_NUM_NODES} node(s)"

echo "== Precompiling (fast if already done)"
julia --project=. -e 'using Pkg; Pkg.precompile()'

echo "== GPUs visible to each task (every rank sees all of its node's GPUs)"
srun bash -c 'echo "  task $SLURM_PROCID on $(hostname): $(nvidia-smi -L)"'

for check in single_mpi cuda_aware_mpi distributed_vs_serial output; do
    echo "== Check: $check"
    srun --cpu-bind=none julia --project=. "checks/${check}.jl"
done
echo "== All checks passed"
