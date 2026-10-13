# Test: the main packages load, the GPU works, and MPI starts (1 rank). Prints the versions,
# so every test report records exactly what was tested.

using Oceananigans, CUDA, MPI, NCDatasets, JLD2
import OpenMPI_jll
include(joinpath(ENV["OCEANANIGANS_DRAC_ROOT"], "src", "drac_mpi.jl"))
drac_mpi_init()

println("julia         ", VERSION)
for (name, mod) in (("Oceananigans", Oceananigans), ("CUDA", CUDA), ("MPI", MPI),
                    ("NCDatasets", NCDatasets), ("JLD2", JLD2), ("OpenMPI_jll", OpenMPI_jll))
    println(rpad(name, 14), pkgversion(mod))
end
println("libmpi        ", MPI.identify_implementation())
ok = CUDA.functional()
if ok
    dev = CUDA.device()
    println("GPU           ", CUDA.name(dev), ", ", round(CUDA.total_memory() / 2^30, digits = 1), " GiB, CUDA runtime ",
            CUDA.runtime_version())
    a = CUDA.ones(Float64, 10^6)
    ok = sum(a) == 10^6
end
println(ok ? "PASS: packages load, GPU works, MPI starts" : "FAIL: CUDA not functional")
ok || exit(1)
