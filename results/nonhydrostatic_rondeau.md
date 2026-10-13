# Nonhydrostatic scaling on rondeau (A100)

## Setup

- **Benchmark:** `benchmarks/nonhydrostatic_box.jl` (the `nonhydrostatic` case of the newer
  Oceananigans benchmark suite, ported to 0.113.5 and to several GPUs): `NonhydrostaticModel`,
  1 km × 1 km × 500 m box, Periodic × Periodic × Bounded, WENO(5), f-plane, buoyancy tracer,
  Float64, RK3, fixed Δt.
- **Size:** 512 × 512 × 256 (67.1 million cells) for strong scaling; the same per GPU for weak scaling.
- **Pressure solvers:** FFT (uniform grid), Fourier-tridiagonal (z stretched, as our stretched-grid
  runs would use), conjugate gradient (seamount; immersed boundary; 1 GPU only).
- **Distribution:** one MPI rank per GPU, grid split in x; the model picks
  `DistributedFFTBasedPoissonSolver` / `DistributedFourierTridiagonalPoissonSolver`.
- **Timing:** 10 warm-up steps, then 5 windows of 100 steps; fastest window shown (windows agree
  within 5% unless noted).
- **Hardware:** rondeau, 4 × NVIDIA A100-SXM4-40GB with NVLink; CUDA-aware OpenMPI 4.1.7;
  launched with `tools/run_local.sh` (one GPU per rank, `JULIA_CUDA_MEMORY_POOL=none`).
- **Software:** Julia 1.10.8, Oceananigans 0.113.5. **Date:** 2026-10-13.
- **Memory:** GPU memory per rank. In these runs it was read for the whole device, which is correct
  only when nobody else uses the GPU (see the weak-scaling note). The benchmark now reads the
  memory of its own process and flags a shared GPU (`shared_gpu=true`).

## Strong scaling (fixed size 512 × 512 × 256)

| Solver | GPUs | Time per step (s) | Speedup | Efficiency | Throughput (cells/s) | Memory per GPU (GiB) | Total memory (GiB) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| FFT | 1 | 0.2536 | 1.00 | 100% | 2.65e8 | 9.95 | 9.95 |
| FFT | 2 | 0.1916 | 1.32 | 66% | 3.50e8 | 7.67 | 15.3 |
| Fourier-tridiagonal | 1 | 0.2200 | 1.00 | 100% | 3.05e8 | 10.95 | 10.95 |
| Fourier-tridiagonal | 2 | 0.1713 | 1.28 | 64% | 3.92e8 | 8.17 | 16.3 |
| Fourier-tridiagonal | 4 | 0.1044 | 2.11 | 53% | 6.43e8 | 4.59 | 18.4 |
| Conjugate gradient | 1 | 1.3067 | – | – | 5.14e7 | 12.62 | 12.62 |

Spread between windows: 1 GPU < 0.1%; 2 GPUs 5%; 4 GPUs 12%; conjugate gradient 6% (the number of
iterations varies from step to step).

## Weak scaling (512 × 512 × 256 per GPU, FFT)

| GPUs | Total size | Time per step (s) | Efficiency | Memory per GPU (GiB) |
| --- | --- | --- | --- | --- |
| 1 | 512 × 512 × 256 | 0.2535 | 100% | 9.95 |
| 2 | 1024 × 512 × 256 | 0.3790 | (67%) | (31.5, see note) |
| 4 | 2048 × 512 × 256 | not run (GPU 0 in use by another user) | | |

**Note:** during the 2-GPU run another user's job (17.6 GB) was on GPU 0. Its memory is included in
the 31.5 GiB (about 14.4 GiB is ours), and it may have slowed the run. **Re-run 2 and 4 GPUs on idle
GPUs** before using these numbers.

## Reading the results

- **The pressure solve's communication sets the scaling.** Hydrostatic Oceananigans scales at
  97% from 1 to 2 GPUs (Nibi, `nibi_scaling.md`); nonhydrostatic at 64–66%, even within one node over
  NVLink. If everything but the pressure solve split perfectly, 2 GPUs would take 0.127 s (FFT); the
  extra ~0.065 s per step (~20 ms per pressure solve, 3 per step) is the transposes of the distributed
  FFT, which reshuffle the whole pressure field between GPUs.
- **The cost is mostly paid once, when going from 1 GPU to several.** Fourier-tridiagonal: 64% at
  2 GPUs, 53% at 4, but 2 → 4 GPUs alone is 82% efficient. More GPUs within a node still help.
- **Fourier-tridiagonal is 13% faster than FFT on one GPU** (a tridiagonal solve per column is cheaper
  than an FFT in z) and scales the same way; it needs ~1 GiB more.
- **Conjugate gradient costs ~5×** the FFT solver (each iteration applies an FFT-based
  preconditioner): topography in a nonhydrostatic run is expensive, and it is single-GPU here.
- **Memory:** ~150–200 bytes per cell on one GPU (FFT 159, Fourier-tridiagonal 175, conjugate
  gradient 202, including ~0.5 GiB of CUDA context): one A100-40GB holds roughly 200–250 million cells.
  Distributing adds buffers for the transposes: **+49% total memory on 2 GPUs, +68% on 4**
  (Fourier-tridiagonal). So more GPUs do allow larger problems, but not in proportion
  (2 GPUs ≈ 1.6–1.8× the cells of one).

## Where the time goes (first look)

`benchmarks/alltoall_bandwidth.jl` on pelee (same hardware, Oct 13): the MPI Alltoall of one
transpose at 512 x 512 x 256 on 2 GPUs takes 3.45 ms (~78 GB/s per GPU over NVLink), whether each
rank sees one GPU or all. For FFT on 2 GPUs the step is 65 ms slower than ideal (0.192 s vs 0.127 s),
and the 6 transposes per step account for only ~21 ms of that. **The GPU-to-GPU communication is not
the main cost; ~44 ms per step is elsewhere** (distributed FFT as separate 1-D transforms, packing
and synchronization, or the rest of the model). Next: time the Poisson solve alone on 1 vs 2 GPUs,
then profile one step (Nsight Systems) if needed.

## To do

- [ ] Poisson solve alone, 1 vs 2 GPUs (solver vs rest of the model).
- [ ] FFT on 4 GPUs (strong scaling).
- [ ] Weak scaling on 2 and 4 idle GPUs (memory per GPU at fixed local size answers how big a problem fits).
- [ ] Nibi (H100): 1, 2, 4, 8 GPUs, then 2 nodes (expected worse across nodes), if useful for the RAC proposal.
- [ ] Same comparison with the real configurations once BalancedFlows has a nonhydrostatic option.
