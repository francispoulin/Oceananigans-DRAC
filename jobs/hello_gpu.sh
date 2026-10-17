#!/bin/bash
# Second test: Oceananigans on one GPU. From the repository root:
#     sbatch jobs/hello_gpu.sh
#SBATCH --job-name=hello_gpu
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --gpus-per-node=h100:1      # per node, never --gpus-per-task (see jobs/gpu_request.sh)
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --time=0:30:00
#SBATCH --output=%x_%j.out

[[ "${1:-}" == -h || "${1:-}" == --help ]] && { sed -n '2,/^[^#]/{/^#SBATCH/d;/^# *shellcheck/d;s/^# \{0,1\}//p;}' "$0"; exit 0; }   # -h: usage
cd "$SLURM_SUBMIT_DIR"
source env/ocean_setup.sh
set -eo pipefail          # after loading modules, as module commands can return harmless errors
nvidia-smi -L
nvidia-smi --query-gpu=name,memory.used,memory.total --format=csv
julia --project=. examples/hello_oceananigans.jl GPU
