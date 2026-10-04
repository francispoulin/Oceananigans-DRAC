#!/bin/bash
# Oceananigans benchmark suite on any number of GPUs, as used for the Nibi scaling results.
# Runs the benchmarks in an Oceananigans checkout (its benchmarking/ folder), which needs the
# same MPI setup as this repository: see docs/nibi.md, "Running the Oceananigans benchmarks".
#
#     sbatch --account=def-YOURPI --job-name=bench_gpu4  --nodes=1 --ntasks-per-node=4 jobs/benchmark.sh
#     sbatch --account=def-YOURPI --job-name=bench_gpu16 --nodes=2 --ntasks-per-node=8 --mem=0 jobs/benchmark.sh
#
# Settings through environment variables, for example
#     sbatch --export=ALL,SIZE=2880x1440x200 ... jobs/benchmark.sh
#SBATCH --job-name=bench
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=2
#SBATCH --gpus-per-task=h100:1
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --time=1:20:00
#SBATCH --output=%x_%j.out

cd "$SLURM_SUBMIT_DIR"
source env/drac.sh
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
if (( NGPU > 1 )); then
    # Split in x only: Nx must be divisible by the number of GPUs.
    ARGS+=( --distributed --partition="${NGPU}x1x1" )
fi

echo "Job ${SLURM_JOB_ID}: ${NGPU} GPU(s) on ${SLURM_JOB_NUM_NODES} node(s), size ${SIZE}"
echo "Arguments: ${ARGS[*]}"
srun bash -c 'echo "  task $SLURM_PROCID on $(hostname): $(nvidia-smi -L)"'
julia --project=. -e 'using Pkg; Pkg.precompile()'
srun --cpu-bind=none julia --project=. run_benchmarks.jl "${ARGS[@]}"
