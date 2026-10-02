# Check 3: a distributed Oceananigans computation gives the same answer as one GPU.
#
# Each rank computes ∂c/∂x on its part of a grid split in x across all ranks. That needs
# halo exchange between neighbouring ranks, including across the periodic boundary. Each
# rank also computes the same derivative on the whole grid on its own GPU, and compares
# its part. Expected: agreement to round-off (≲ 1e-12 relative).
#
# Requires Nx (64) to be divisible by the number of ranks.

using Oceananigans, CUDA, NCDatasets
using Oceananigans.DistributedComputations: Distributed, Partition
using Oceananigans.BoundaryConditions: fill_halo_regions!
include(joinpath(@__DIR__, "..", "src", "drac_mpi.jl"))
drac_mpi_init()

comm = MPI.COMM_WORLD
n = MPI.Comm_size(comm)
N = (64, 32, 8)
N[1] % n == 0 || error("Nx = $(N[1]) is not divisible by $n ranks")

f(x, y, z) = sin(2π * x) * cos(2π * y) * (1 + z)
domain = (x = (0, 1), y = (0, 1), z = (0, 1))
topology = (Periodic, Periodic, Bounded)

# Distributed
arch = Distributed(GPU(); partition = Partition(n, 1, 1))
rank = arch.local_rank
grid = RectilinearGrid(arch; size = N, domain..., topology)
c = CenterField(grid)
set!(c, f)
fill_halo_regions!(c)
dcdx = Field(∂x(c))
compute!(dcdx)

# The same on the whole grid, on this rank's GPU
serial_grid = RectilinearGrid(GPU(); size = N, domain..., topology)
cs = CenterField(serial_grid)
set!(cs, f)
fill_halo_regions!(cs)
dcdx_serial = Field(∂x(cs))
compute!(dcdx_serial)

nx = N[1] ÷ n
i0 = (arch.local_index[1] - 1) * nx
mine = Array(interior(dcdx))
reference = Array(interior(dcdx_serial))[i0+1:i0+nx, :, :]
err = MPI.Allreduce(maximum(abs, mine .- reference), MPI.MAX, comm)
scale = MPI.Allreduce(maximum(abs, reference), MPI.MAX, comm)

if rank == 0
    println("max |distributed - single GPU| / max |∂c/∂x| = ", err / scale, " on $n ranks")
    println(err / scale < 1e-12 ? "PASS: distributed matches single GPU" :
                                  "FAIL: distributed differs from single GPU")
end
MPI.Barrier(comm)
err / scale < 1e-12 || exit(1)
