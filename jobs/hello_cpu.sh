#!/bin/bash
# First test: Oceananigans on a CPU compute node. From the repository root:
#     sbatch --account=def-YOURPI jobs/hello_cpu.sh
#SBATCH --job-name=hello_cpu
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=0:30:00
#SBATCH --output=%x_%j.out

cd "$SLURM_SUBMIT_DIR"
source env/drac.sh
set -eo pipefail          # after loading modules, as module commands can return harmless errors
julia --project=. examples/hello_oceananigans.jl CPU
