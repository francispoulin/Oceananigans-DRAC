#!/bin/bash
# Environment for Oceananigans on the Waterloo fluids group's GPU servers, pelee and rondeau
# (4x A100 each, shared drive, no Slurm). Source env/ocean_setup.sh, which sources this file.
#
# Not everyone has access to these machines. The file is also an example for any server
# without Slurm and with locally built modules: change the block marked MACHINE-SPECIFIC.

_fluids_depot="${JULIA_DEPOT_PATH%%:*}"      # remember the user's depot before loading modules

# ---- MACHINE-SPECIFIC ------------------------------------------------------------------
# TODO(verify on pelee): module names, and whether a purge is needed/safe here.
module purge >/dev/null 2>&1
module load openmpi/4.1.7-with-cuda          # CUDA-aware OpenMPI built for the group
module load julia/1.10.8                     # 1.10.10 on the Alliance; same 1.10 series

# Default depot for this machine (shared drive, visible from both pelee and rondeau).
# Override by setting JULIA_DEPOT_PATH before sourcing.
_fluids_default_depot="$HOME/julia_depot"    # TODO(verify): is $HOME on the shared drive?
# ----------------------------------------------------------------------------------------

export OCEAN_MACHINE="$(hostname -s)"

# The system OpenMPI prefix. Derived from mpiexec on PATH, so it works whether or not the
# module sets a variable for it.
if command -v mpiexec >/dev/null 2>&1; then
    export OCEAN_MPI_ROOT="$(dirname "$(dirname "$(readlink -f "$(command -v mpiexec)")")")"
else
    echo "fluidsgpu.sh: mpiexec not found; is the openmpi module loaded?" >&2
    unset OCEAN_MPI_ROOT
fi
export OPAL_PREFIX="$OCEAN_MPI_ROOT"

export OCEANANIGANS_DRAC_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export JULIA_DEPOT_PATH="${_fluids_depot:-$_fluids_default_depot}"
export JULIA_NUM_THREADS="${JULIA_NUM_THREADS:-1}"
export JULIA_NUM_PRECOMPILE_TASKS="${JULIA_NUM_PRECOMPILE_TASKS:-2}"

unset _fluids_depot _fluids_default_depot

echo "Oceananigans-DRAC environment ($OCEAN_MACHINE): repo=$OCEANANIGANS_DRAC_ROOT, depot=$JULIA_DEPOT_PATH"
