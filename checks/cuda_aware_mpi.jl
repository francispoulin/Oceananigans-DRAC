# Check 2: each rank has its own GPU, and GPU arrays pass correctly through MPI
# (CUDA-aware MPI, which Oceananigans' distributed GPU runs rely on).
#
# Ring exchange: rank r sends a GPU array filled with r to rank r+1 (mod n). Works for any
# number of ranks, including one (a rank then sends to itself).
#
# Every rank reports CuDevice(0): with one GPU per task, each rank sees only its own GPU,
# numbered 0. The UUIDs show whether they are really different GPUs.

using CUDA, NCDatasets
include(joinpath(@__DIR__, "..", "src", "drac_mpi.jl"))
drac_mpi_init()

comm = MPI.COMM_WORLD
rank, n = MPI.Comm_rank(comm), MPI.Comm_size(comm)

dev = CUDA.device()
uuid = string(CUDA.uuid(dev))
println("rank $rank on $(gethostname()): $(CUDA.name(dev)), UUID $uuid")

dest, source = mod(rank + 1, n), mod(rank - 1, n)
send = CUDA.fill(Float64(rank), 10^6)
recv = CUDA.zeros(Float64, 10^6)
MPI.Sendrecv!(send, recv, comm; dest, source)
ok = all(Array(recv) .== source)
println("rank $rank received from rank $source: ", ok ? "PASS" : "FAIL")

# Distinct GPUs: gather all UUIDs on rank 0
all_uuids = MPI.gather(uuid, comm; root=0)
distinct = rank == 0 ? length(unique(all_uuids)) == n : true
all_ok = MPI.Allreduce(ok ? 1 : 0, MPI.MIN, comm) == 1
if rank == 0
    println(distinct ? "PASS: $n ranks on $n different GPUs" : "FAIL: ranks share GPUs: $all_uuids")
    println(all_ok ? "PASS: CUDA-aware MPI" : "FAIL: CUDA-aware MPI")
end
MPI.Barrier(comm)
(all_ok && distinct) || exit(1)
