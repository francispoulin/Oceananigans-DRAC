# Benchmarks

## `nonhydrostatic_box.jl`

Time per step of a `NonhydrostaticModel` on 1, 2, 4, ... GPUs (one MPI rank per GPU, grid split in
x), to see how the nonhydrostatic pressure solve scales. Configuration copied from the
`nonhydrostatic` case of the newer Oceananigans benchmark suite (main branch), adapted to the
Oceananigans version in this repository (0.113.5) and to multiple GPUs:
1 km x 1 km x 500 m box, periodic in x and y, WENO(5), f-plane, stratified buoyancy tracer.

| `--solver` | Grid | 1 GPU | several GPUs |
| --- | --- | --- | --- |
| `FFT` | uniform | `FFTBasedPoissonSolver` | `DistributedFFTBasedPoissonSolver` (transposes) |
| `FourierTridiagonal` | stretched in z | `FourierTridiagonalPoissonSolver` | `DistributedFourierTridiagonalPoissonSolver` |
| `ConjugateGradient` | seamount (immersed) | FFT-preconditioned CG | not supported here |

Constraints of the distributed solvers: no split in z; Ny divisible by the number of GPUs.

**pelee / rondeau** (strong scaling 1, 2, 4 GPUs; each run waits for the previous one):

```bash
cd $OCEANANIGANS_DRAC_ROOT
for n in 1 2 4; do
    bash tools/run_local.sh --wait -n $n -j nh_fft_${n}gpu benchmarks/nonhydrostatic_box.jl --solver=FFT || break
done
grep -h "^RESULT" logs/nh_fft_*gpu_*.out
```

**Alliance:** `sbatch --ntasks-per-node=2 jobs/benchmark_nh.sh` (options in that file).

Every run prints one `RESULT ...` line (time per step: fastest, median, slowest window; cells/s;
GPU memory) and writes a JSON file to `results/raw/`. The default size, 512 x 512 x 256
(67M cells), fits on one A100-40GB; for weak scaling use `--weak=true` (size per GPU).

Good comparisons: FFT vs FourierTridiagonal at the same size (the stretched-z solver is what a
Beaufort Gyre or Gulf Stream nonhydrostatic run would use), and the same box with the hydrostatic
model (`earth_ocean` case of the Oceananigans suite) for the cost of going nonhydrostatic.

## `alltoall_bandwidth.jl`

Times only the GPU-to-GPU `MPI_Alltoall` that each transpose of the distributed Poisson solvers
does (2 per pressure solve with an x-split, 3 solves per RK3 step), at the same sizes as
`nonhydrostatic_box.jl`. It prints the time per transpose and the bandwidth per GPU, and checks the data.

On rondeau, every pair of A100s is linked by 4 NVLinks (`nvidia-smi topo -m`: `NV4`, about 100 GB/s
each way), but the nonhydrostatic results imply only ~25 GB/s, which is PCIe-like. The suspected
cause is that `run_local.sh` shows each rank only its own GPU, which can stop MPI from copying
GPU-to-GPU (CUDA IPC). Compare the default with `--all-visible` (every rank sees all its GPUs
and picks its own by local rank):

```bash
cd $OCEANANIGANS_DRAC_ROOT
for n in 2 4; do
    bash tools/run_local.sh --wait -n $n -j a2a_${n}gpu_own benchmarks/alltoall_bandwidth.jl || break
    bash tools/run_local.sh --wait -n $n --all-visible -j a2a_${n}gpu_all benchmarks/alltoall_bandwidth.jl || break
done
grep -h "^RESULT" logs/a2a_*.out
```

If `--all-visible` is much faster, re-run `nonhydrostatic_box.jl` with it (Oceananigans'
`Distributed(GPU())` assigns GPUs by local rank; the benchmark's `shared_gpu` flag would catch
two ranks on one GPU).
