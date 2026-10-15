#!/bin/bash
# Pressure solver alone (benchmarks/poisson_solver.jl) with MPI or NCCL, on any number of GPUs and
# nodes, one MPI rank per GPU, grid split in x. From the repository root, after ocean_setup, once
# the NCCL test environment exists on this cluster (bash setup/setup_nccl_env.sh on a login node):
#
#     sbatch --job-name=p_ft_mpi_4  --ntasks-per-node=4 --mem=0 --export=ALL,COMM=MPI  jobs/benchmark_poisson.sh
#     sbatch --job-name=p_ft_nccl_8 --nodes=2 --ntasks-per-node=4 --mem=0 --export=ALL,COMM=NCCL jobs/benchmark_poisson.sh
#
# or submit the whole MPI-vs-NCCL set with jobs/submit_poisson_scaling.sh.
# Settings through environment variables: SIZE (GLOBAL grid, default 512x512x256), SOLVER
# (FourierTridiagonal | FFT), COMM (MPI | NCCL), FLOAT (Float64), REPS, WINDOWS, JULIA_ENV
# (default envs/nccl). Fir and Rorqual: 4 GPUs per node.
#SBATCH --job-name=poisson
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

JULIA_ENV="${JULIA_ENV:-envs/nccl}"   # not PROJECT: the Alliance clusters set $PROJECT to your project space
[[ -f "$JULIA_ENV/Project.toml" ]] || { echo "no environment in $JULIA_ENV: run setup/setup_nccl_env.sh on a login node first"; exit 1; }
ARGS=( --size="${SIZE:-512x512x256}" --solver="${SOLVER:-FourierTridiagonal}" --comm="${COMM:-MPI}"
       --float="${FLOAT:-Float64}" --reps="${REPS:-20}" --windows="${WINDOWS:-5}" )

echo "Job ${SLURM_JOB_ID} on ${CC_CLUSTER:-?}: ${SLURM_NTASKS} GPU(s) on ${SLURM_JOB_NUM_NODES} node(s): ${ARGS[*]}"
srun bash -c 'echo "  task $SLURM_PROCID on $(hostname): $(nvidia-smi -L)"'
# Compile once with ONE process before the ranks start (ranks compiling NCCL together fail).
julia --project="$JULIA_ENV" -e 'using Pkg; Pkg.precompile(); using Oceananigans, CUDA, NCCL'
srun --cpu-bind=none julia --project="$JULIA_ENV" benchmarks/poisson_solver.jl "${ARGS[@]}"
