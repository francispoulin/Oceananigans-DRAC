#!/bin/bash
# One-time setup on a LOGIN node (it needs internet access). From the repository root:
#
#     bash setup/setup.sh
#
# Steps:
#   1. install the packages (exact tested versions if Manifest.toml is present)
#   2. make MPI.jl use the system OpenMPI (MPIPreferences)
#   3. redirect OpenMPI_jll, which NetCDF/HDF5 load, to the same system OpenMPI library
#   4. precompile
# It writes LocalPreferences.toml (machine-specific, so not under version control).

cd "$(dirname "${BASH_SOURCE[0]}")/.."
source env/nibi.sh
set -eo pipefail          # after loading modules, as module commands can return harmless errors

echo "== 1. Packages"
if [[ -f Manifest.toml ]]; then
    julia --project=. -e 'using Pkg; Pkg.instantiate()'
else
    julia --project=. -e 'using Pkg; Pkg.add(["Oceananigans", "CUDA", "MPI", "MPIPreferences",
                                              "OpenMPI_jll", "Preferences", "NCDatasets", "JLD2"])'
fi

echo "== 2. MPI.jl -> system OpenMPI"
julia --project=. -e 'using MPIPreferences; MPIPreferences.use_system_binary()'

echo "== 3. OpenMPI_jll -> system OpenMPI library"
LIBMPI="$EBROOTOPENMPI/lib/libmpi.so"
if [[ -z "$EBROOTOPENMPI" || ! -f "$LIBMPI" ]]; then
    echo "ERROR: cannot find the system libmpi ('$LIBMPI'). Is the openmpi module loaded?"
    exit 1
fi
julia --project=. -e "using Preferences, OpenMPI_jll
                      set_preferences!(OpenMPI_jll, \"libmpi_path\" => \"$LIBMPI\"; force=true)"
# The preference takes effect in a new Julia session:
julia --project=. -e 'using OpenMPI_jll; println("   OpenMPI_jll.libmpi_path = ", OpenMPI_jll.libmpi_path)'

echo "== 4. Precompile"
julia --project=. -e 'using Pkg; Pkg.precompile()'

echo
echo "Setup done. The libmpi_path above must be under /cvmfs, not in your Julia depot."
echo "Next: sbatch jobs/hello_cpu.sh, then jobs/hello_gpu.sh, then jobs/checks.sh"
