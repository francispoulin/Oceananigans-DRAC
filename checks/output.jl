# Check 4: NetCDF and JLD2 files can be written and read back while MPI is running.
#
# Each rank writes its own small file in each format to a temporary folder and reads it
# back. NetCDF is the format whose libraries caused the MPI conflict, so this is the check
# that certifies a setup for real workloads.

using CUDA, NCDatasets, JLD2
include(joinpath(@__DIR__, "..", "src", "drac_mpi.jl"))
drac_mpi_init()

comm = MPI.COMM_WORLD
rank = MPI.Comm_rank(comm)
dir = mktempdir(get(ENV, "SLURM_TMPDIR", tempdir()))
data = rand(8, 8) .+ rank

ncfile = joinpath(dir, "check_rank$(rank).nc")
NCDataset(ncfile, "c") do ds
    defDim(ds, "x", 8)
    defDim(ds, "y", 8)
    v = defVar(ds, "a", Float64, ("x", "y"))
    v[:, :] = data
end
nc_back = NCDataset(ds -> ds["a"][:, :], ncfile)

jldfile = joinpath(dir, "check_rank$(rank).jld2")
jldsave(jldfile; data)
jld_back = JLD2.load(jldfile, "data")

ok_nc, ok_jld = nc_back == data, jld_back == data
println("rank $rank: NetCDF ", ok_nc ? "PASS" : "FAIL", ", JLD2 ", ok_jld ? "PASS" : "FAIL")
ok = MPI.Allreduce((ok_nc && ok_jld) ? 1 : 0, MPI.MIN, comm) == 1
rank == 0 && println(ok ? "PASS: NetCDF and JLD2 output" : "FAIL: output")
MPI.Barrier(comm)
ok || exit(1)
