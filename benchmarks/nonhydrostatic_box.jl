# Nonhydrostatic benchmark: time per step of a NonhydrostaticModel in a stratified, rotating box,
# on 1 or more GPUs (one MPI rank per GPU, grid split in x). Same configuration as the
# `nonhydrostatic` case of the newer Oceananigans benchmark suite (benchmarking/src/
# nonhydrostatic_box.jl on Oceananigans main), written for the Oceananigans version in this
# repository (0.113.5), with multi-GPU support and the same timing method as our hydrostatic runs.
#
#   Box 1 km x 1 km x 500 m, Periodic x Periodic x Bounded, WENO(5), f = 1e-4, buoyancy tracer,
#   N^2 = 1e-5, U = 0.05 m/s mean flow + deterministic sinusoidal perturbation. RK3, fixed dt.
#
# Pressure solvers (--solver):
#   FFT                 uniform grid; 1 GPU: FFTBasedPoissonSolver, several: DistributedFFTBasedPoissonSolver
#   FourierTridiagonal  z stretched (ExponentialDiscretization); several GPUs: the distributed version
#   ConjugateGradient   seamount (immersed boundary), FFT-preconditioned CG. Single GPU only
#                       (not supported on distributed grids in this version, as far as we know).
#
# Usage (from the repository root, after ocean_setup):
#   pelee/rondeau:  bash tools/run_local.sh --wait -n 2 -j nh_fft_2gpu benchmarks/nonhydrostatic_box.jl --solver=FFT
#   Alliance:       sbatch --ntasks-per-node=2 jobs/benchmark_nh.sh            (see that file)
#
# Options (all --name=value):
#   --size=512x512x256   GLOBAL grid size for strong scaling (Nx must be divisible by the GPUs,
#                        Ny too: distributed Poisson solver). With --weak, the size PER GPU (Nx is
#                        multiplied by the number of GPUs).
#   --weak=false
#   --solver=FFT         FFT | FourierTridiagonal | ConjugateGradient
#   --float=Float64      Float64 | Float32
#   --steps=100          time steps per timing window
#   --windows=5          timing windows
#   --warmup=10          untimed steps first (compilation)
#   --dt=0               0 = automatic: 0.2 * min(dx, dz) / 0.06 m/s
#   --output=            JSON file (default results/raw/nh_<solver>_<size>_<n>gpu_<date>.json;
#                        results/raw/ is not under version control)
#   --device=GPU         GPU | CPU
#
# Prints one line starting with "RESULT" (easy to grep) and writes a JSON file (rank 0).

using Oceananigans
using Oceananigans.Solvers: ConjugateGradientPoissonSolver
using MPI
using Printf, Dates, Statistics

# ---------------------------------------------------------------- options
function parse_options(args)
    opts = Dict("size" => "512x512x256", "weak" => "false", "solver" => "FFT", "float" => "Float64",
                "steps" => "100", "windows" => "5", "warmup" => "10", "dt" => "0",
                "output" => "", "device" => "GPU")
    for a in args
        m = match(r"^--([a-z_]+)=(.*)$", a)
        m === nothing && error("bad argument '$a' (use --name=value)")
        haskey(opts, m[1]) || error("unknown option --$(m[1]); known: $(join(sort(collect(keys(opts))), ", "))")
        opts[m[1]] = m[2]
    end
    return opts
end

opts     = parse_options(ARGS)
solver   = opts["solver"]
solver in ("FFT", "FourierTridiagonal", "ConjugateGradient") || error("--solver must be FFT, FourierTridiagonal or ConjugateGradient")
FT       = opts["float"] == "Float32" ? Float32 : opts["float"] == "Float64" ? Float64 : error("--float must be Float64 or Float32")
weak     = lowercase(opts["weak"]) in ("true", "1", "yes")
nsteps   = parse(Int, opts["steps"])
nwindows = parse(Int, opts["windows"])
nwarmup  = parse(Int, opts["warmup"])
Nx0, Ny, Nz = parse.(Int, split(opts["size"], 'x'))

# ---------------------------------------------------------------- MPI and architecture
use_gpu = opts["device"] == "GPU"
use_gpu && @eval using CUDA

# Start MPI the safe way on our machines (see src/drac_mpi.jl), also for one rank.
include(joinpath(ENV["OCEANANIGANS_DRAC_ROOT"], "src", "drac_mpi.jl"))
drac_mpi_init()
comm   = MPI.COMM_WORLD
rank   = MPI.Comm_rank(comm)
nranks = MPI.Comm_size(comm)
say(x...) = rank == 0 && (println(x...); flush(stdout))

Nx = weak ? Nx0 * nranks : Nx0
Nx % nranks == 0 || error("Nx = $Nx is not divisible by $nranks GPUs")
Ny % nranks == 0 || error("Ny = $Ny must be divisible by the number of GPUs ($nranks) for the distributed Poisson solver")
solver == "ConjugateGradient" && nranks > 1 && error("--solver=ConjugateGradient: single GPU only in this benchmark")

child = use_gpu ? GPU() : CPU()
arch  = nranks == 1 ? child : Distributed(child; partition = Partition(nranks, 1, 1))

# ---------------------------------------------------------------- model (as nonhydrostatic_box)
Oceananigans.defaults.FloatType = FT
Lx = Ly = FT(1000)
Lz = FT(500)
z  = solver == "FourierTridiagonal" ? ExponentialDiscretization(Nz, -Lz, 0; scale = Lz / 2) : (-Lz, 0)

grid = RectilinearGrid(arch; size = (Nx, Ny, Nz), halo = (4, 4, 4),
                       x = (0, Lx), y = (0, Ly), z, topology = (Periodic, Periodic, Bounded))

