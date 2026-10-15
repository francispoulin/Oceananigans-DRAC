#!/bin/bash
# Always give --gpus-per-node=h100:<ranks per node> (all ranks see all the node's GPUs; never
# --gpus-per-task, see jobs/gpu_request.sh), or submit with the jobs/submit_*.sh scripts.
# Oceananigans benchmark suite on any number of GPUs, as used for the Nibi scaling results.
# Runs the benchmarks in an Oceananigans checkout (its benchmarking/ folder), which needs the
# same MPI setup as this repository: see docs/drac.md, `section 8`.
#
#     sbatch --job-name=bench_gpu4  --nodes=1 --ntasks-per-node=4 --gpus-per-node=h100:4 jobs/benchmark.sh
#     sbatch --job-name=bench_gpu16 --nodes=2 --ntasks-per-node=8 --gpus-per-node=h100:8 --mem=0 jobs/benchmark.sh
#
# Settings through environment variables, for example
#     sbatch --export=ALL,SIZE=2880x1440x200 ... jobs/benchmark.sh
# COMM=NCCL uses NCCLDistributed (needs a suite set up with setup/setup_benchmark_suite.sh, which
# adds --comm and NCCL.jl; not available in the Nibi checkout). Default: MPI (option not passed).
#SBATCH --job-name=bench
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=2
#SBATCH --gpus-per-node=h100:1      # submit_*.sh pass h100:<tasks per node> (jobs/gpu_request.sh)
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --time=1:20:00
#SBATCH --output=%x_%j.out

cd "$SLURM_SUBMIT_DIR"
source env/ocean_setup.sh
set -eo pipefail          # after loading modules, as module commands can return harmless errors

BENCH_DIR=${BENCH_DIR:-$SCRATCH/software/Oceananigans.jl/benchmarking}
SIZE=${SIZE:-1440x720x200}
NGPU=${SLURM_NTASKS}
cd "$BENCH_DIR"
mkdir -p results

ARGS=(
    --size="$SIZE"
    --grid_type=lat_lon
    --device=GPU
    --output="results/${SLURM_JOB_NAME}_${SLURM_JOB_ID}.json"
)
if [[ -n "$DT" ]]; then
    ARGS+=( --dt="$DT" )
fi

PARTITION=${PARTITION:-${NGPU}x1x1}   # default: split in x only; e.g. PARTITION=8x8x1 for 2D
if (( NGPU > 1 )); then
    # Nx (and Ny, for a 2D split) must be divisible by the number of ranks in that direction.
    ARGS+=( --distributed --partition="$PARTITION" )
    [[ -n "$COMM" ]] && ARGS+=( --comm="$COMM" )
fi

echo "Job ${SLURM_JOB_ID} on ${CC_CLUSTER:-?}: ${NGPU} GPU(s) on ${SLURM_JOB_NUM_NODES} node(s), size ${SIZE}, comm ${COMM:-MPI}"
echo "Arguments: ${ARGS[*]}"
srun bash -c 'echo "  task $SLURM_PROCID on $(hostname): $(nvidia-smi -L)"'
julia --project=. -e 'using Pkg; Pkg.precompile()'
if [[ "${COMM^^}" == NCCL ]]; then     # compile NCCL with one process before the ranks start
    julia --project=. -e 'using Oceananigans, CUDA, NCCL
        println("  CUDA driver ", CUDA.driver_version(), ", runtime ", CUDA.runtime_version(), ", NCCL ", try NCCL.version() catch; "?" end)' || {
        echo "ERROR loading CUDA/NCCL on $(hostname): rerun setup/setup_benchmark_suite.sh on a login node with GPUs"; exit 1; }
fi
srun --cpu-bind=none julia --project=. run_benchmarks.jl "${ARGS[@]}"
