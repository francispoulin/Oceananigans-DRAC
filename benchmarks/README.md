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

### Where the time goes: `--parts=true`

Adds a second line, `RESULT nhparts`, with the pieces of a step timed separately: the pressure
solve alone (3 per RK3 step), the pair of transposes it does on several GPUs (pack, MPI Alltoall,
unpack), one halo fill of u, v, w, and the rest of the step (`t_step - 3 t_solve`). Comparing 1
and 2 GPUs shows whether the lost time is in the distributed Poisson solver or in the rest of the model.

```bash
cd $OCEANANIGANS_DRAC_ROOT
for n in 1 2; do
    for s in FFT FourierTridiagonal; do
        bash tools/run_local.sh --wait -n $n -j nhparts_${s}_${n}gpu benchmarks/nonhydrostatic_box.jl --solver=$s --parts=true --windows=3 || break 2
    done
done
grep -ah "^RESULT nhparts" logs/nhparts_*.out
```

How to read it: if 2 GPUs scaled perfectly, `t_solve` and `t_rest` would each halve. With an
x-split, `t_solve(2) - t_solve(1)/2` is the solver's overhead, of which `t_transposes_ms` is the
communication part (`alltoall_bandwidth.jl` alone gave ~6.9 ms per solve on pelee); the remainder
is the extra FFT work (three 1-D transforms plus a permutation instead of one batched 2-D FFT).

## `alltoall_bandwidth.jl`

Times only the GPU-to-GPU `MPI_Alltoall` that each transpose of the distributed Poisson solvers
does (2 per pressure solve with an x-split, 3 solves per RK3 step), at the same sizes as
`nonhydrostatic_box.jl`. It prints the time per transpose and the bandwidth per GPU, and checks the data.

```bash
cd $OCEANANIGANS_DRAC_ROOT
bash tools/run_local.sh --wait -n 2 -j a2a_2gpu_own benchmarks/alltoall_bandwidth.jl
bash tools/run_local.sh --wait -n 2 --all-visible -j a2a_2gpu_all benchmarks/alltoall_bandwidth.jl
grep -h "^RESULT" logs/a2a_*.out
```

**Result (pelee, 2 x A100-SXM4, Oct 13 2026):** 3.45 ms per transpose (268 MB sent per GPU,
~78 GB/s), identical with each rank seeing only its own GPU (`run_local.sh` default) and with
`--all-visible`. MPI therefore copies GPU-to-GPU over NVLink in both cases. Per RK3 step that is
~21 ms, about a third of the ~65 ms that 2 GPUs lose in `nonhydrostatic_box.jl`; the rest is
elsewhere (distributed FFT kernels, packing, or the rest of the model). Use this script to check
a new machine or MPI version.
