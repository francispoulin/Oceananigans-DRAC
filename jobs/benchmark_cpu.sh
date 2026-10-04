#!/bin/bash
# Oceananigans benchmark on one full Nibi CPU node (192 cores, 748 GB), for comparison with the
# same benchmark on one H100. Runs the suite in an Oceananigans checkout (BENCH_DIR), like
# jobs/benchmark.sh. From the repository root:
#
#   Threads only (1 process x 192 threads):
#     sbatch jobs/benchmark_cpu.sh
#   MPI and threads (recommended; 48 x 4 was fastest on Nibi for the 1440x720x200 grid):
#     sbatch --ntasks=48 --cpus-per-task=4 jobs/benchmark_cpu.sh
#
# The grid is split in x only, so the number of processes must divide Nx. Each process also
# needs at least about 23 columns: the split-explicit free surface uses a wide halo (23 for the
# default substeps), and Oceananigans warns that results may be incorrect when a process owns
# fewer columns than that. For Nx = 1440 this means at most about 60 processes (96 is too many). A CPU node is much slower than a GPU, so the run is shortened to 2 warm-up
# steps and 3 windows of 10 steps (the GPU runs used 5 windows of 100).
#SBATCH --job-name=bench_cpu
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=192
#SBATCH --mem=0
#SBATCH --time=3:00:00
#SBATCH --output=%x_%j.out

cd "$SLURM_SUBMIT_DIR"
source env/drac.sh
set -eo pipefail          # after loading modules, as module commands can return harmless errors

BENCH_DIR=${BENCH_DIR:-$SCRATCH/software/Oceananigans.jl/benchmarking}
SIZE=${SIZE:-1440x720x200}
NRANKS=${SLURM_NTASKS}
export JULIA_NUM_THREADS=${SLURM_CPUS_PER_TASK}
cd "$BENCH_DIR"
mkdir -p results

ARGS=(
    --size="$SIZE"
    --grid_type=lat_lon
    --device=CPU
    --warmup_steps=2
    --time_steps=10
    --samples=3
    --output="results/${SLURM_JOB_NAME}_${NRANKS}x${JULIA_NUM_THREADS}_${SLURM_JOB_ID}.json"
)
if (( NRANKS > 1 )); then
    ARGS+=( --distributed --partition="${NRANKS}x1x1" )
fi

echo "Job ${SLURM_JOB_ID}: ${NRANKS} process(es) x ${JULIA_NUM_THREADS} thread(s) on $(hostname), size ${SIZE}"
echo "Arguments: ${ARGS[*]}"
julia --project=. -e 'using Pkg; Pkg.precompile()'
srun --cpu-bind=cores julia --project=. --threads="$JULIA_NUM_THREADS" run_benchmarks.jl "${ARGS[@]}"
