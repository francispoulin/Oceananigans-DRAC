#!/bin/bash
# Second test: Oceananigans on one GPU. From the repository root:
#     sbatch --account=def-YOURPI jobs/hello_gpu.sh
#SBATCH --job-name=hello_gpu
#SBATCH --ntasks=1
#SBATCH --gpus-per-task=h100:1
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --time=0:30:00
#SBATCH --output=%x_%j.out

cd "$SLURM_SUBMIT_DIR"
source env/drac.sh
set -eo pipefail          # after loading modules, as module commands can return harmless errors
nvidia-smi -L
nvidia-smi --query-gpu=name,memory.used,memory.total --format=csv
julia --project=. examples/hello_oceananigans.jl GPU
