# A first Oceananigans run on CPU or GPU:
#
#     julia --project=. examples/hello_oceananigans.jl CPU
#     julia --project=. examples/hello_oceananigans.jl GPU

using Oceananigans
device = isempty(ARGS) ? "CPU" : uppercase(ARGS[1])
if device == "GPU"
    using CUDA
    arch = GPU()
else
    arch = CPU()
end

grid = RectilinearGrid(arch, size = (8, 8, 8), extent = (1, 2, 3))
@info "hello from Oceananigans on $device!"
@show grid

c = CenterField(grid)
set!(c, (x, y, z) -> x + y + z)
@show c
