#!/bin/bash
# Multi-GPU checks, on any number of GPUs (one MPI rank per GPU). From the repository root:
#
#     sbatch --account=def-YOURPI --nodes=1 --ntasks-per-node=2 jobs/checks.sh            # 2 GPUs
#     sbatch --account=def-YOURPI --nodes=1 --ntasks-per-node=8 --mem=0 jobs/checks.sh    # a full Nibi node
#     sbatch --account=def-YOURPI --nodes=2 --ntasks-per-node=8 --mem=0 jobs/checks.sh    # across nodes
#
# Each check prints PASS or FAIL; the job stops at the first failure.
#SBATCH --job-name=checks
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=2
#SBATCH --gpus-per-task=h100:1
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --time=0:30:00
#SBATCH --output=%x_%j.out

cd "$SLURM_SUBMIT_DIR"
source env/drac.sh
set -eo pipefail          # after loading modules, as module commands can return harmless errors
echo "Job ${SLURM_JOB_ID}: ${SLURM_NTASKS} GPU(s) on ${SLURM_JOB_NUM_NODES} node(s)"

echo "== Precompiling (fast if already done)"
julia --project=. -e 'using Pkg; Pkg.precompile()'

echo "== GPU per task (from Slurm; UUIDs must all differ)"
srun bash -c 'echo "  task $SLURM_PROCID on $(hostname): $(nvidia-smi -L)"'

for check in single_mpi cuda_aware_mpi distributed_vs_serial output; do
    echo "== Check: $check"
    srun --cpu-bind=none julia --project=. "checks/${check}.jl"
done
echo "== All checks passed"
