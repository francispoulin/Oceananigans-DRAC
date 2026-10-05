#!/bin/bash
# Make a Julia project use the cluster's OpenMPI, for MPI.jl and for OpenMPI_jll (which NetCDF
# and HDF5 load). For a project folder other than this repository; once per cluster, on a LOGIN
# node (it needs internet):
#
#     bash /path/to/Oceananigans-DRAC/setup/configure_mpi.sh /path/to/your/project
#
# It makes sure MPIPreferences, Preferences and OpenMPI_jll (4.1.10 or later in 4.1) are in the
# project, then does steps 2 and 3 of setup/setup.sh there. It writes LocalPreferences.toml in
# that folder (machine-specific: do not commit it).

DRAC_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -z "$1" || ! -f "$1/Project.toml" ]]; then
    echo "usage: bash configure_mpi.sh <folder containing Project.toml>"; exit 1
fi
PROJECT_DIR="$(cd "$1" && pwd)"
source "$DRAC_ROOT/env/drac.sh"
set -eo pipefail
export JULIA_NUM_PRECOMPILE_TASKS=${JULIA_NUM_PRECOMPILE_TASKS:-2}
export OPENBLAS_NUM_THREADS=1
export DRAC_MPILIB_DIR="$EBROOTOPENMPI/lib"
export DRAC_LIBMPI="$DRAC_MPILIB_DIR/libmpi.so"
[[ -f "$DRAC_LIBMPI" ]] || { echo "ERROR: cannot find '$DRAC_LIBMPI'. Is the openmpi module loaded?"; exit 1; }

echo "== 1. Packages in $PROJECT_DIR"
julia --project="$PROJECT_DIR" -e '
    using Pkg
    deps = keys(Pkg.project().dependencies)
    for p in ("MPIPreferences", "Preferences")
        p in deps || Pkg.add(p)
    end
    "OpenMPI_jll" in deps || Pkg.add(name="OpenMPI_jll", version="4.1.10")
    Pkg.compat("OpenMPI_jll", "~4.1.10")
    # An existing Manifest may hold an older OpenMPI_jll that the new compat excludes;
    # Pkg.resolve would keep it and fail, so update that one package.
    Pkg.update("OpenMPI_jll")
    Pkg.instantiate()'

echo "== 2. MPI.jl -> system OpenMPI ($DRAC_MPILIB_DIR)"
julia --project="$PROJECT_DIR" -e '
    using MPIPreferences
    MPIPreferences.use_system_binary(; extra_paths=[ENV["DRAC_MPILIB_DIR"]])'

echo "== 3. OpenMPI_jll -> system OpenMPI library"
julia --project="$PROJECT_DIR" -e '
    using Preferences, OpenMPI_jll
    set_preferences!(OpenMPI_jll, "libmpi_path" => ENV["DRAC_LIBMPI"]; force=true)'
julia --project="$PROJECT_DIR" -e 'using OpenMPI_jll; println("   libmpi_path = ", OpenMPI_jll.libmpi_path)'

echo "== 4. Precompile and check"
julia --project="$PROJECT_DIR" -e 'using Pkg; Pkg.precompile(); using MPI; println("   imports OK")'
echo "Done. libmpi_path above must be under /cvmfs. Commit Project.toml and Manifest.toml, not LocalPreferences.toml."
