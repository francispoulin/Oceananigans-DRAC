#!/bin/bash
# Nonhydrostatic benchmark (benchmarks/nonhydrostatic_box.jl) on any number of GPUs, one MPI
# rank per GPU, grid split in x. From the repository root, after ocean_setup:
#
#     sbatch --job-name=nh_fft_1 --ntasks-per-node=1 jobs/benchmark_nh.sh
#     sbatch --job-name=nh_fft_2 --ntasks-per-node=2 jobs/benchmark_nh.sh
#     sbatch --job-name=nh_ft_4  --ntasks-per-node=4 --export=ALL,SOLVER=FourierTridiagonal jobs/benchmark_nh.sh
#     sbatch --job-name=nh_fft_16 --nodes=2 --ntasks-per-node=8 --mem=0 jobs/benchmark_nh.sh
#
# Settings through environment variables: SIZE (default 512x512x256, global), SOLVER (FFT,
# FourierTridiagonal, ConjugateGradient), FLOAT (Float64), WEAK (false; true = SIZE per GPU),
# STEPS, WINDOWS. On pelee/rondeau use tools/run_local.sh instead (docs/fluidsgpu.md).
#SBATCH --job-name=nh
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --gpus-per-task=h100:1
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --time=0:45:00
#SBATCH --output=%x_%j.out

cd "$SLURM_SUBMIT_DIR"
source env/ocean_setup.sh
set -eo pipefail          # after loading modules, as module commands can return harmless errors

ARGS=( --size="${SIZE:-512x512x256}" --solver="${SOLVER:-FFT}" --float="${FLOAT:-Float64}"
       --weak="${WEAK:-false}" --steps="${STEPS:-100}" --windows="${WINDOWS:-5}" )

echo "Job ${SLURM_JOB_ID}: ${SLURM_NTASKS} GPU(s) on ${SLURM_JOB_NUM_NODES} node(s): ${ARGS[*]}"
srun bash -c 'echo "  task $SLURM_PROCID on $(hostname): $(nvidia-smi -L)"'
julia --project=. -e 'using Pkg; Pkg.precompile()'
srun --cpu-bind=none julia --project=. benchmarks/nonhydrostatic_box.jl "${ARGS[@]}"
