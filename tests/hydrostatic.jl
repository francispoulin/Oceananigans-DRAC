# Test: a HydrostaticFreeSurfaceModel time-steps on 1 or more GPUs (grid split in x), and the
# distributed result matches the same model on one GPU.
#
# Small channel like the Gulf Stream setup: periodic in x, walls in y, WENO(5), f-plane,
# buoyancy tracer, split-explicit free surface with a FIXED number of substeps (required on
# distributed grids), RK3. Deterministic initial state: a geostrophic-like jet in b plus a
# small sinusoidal perturbation. 30 steps.
#
# With n > 1 ranks, every rank also runs the whole model on its own GPU and compares its part.
# Expected agreement: round-off growth only (relative difference well below 1e-8).
# Nx = 64 must be divisible by the number of ranks.

using Oceananigans, CUDA, NCDatasets
using Printf
include(joinpath(ENV["OCEANANIGANS_DRAC_ROOT"], "src", "drac_mpi.jl"))
drac_mpi_init()

comm = MPI.COMM_WORLD
rank, n = MPI.Comm_rank(comm), MPI.Comm_size(comm)
N = (64, 32, 16)
N[1] % n == 0 || error("Nx = $(N[1]) is not divisible by $n ranks")
Lx, Ly, Lz = 640e3, 320e3, 1000.0
nsteps, Δt = 30, 300.0

bᵢ(x, y, z) = 1e-4 * z + 2e-3 * tanh(y / 50e3) * exp(z / 300) + 1e-5 * sin(2π * x / Lx) * exp(-(y / 50e3)^2)

function build(arch)
    grid = RectilinearGrid(arch; size = N, halo = (4, 4, 4), x = (0, Lx), y = (-Ly / 2, Ly / 2), z = (-Lz, 0),
                           topology = (Periodic, Bounded, Bounded))
    model = HydrostaticFreeSurfaceModel(grid;
                                        momentum_advection = WENO(order = 5),
                                        tracer_advection = WENO(order = 5),
                                        buoyancy = BuoyancyTracer(), tracers = :b,
                                        coriolis = FPlane(f = 1e-4),
                                        free_surface = SplitExplicitFreeSurface(grid; substeps = 20),
                                        timestepper = :SplitRungeKutta3)
    set!(model, b = bᵢ)
    return model
end

arch = n == 1 ? GPU() : Distributed(GPU(); partition = Partition(n, 1, 1))
model = build(arch)
t0 = time()
for _ in 1:nsteps
    time_step!(model, Δt)
end
CUDA.synchronize()
elapsed = time() - t0

u, b = model.velocities.u, model.tracers.b
finite_local = all(isfinite, interior(u)) && all(isfinite, interior(b))
finite = MPI.Allreduce(finite_local ? 1 : 0, MPI.MIN, comm) == 1
umax = MPI.Allreduce(maximum(abs, interior(u)), MPI.MAX, comm)
rank == 0 && @printf("%d steps on %d GPU(s) in %.1f s (incl. compilation), max|u| = %.3e m/s, finite = %s\n",
                     nsteps, n, elapsed, umax, finite)

ok = finite && umax > 0
if n > 1 && ok
    serial = build(GPU())                        # the whole model on this rank's GPU
    for _ in 1:nsteps
        time_step!(serial, Δt)
    end
    nx = N[1] ÷ n
    i0 = (arch.local_index[1] - 1) * nx
    worst = 0.0
    for (name, d, s) in (("u", u, serial.velocities.u), ("v", model.velocities.v, serial.velocities.v),
                         ("b", b, serial.tracers.b))
        mine = Array(interior(d))
        ref  = Array(interior(s))[i0+1:i0+nx, :, :]
        err  = MPI.Allreduce(maximum(abs, mine .- ref), MPI.MAX, comm)
        scl  = MPI.Allreduce(maximum(abs, ref), MPI.MAX, comm)
        rank == 0 && @printf("  %s: max |distributed - single GPU| / max |single| = %.2e\n", name, err / scl)
        worst = max(worst, err / scl)
    end
    ok = worst < 1e-8
end

rank == 0 && println(ok ? "PASS: hydrostatic model on $n GPU(s)" * (n > 1 ? ", matches single GPU" : "") :
                          "FAIL: hydrostatic model on $n GPU(s)")
MPI.Barrier(comm)
ok || exit(1)
