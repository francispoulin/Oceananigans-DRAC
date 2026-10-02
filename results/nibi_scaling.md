# Oceananigans scaling on Nibi

## Setup

- **Benchmark:** Oceananigans benchmark suite, case `earth_ocean`, latitude–longitude grid
  1440 × 720 × 200 (207,360,000 cells), Float64, WENO vector-invariant momentum advection,
  WENO7 tracer advection, CATKE, 2 tracers, split Runge–Kutta 3, Δt = 60 s.
- **Timing:** 5 warm-up steps, then 5 windows of 100 steps; the time per step is the
  **fastest** window (as reported by the suite). "Spread" is how much slower the slowest
  window was.
- **Hardware:** Nibi GPU nodes, 8 × NVIDIA H100 80 GB HBM3 per node, Intel Xeon Platinum 8570.
- **Software:** Julia 1.10.10, Oceananigans 0.113.5, CUDA.jl 6.1.0, OpenMPI 4.1.5 (system).
- **Distribution:** one MPI rank per GPU, grid split in x only (`--partition=Nx1x1`).
- **Date:** 2026-10-02.

## Strong scaling (fixed size 1440 × 720 × 200)

| GPUs | Nodes | Cells per GPU | Time per step (s) | Speedup | Efficiency | Throughput (cells/s) | Spread |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 1 | 207,360,000 | 1.0110 | 1.00 | 100% | 2.05e8 | 0.1% |
| 2 | 1 | 103,680,000 | 0.5228 | 1.93 | 96.7% | 3.97e8 | 1.7% |
| 4 | 1 | 51,840,000 | 0.2594 | 3.90 | 97.4% | 7.99e8 | 1.2% |
| 8 | 1 | 25,920,000 | 0.1438 | 7.03 | 87.9% | 1.44e9 | 4.4% |
| 16 | 2 | 12,960,000 | 0.0851 | 11.87 | 74.2% | 2.44e9 | 23% |
| 32 | 4 | 6,480,000 | 0.0689 | 14.67 | 45.9% | 3.01e9 | 60% |

Throughput is for the whole grid (total cells / time per step), not per GPU.

**Reading the results.** Within one node (up to 8 GPUs) efficiency stays at 88–97%.
Across nodes it falls, because communication between nodes is slower and each GPU's
share becomes too small to keep an H100 busy (45 columns at 32 GPUs). The large spread at
16 and 32 GPUs means typical times there are noticeably slower than the fastest window.

## To do

- [ ] GPU memory per rank (now recorded for distributed runs after the `src/utils.jl` fix)
- [ ] Larger problem that needs several GPUs: 2880 × 1440 × 200 (4 → 32 GPUs) and
      5760 × 2880 × 200 (16 → 64 GPUs)
- [ ] Weak scaling (constant cells per GPU)
- [ ] Median times alongside the fastest window
