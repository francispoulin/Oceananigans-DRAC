#!/bin/bash
# Environment for Oceananigans on Nibi (SHARCNET). Source it, don't run it:
#
#     source env/nibi.sh
#
# Used by setup/setup.sh and by every job script, so that setup and jobs always see the
# same modules and the same Julia depot.

module purge                 # some modules are "sticky" and stay loaded: that is normal
module load StdEnv/2023
module load gcc/12.3
module load openmpi/4.1.5
module load cuda/12.6
module load julia/1.10.10

# Root of this repository (the folder containing env/), for scripts that need it.
export OCEANANIGANS_DRAC_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Julia depot: where packages and compiled code are stored. Keep it out of $HOME (small
# quota). Override by setting JULIA_DEPOT_PATH before sourcing this file.
# TODO (verification): check Nibi's scratch purge policy; if old files are purged, a depot
# on $SCRATCH can silently lose packages, and a project directory is the safer default.
export JULIA_DEPOT_PATH="${JULIA_DEPOT_PATH:-$SCRATCH/julia_depot}"

# One CPU thread per rank is enough when the work is on the GPU.
export JULIA_NUM_THREADS="${JULIA_NUM_THREADS:-1}"

echo "Oceananigans-DRAC environment (Nibi): repo=$OCEANANIGANS_DRAC_ROOT, depot=$JULIA_DEPOT_PATH"
