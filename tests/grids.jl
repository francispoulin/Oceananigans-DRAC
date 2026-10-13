# Test: the grid types we use can be built on the GPU, fields set and derivatives computed.
#   uniform RectilinearGrid, z-stretched RectilinearGrid (as the Beaufort Gyre), LatitudeLongitudeGrid
#   (as the earth_ocean benchmark), ImmersedBoundaryGrid with a bottom (as the seamount).

using Oceananigans, CUDA

function try_grid(name, grid)
    try
        c = CenterField(grid)
        set!(c, (x, y, z) -> sin(x / 1e3) + z / 1e3)
        d = Field(∂x(c))
        compute!(d)
        ok = all(isfinite, interior(d))
        println(rpad(name, 32), ok ? "ok" : "non-finite values", "  ", size(grid))
        return ok
    catch err
        println(rpad(name, 32), "ERROR: ", sprint(showerror, err)[1:min(end, 300)])
        return false
    end
end

arch = GPU()
results = Bool[]

push!(results, try_grid("Rectilinear, uniform",
    RectilinearGrid(arch; size = (32, 32, 16), x = (0, 1e5), y = (0, 1e5), z = (-1000, 0),
                    topology = (Periodic, Bounded, Bounded))))

stretched_z(k) = -1000 * (1 - tanh(1.5 * (k - 1) / 16) / tanh(1.5))     # BG-style stretching
push!(results, try_grid("Rectilinear, stretched z",
    RectilinearGrid(arch; size = (32, 32, 16), x = (-5e4, 5e4), y = (-5e4, 5e4), z = stretched_z,
                    topology = (Bounded, Bounded, Bounded))))

push!(results, try_grid("LatitudeLongitude",
    LatitudeLongitudeGrid(arch; size = (36, 18, 8), longitude = (0, 360), latitude = (-75, 75),
                          z = (-4000, 0))))

base = RectilinearGrid(arch; size = (32, 32, 16), x = (0, 1e5), y = (0, 1e5), z = (-1000, 0),
                       topology = (Periodic, Periodic, Bounded))
bump(x, y) = -1000 + 300 * exp(-((x - 5e4)^2 + (y - 5e4)^2) / 2e4^2)
push!(results, try_grid("Immersed (GridFittedBottom)", ImmersedBoundaryGrid(base, GridFittedBottom(bump))))

ok = all(results)
println(ok ? "PASS: grids ($(length(results)) types)" : "FAIL: grids ($(count(!, results)) of $(length(results)) failed)")
ok || exit(1)
