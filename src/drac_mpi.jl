# Oceananigans-DRAC: initialize MPI safely on DRAC (Digital Research Alliance of Canada) clusters.
#
# Why this exists
# ---------------
# Packages that write NetCDF or HDF5 output (NCDatasets, and anything built on it) load
# NetCDF_jll / HDF5_jll, which in turn load OpenMPI_jll: Julia's own copy of OpenMPI.
# setup/setup.sh redirects OpenMPI_jll to the system OpenMPI library, but when OpenMPI_jll
# loads it still sets the environment variable OPAL_PREFIX to its own folder. The system
# OpenMPI then loads Julia's OpenMPI plugins at MPI.Init() and crashes with
#
#     symbol lookup error: .../artifacts/.../lib/openmpi/mca_pmix_pmix3x.so:
#     undefined symbol: opal_libevent2022_evthread_use_pthreads
#
# drac_mpi_init() points OPAL_PREFIX back at the OpenMPI installation whose library is
# actually loaded, then initializes MPI.
#
# Usage: after ALL `using` statements, and before anything that initializes MPI
# (for example Oceananigans' `Distributed(GPU())`):
#
#     using Oceananigans, CUDA, NCDatasets
#     include(joinpath(ENV["OCEANANIGANS_DRAC_ROOT"], "src", "drac_mpi.jl"))
#     drac_mpi_init()

using MPI
import OpenMPI_jll

"""
    system_openmpi_prefix()

Installation prefix of the OpenMPI library that OpenMPI_jll has been redirected to by
setup/setup.sh. Errors if OpenMPI_jll still points at Julia's own copy.
"""
function system_openmpi_prefix()
    lib = OpenMPI_jll.libmpi_path
    if occursin("/artifacts/", lib)
        error("OpenMPI_jll still uses Julia's own OpenMPI ($lib). " *
              "Run setup/setup.sh (with the openmpi module loaded) and try again.")
    end
    return dirname(dirname(lib))   # .../openmpi/4.1.5/lib/libmpi.so -> .../openmpi/4.1.5
end

"""
    drac_mpi_init()

Point OPAL_PREFIX at the system OpenMPI, then initialize MPI if it is not already.
"""
function drac_mpi_init()
    ENV["OPAL_PREFIX"] = system_openmpi_prefix()
    MPI.Initialized() || MPI.Init()
    return nothing
end
