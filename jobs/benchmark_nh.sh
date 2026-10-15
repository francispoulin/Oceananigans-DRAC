#!/bin/bash
# Always give --gpus-per-node=h100:<ranks per node> (all ranks see all the node's GPUs; never
# --gpus-per-task, see jobs/gpu_request.sh), or submit with the jobs/submit_*.sh scripts.
# Nonhydrostatic benchmark (benchmarks/nonhydrostatic_box.jl) on any number of GPUs, one MPI
# rank per GPU, grid split in x. From the repository root, after ocean_setup:
#
#     sbatch --job-name=nh_fft_1 --ntasks-per-node=1 --gpus-per-node=h100:1 jobs/benchmark_nh.sh
#     sbatch --job-name=nh_fft_2 --ntasks-per-node=2 --gpus-per-node=h100:2 jobs/benchmark_nh.sh
#     sbatch --job-name=nh_ft_4  --ntasks-per-node=4 --gpus-per-node=h100:4 --export=ALL,SOLVER=FourierTridiagonal jobs/benchmark_nh.sh
#     sbatch --job-name=nh_fft_16 --nodes=2 --ntasks-per-node=8 --gpus-per-node=h100:8 --mem=0 jobs/benchmark_nh.sh
#
# Settings through environment variables: SIZE (default 512x512x256, global), SOLVER (FFT,
# FourierTridiagonal, ConjugateGradient), FLOAT (Float64), WEAK (false; true = SIZE per GPU),
# STEPS, WINDOWS. On pelee/rondeau use tools/run_local.sh instead (docs/fluidsgpu.md).
#SBATCH --job-name=nh
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --gpus-per-node=h100:1      # submit_*.sh pass h100:<tasks per node> (jobs/gpu_request.sh)
#SBATCH --cpus-per-task=8
# (no #SBATCH --mem: Trillium rejects it; submit_*.sh pass --mem elsewhere, see jobs/gpu_request.sh)
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
