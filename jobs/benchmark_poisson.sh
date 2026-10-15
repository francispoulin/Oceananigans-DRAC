#!/bin/bash
# Always give --gpus-per-node=h100:<ranks per node> (all ranks see all the node's GPUs; never
# --gpus-per-task, see jobs/gpu_request.sh), or submit with the jobs/submit_*.sh scripts.
# Pressure solver alone (benchmarks/poisson_solver.jl) with MPI or NCCL, on any number of GPUs and
# nodes, one MPI rank per GPU, grid split in x. From the repository root, after ocean_setup, once
# the NCCL test environment exists on this cluster (bash setup/setup_nccl_env.sh on a login node):
#
#     sbatch --job-name=p_ft_mpi_4  --ntasks-per-node=4 --gpus-per-node=h100:4 --mem=0 --export=ALL,COMM=MPI  jobs/benchmark_poisson.sh
#     sbatch --job-name=p_ft_nccl_8 --nodes=2 --ntasks-per-node=4 --gpus-per-node=h100:4 --mem=0 --export=ALL,COMM=NCCL jobs/benchmark_poisson.sh
#
# or submit the whole MPI-vs-NCCL set with jobs/submit_poisson_scaling.sh.
# Settings through environment variables: SIZE (GLOBAL grid, default 512x512x256), SOLVER
# (FourierTridiagonal | FFT), COMM (MPI | NCCL), FLOAT (Float64), REPS, WINDOWS, JULIA_ENV
# (default envs/nccl). Fir and Rorqual: 4 GPUs per node.
#SBATCH --job-name=poisson
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --gpus-per-node=h100:1      # submit_*.sh pass h100:<tasks per node> (jobs/gpu_request.sh)
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --time=0:45:00
#SBATCH --output=%x_%j.out

cd "$SLURM_SUBMIT_DIR"
source env/ocean_setup.sh
set -eo pipefail          # after loading modules, as module commands can return harmless errors

JULIA_ENV="${JULIA_ENV:-envs/nccl}"   # not PROJECT: the Alliance clusters set $PROJECT to your project space
[[ -f "$JULIA_ENV/Project.toml" ]] || { echo "no environment in $JULIA_ENV: run setup/setup_nccl_env.sh on a login node first"; exit 1; }
ARGS=( --size="${SIZE:-512x512x256}" --solver="${SOLVER:-FourierTridiagonal}" --comm="${COMM:-MPI}"
       --float="${FLOAT:-Float64}" --reps="${REPS:-20}" --windows="${WINDOWS:-5}" )

echo "Job ${SLURM_JOB_ID} on ${CC_CLUSTER:-?}: ${SLURM_NTASKS} GPU(s) on ${SLURM_JOB_NUM_NODES} node(s): ${ARGS[*]}"
srun bash -c 'echo "  task $SLURM_PROCID on $(hostname): $(nvidia-smi -L)"'
# Compile once with ONE process before the ranks start (ranks compiling NCCL together fail).
# Also a safety check: NCCL's library is chosen per machine (GPU driver), so an environment set up on a
# node without GPUs (Trillium's CPU login node) or on another machine may lack the right one.
julia --project="$JULIA_ENV" -e 'using Pkg; Pkg.precompile(); using Oceananigans, CUDA, NCCL
    v = try NCCL.version() catch; "?" end
    println("  CUDA driver ", CUDA.driver_version(), ", runtime ", CUDA.runtime_version(), ", NCCL ", v)' || {
    echo "ERROR loading CUDA/NCCL on $(hostname). Run once on a login node WITH GPUs (Trillium: trig-login01):"
    echo "    bash setup/setup_nccl_env.sh --this-machine"; exit 1; }
srun --cpu-bind=none julia --project="$JULIA_ENV" benchmarks/poisson_solver.jl "${ARGS[@]}"
