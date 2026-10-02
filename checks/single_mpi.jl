# Check 1: exactly one MPI is loaded, and it is the system OpenMPI.
#
# Loads everything a real run would (including NCDatasets, which pulls in Julia's own
# OpenMPI through NetCDF_jll), initializes MPI, then lists every MPI library and OpenMPI
# plugin in the process. All must come from /cvmfs; anything from the Julia depot's
# "artifacts" folder means two MPIs are mixed. Works with any number of ranks.

using Oceananigans, CUDA, NCDatasets, JLD2
using Libdl
include(joinpath(@__DIR__, "..", "src", "drac_mpi.jl"))
drac_mpi_init()

comm = MPI.COMM_WORLD
rank = MPI.Comm_rank(comm)

mpi_libs = filter(l -> occursin(r"libmpi|libopen-pal|libopen-rte|/mca_", l), Libdl.dllist())
foreign = filter(l -> occursin("/artifacts/", l) &&
                      occursin(r"libmpi\.so|libopen-pal|libopen-rte|/mca_", l), mpi_libs)
		 
if rank == 0
    println("OPAL_PREFIX = ", ENV["OPAL_PREFIX"])
    println("MPI libraries and plugins loaded on rank 0:")
    foreach(l -> println("  ", l), mpi_libs)
end
ok = MPI.Allreduce(isempty(foreign) ? 1 : 0, MPI.MIN, comm) == 1
rank == 0 && println(ok ? "PASS: one MPI, the system OpenMPI" :
                          "FAIL: Julia's own MPI libraries are loaded: $foreign")
MPI.Barrier(comm)
ok || exit(1)