pressure_solver = nothing        # let the model choose (distributed solver on several GPUs)
if solver == "ConjugateGradient"
    seamount(x, y) = -Lz + 100 * exp(-((x - Lx / 2)^2 + (y - Ly / 2)^2) / 200^2)
    grid = ImmersedBoundaryGrid(grid, GridFittedBottom(seamount))
    pressure_solver = ConjugateGradientPoissonSolver(grid)
end

model = NonhydrostaticModel(grid; pressure_solver,
                            advection = WENO(FT; order = 5),
                            coriolis  = FPlane(FT; f = 1e-4),
                            buoyancy  = BuoyancyTracer(),
                            tracers   = :b)

U, ε, N² = 0.05, 0.005, 1e-5
uᵢ(x, y, z) = U + ε * sin(6π * x / Lx) * cos(4π * y / Ly) * cos(π * z / Lz)
vᵢ(x, y, z) =     ε * cos(4π * x / Lx) * sin(6π * y / Ly) * cos(π * z / Lz)
bᵢ(x, y, z) = N² * z
set!(model, u = uᵢ, v = vᵢ, b = bᵢ)

Δx  = Lx / Nx
zcolumn = RectilinearGrid(CPU(); size = (1, 1, Nz), x = (0, 1), y = (0, 1), z,
                          topology = (Periodic, Periodic, Bounded))    # small CPU copy of z
Δzmin = minimum(diff(collect(znodes(zcolumn, Face()))))
Δt  = parse(Float64, opts["dt"])
Δt  = Δt > 0 ? Δt : 0.2 * min(Δx, Δzmin) / 0.06
Δt  = FT(Δt)

say("Nonhydrostatic box: ", Nx, "x", Ny, "x", Nz, " (", round(Nx * Ny * Nz / 1e6, digits = 1), "M cells), ",
    nranks, " rank(s) on ", use_gpu ? "GPU" : "CPU", ", solver ", solver, ", ", FT, ", dt = ", Δt, " s",
    weak ? " (weak scaling)" : "")
say("pressure solver: ", nameof(typeof(model.pressure_solver)))

# ---------------------------------------------------------------- timing
sync() = (use_gpu && CUDA.synchronize(); MPI.Barrier(comm))

for _ in 1:nwarmup
    time_step!(model, Δt)
end
sync()

times = Float64[]
for w in 1:nwindows
    sync()
    t0 = time_ns()
    for _ in 1:nsteps
        time_step!(model, Δt)
    end
    sync()
    push!(times, (time_ns() - t0) / 1e9 / nsteps)
    say(@sprintf("  window %d: %.4f s/step", w, times[end]))
end

# Sanity: the flow must still be finite (all ranks).
local_ok = all(isfinite, interior(model.velocities.u)) && all(isfinite, interior(model.tracers.b))
all_ok   = MPI.Allreduce(local_ok ? 1 : 0, MPI.MIN, comm) == 1

memory = use_gpu ? Float64(CUDA.total_memory() - CUDA.free_memory()) : 0.0   # whole device
memory = MPI.Allreduce(memory, MPI.MAX, comm)

tmin, tmed, tmax = minimum(times), median(times), maximum(times)
ncells = Nx * Ny * Nz
gpu    = use_gpu ? CUDA.name(CUDA.device()) : "CPU"

say(@sprintf("RESULT nh solver=%s size=%dx%dx%d gpus=%d weak=%s float=%s t_step_min=%.5f t_step_median=%.5f t_step_max=%.5f cells_per_s=%.3e mem_GiB=%.2f finite=%s gpu=\"%s\"",
             solver, Nx, Ny, Nz, nranks, weak, FT, tmin, tmed, tmax, ncells / tmin, memory / 2^30, all_ok, gpu))

if rank == 0
    stamp  = Dates.format(now(), "yyyymmdd-HHMMSS")
    output = isempty(opts["output"]) ? joinpath("results", "raw", "nh_$(solver)_$(Nx)x$(Ny)x$(Nz)_$(nranks)gpu_$(stamp).json") : opts["output"]
    mkpath(dirname(output))
    q(s) = "\"" * replace(string(s), "\"" => "\\\"") * "\""
    fields = [
        "name"                         => q("NonhydrostaticBox_$(solver)_$(Nx)x$(Ny)x$(Nz)_$(FT)"),
        "case"                         => q("nonhydrostatic_box"),
        "pressure_solver"              => q(nameof(typeof(model.pressure_solver))),
        "float_type"                   => q(FT),
        "grid_size"                    => "[$Nx, $Ny, $Nz]",
        "ranks"                        => string(nranks),
        "partition"                    => q("$(nranks)x1x1"),
        "weak_scaling"                 => string(weak),
        "dt"                           => string(Δt),
        "time_steps"                   => string(nsteps),
        "samples"                      => string(nwindows),
        "time_per_step_seconds"        => string(tmin),
        "time_per_step_median_seconds" => string(tmed),
        "time_per_step_max_seconds"    => string(tmax),
        "grid_points_per_second"       => string(ncells / tmin),
        "gpu_memory_used"              => string(memory),
        "finite"                       => string(all_ok),
        "gpu_name"                     => q(gpu),
        "julia_version"                => q(VERSION),
        "oceananigans_version"         => q(pkgversion(Oceananigans)),
        "hostname"                     => q(gethostname()),
        "timestamp"                    => q(now()),
    ]
    open(output, "w") do io
        println(io, "{")
        for (i, (k, v)) in enumerate(fields)
            println(io, "  ", q(k), ": ", v, i < length(fields) ? "," : "")
        end
        println(io, "}")
    end
    println("wrote ", output)
end

all_ok || error("non-finite values after the benchmark: the time step may be too large")
