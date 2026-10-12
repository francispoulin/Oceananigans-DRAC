#!/bin/bash
# Plotting job (movies, growth rates, ...) on an Alliance CPU node, with the viz environment.
# Submit FROM YOUR PROJECT FOLDER, after `ocean_setup` (it exports OCEANANIGANS_DRAC_ROOT):
#
#     cd /path/to/BeaufortGyreSimulations
#     sbatch $OCEANANIGANS_DRAC_ROOT/jobs/viz.sh scripts/make_movies.jl
#
# Each argument is one Julia command line, run in order; quote it if the script takes arguments:
#
#     sbatch $OCEANANIGANS_DRAC_ROOT/jobs/viz.sh scripts/make_movies.jl "scripts/growth.jl run.toml"
#
# Override resources on the command line, e.g. sbatch --time=6:00:00 --mem=64G ...
# On pelee/rondeau (no Slurm) use tools/run_local.sh instead.
#SBATCH --job-name=viz
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=32000M
#SBATCH --time=3:00:00
#SBATCH --output=%x_%j.out

: "${OCEANANIGANS_DRAC_ROOT:?run ocean_setup before sbatch, so the job knows where the repository is}"
[[ $# -gt 0 ]] || { echo "usage: sbatch jobs/viz.sh script.jl [\"script2.jl args\" ...]"; exit 1; }

cd "$SLURM_SUBMIT_DIR"
source "$OCEANANIGANS_DRAC_ROOT/env/ocean_setup.sh"
set -eo pipefail          # after loading modules, as module commands can return harmless errors

for cmd in "$@"; do
    echo "== $(date '+%F %T')  julia --project=viz $cmd"
    # shellcheck disable=SC2086   # word splitting is intended: "script.jl arg1 arg2"
    julia --project="$OCEANANIGANS_DRAC_ROOT/viz" $cmd
done
echo "== $(date '+%F %T')  done"
