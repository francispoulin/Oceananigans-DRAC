# Sanity tests

One command per machine checks that the whole setup works: environment, packages, grids, the
hydrostatic and nonhydrostatic models on 1, 2 and 4 GPUs, multi-GPU communication, file output,
and plotting. Run them after setting up a machine, and **before adopting any library update**
(Oceananigans, CUDA, MPI, a new module).

```bash
ocean_setup
bash $OCEANANIGANS_DRAC_ROOT/tools/run_tests.sh               # 1, 2 and 4 GPUs (~15-30 min)
bash $OCEANANIGANS_DRAC_ROOT/tools/run_tests.sh --gpus "1 2"   # if only 2 GPUs are free
bash $OCEANANIGANS_DRAC_ROOT/tools/run_tests.sh --list         # what would run
```

- **pelee / rondeau:** runs the tests one after another through `tools/run_local.sh`. A test that
  needs more GPUs than are free is marked SKIP, not FAIL.
- **Alliance:** submits one Slurm job with all tests (1 node, as many GPUs as the largest test).

The summary goes to `results/tests/<machine>_<date-time>.md`: commit it, it is the record of what
was tested and with which versions. One log per test in `logs/`.

## What is tested now

| Test | GPUs | What it shows |
| --- | --- | --- |
| `check_env` | - | environment and this repository's project (warnings, not failures) |
| `load` | 1 | Oceananigans, CUDA, MPI, NCDatasets, JLD2 load; versions; GPU works; MPI starts |
| `grids` | 1 | uniform, z-stretched, latitude-longitude and immersed grids on the GPU; fields, ∂x |
| `hydrostatic` | 1, 2, 4 | HydrostaticFreeSurfaceModel (WENO, split-explicit free surface, RK3) steps; on 2 and 4 GPUs matches the 1-GPU run (relative difference < 1e-8) |
| `single_mpi` | 1, 2, 4 | one MPI only, the system OpenMPI (with NetCDF loaded) |
| `cuda_aware_mpi` | 1, 2, 4 | one GPU per rank; GPU arrays pass through MPI |
| `distributed_vs_serial` | 1, 2, 4 | halo exchange: distributed ∂x equals single GPU |
| `output` | 1, 2, 4 | NetCDF and JLD2 written and read back under MPI |
| `nh_fft` | 1, 2, 4 | NonhydrostaticModel, FFT pressure solver (distributed on 2, 4) steps, finite |
| `nh_ft` | 1 | NonhydrostaticModel, stretched z, Fourier-tridiagonal solver |
| `viz` | CPU | viz environment: NetCDF read, PNG and MP4 with CairoMakie |

## To add (the list grows as needed)

- Nonhydrostatic distributed vs single GPU (as `hydrostatic`), and Fourier-tridiagonal on 2, 4 GPUs.
- Checkpoint and restart (pickup) gives the same answer as an uninterrupted run.
- Performance: the hydrostatic and nonhydrostatic benchmarks within a few % of stored numbers.
- Simulation repos (once merged): jet bitwise reproduction of `v1.0-multigpu` (128³, 1 and 4 GPUs);
  vortex `BG_4km_U02_balanced_1e-2` norms over 20 days and the balance test; movie and growth
  scripts on a small stored run.
- NumericalEarth / sea ice: a short coupled run when that component is in use.
- Across nodes (Alliance): the multi-GPU tests on 2 nodes.
