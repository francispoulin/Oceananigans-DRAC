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

- **The distributed pressure solve sets the scaling.** Hydrostatic Oceananigans scales at
  97% from 1 to 2 GPUs (Nibi, `nibi_scaling.md`); nonhydrostatic at 64–66%, even within one node over
  NVLink. About 80% of the time lost per step is in the pressure solve; the GPU-to-GPU data movement
  is only part of it (see "Where the time goes" below).
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

## Where the time goes

All on pelee (same hardware as rondeau: 2 × A100-SXM4-40GB, NVLink), Oct 13, 512 × 512 × 256.
Posted as an Oceananigans Discussion (Oct 13, 2026) with the roadmap below.

### The MPI Alltoall alone (`benchmarks/alltoall_bandwidth.jl`)

One transpose on 2 GPUs: 3.45 ms (268 MB sent per GPU, ~78 GB/s over NVLink), the same whether each
rank sees one GPU or all (`run_local.sh --all-visible`). So MPI copies GPU-to-GPU over NVLink, and
the 6 transposes per step (2 per solve) account for ~21 ms of the ~65 ms lost per step (FFT).

### Pieces of a step (`--parts=true`)

Time in ms; one RK3 step does 3 pressure solves; "rest" = step − 3 solves.

| | FFT, 1 GPU | FFT, 2 GPUs | FT, 1 GPU | FT, 2 GPUs |
| --- | --- | --- | --- | --- |
| step | 253.6 | 193.3 (66%) | 220.3 | 171.9 (64%) |
| one pressure solve | 32.1 | **33.7** | 18.8 | **26.4** |
| transposes in one solve (pack, Alltoall, unpack) | – | 10.6 | – | 10.6 |
| rest of the step | 157.3 | 92.2 (85%) | 164.0 | 92.7 (88%) |
| one halo fill of u, v, w | 0.24 | 0.79 | 0.24 | 0.79 |

(FT = Fourier-tridiagonal.) **On 2 GPUs the distributed solve is no faster than on 1 GPU (FFT), or
slower (FT, +40%).** About 80% of the time lost per step is in the solve (FFT 53 of 67 ms; FT 51 of
62 ms); the rest of the model scales at 85–88%. A repeat of the FT runs (single timing window)
gave the same solve times (18.8 and 26.5 ms).

### Inside the Fourier-tridiagonal solve (Nsight Systems, `--profile=true`)

2 profiled steps = 6 solves; kernel times per solve in ms (2 GPUs: rank 0).

| | 1 GPU | 2 GPUs | ideal (½ of 1 GPU) |
| --- | --- | --- | --- |
| cuFFT kernels (x and y) | 6.3 | 3.1 | 3.2 |
| batched tridiagonal solve | 5.2 | 2.6 | 2.6 |
| source term | 2.0 | 1.0 | 1.0 |
| copies, scaling (cuBLAS `scal`), real part, reductions | 5.2 | 2.9 | 2.6 |
| `permutedims` (4 per solve) | – | **6.1** | – |
| pack/unpack for the 2 transposes | – | **3.6** | – |
| MPI GPU-to-GPU copies (NVLink, CUDA IPC) | – | **7.0** | – |
| device-to-device copy | – | 0.8 | – |
| **total** | **18.7** | **≈ 27 (measured 26.5)** | **9.4** |

- Everything the solve does on one GPU scales perfectly to two; the excess is work only the
  distributed path does.
- The largest piece is `permutedims`: on GPUs the y transform runs on a copy reordered so y is
  contiguous, and reordered back (forward and backward), because cuFFT handles strided transforms
  along dimension 2 poorly (comment in `plan_distributed_transforms`). On one GPU, x and y are
  transformed together in one batched 2-D FFT, so this does not arise.
- The GPUs are busy throughout (no large idle gaps): the cost is extra memory traffic, not waiting.
  The host waits in `cuStreamSynchronize`, and Open MPI polls CUDA events during the copies.
- Rest of the step: the tendency kernels are split into interior and boundary parts (to overlap halo
  communication), costing ~8% extra, plus many small kernels for halo buffers.

### Roadmap (smallest changes first; savings per FT solve)

| Step | Difficulty | Saving | Expected FT efficiency, 1 → 2 GPUs |
| --- | --- | --- | --- |
| A. Store the y-local data y-first throughout the solve, so the 4 permutes disappear | medium | ~6 ms | ~72% |
| B. Remove the duplicate normalization and the extra device-to-device copy | easy | ~1.5 ms | ~74% (with A) |
| C. `NCCLDistributed` for the transposes (exists in `OceananigansNCCLExt`) | easy to try | small | |
| D. Fuse the reordering into neighbouring kernels | medium | 1–2 ms | |
| E. Overlap the Alltoall with FFT/tridiagonal work (pipelined transposes) | hard | up to ~5 ms | needed beyond ~78% |

Without overlap (E), the 7 ms of data movement per solve remains: ~78% is the ceiling for the solve
changes alone.

## To do

- [x] Poisson solve alone, 1 vs 2 GPUs (`--parts`), and a profile of the FT solve (`--profile`).
- [ ] Follow the Oceananigans Discussion; if welcome, try A and B (separate environment, compare with
      the tables above).
- [ ] Profile the FFT solver the same way.
- [ ] FFT on 4 GPUs (strong scaling).
- [ ] Weak scaling on 2 and 4 idle GPUs (memory per GPU at fixed local size answers how big a problem fits).
- [ ] Nibi (H100): 1, 2, 4, 8 GPUs, then 2 nodes (expected worse across nodes), if useful for the RAC proposal.
- [ ] Same comparison with the real configurations once BalancedFlows has a nonhydrostatic option.
