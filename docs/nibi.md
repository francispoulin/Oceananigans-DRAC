# Using DRAC's Nibi cluster

> **Draft, not yet verified from scratch.** Items marked TODO are filled in during the
> verification run. The scripts referred to below are in
> [Oceananigans-DRAC](https://github.com/francispoulin/Oceananigans-DRAC) (TODO: final URL).

## Overview

[Nibi](https://docs.alliancecan.ca/wiki/Nibi) (TODO: check link) is a cluster of the
Digital Research Alliance of Canada (DRAC), run by SHARCNET at the University of Waterloo.
Its GPU nodes each have **8 NVIDIA H100 80 GB GPUs** and Intel Xeon Platinum 8570 CPUs.
Jobs are scheduled with **Slurm**.

This post covers everything needed to run Oceananigans on Nibi, from a first CPU job to
multi-node GPU runs: installing packages, setting up CUDA-aware MPI, writing Slurm scripts,
and checking that the setup is correct. Please comment below if something doesn't work;
the post and the scripts will be kept up to date.

**Three things that save time on Nibi:**

- **Login nodes have internet access but no GPUs.** Install packages on a login node;
  `nvidia-smi` failing there is normal.
- **Keep the Julia depot out of `$HOME`**, which has a small quota.
- **NetCDF output needs one extra step** in multi-GPU runs (step 6). Without it, runs crash
  at `MPI.Init()` with an `undefined symbol` error.

## 1. Get the scripts

```bash
cd $SCRATCH        # or wherever you keep software
git clone https://github.com/francispoulin/Oceananigans-DRAC.git
cd Oceananigans-DRAC
```

The environment for every step is in `env/nibi.sh`: the modules (`StdEnv/2023`, `gcc/12.3`,
`openmpi/4.1.5`, `cuda/12.6`, `julia/1.10.10`) and the depot location (`$SCRATCH/julia_depot`
unless you set `JULIA_DEPOT_PATH` first). `module purge` leaves a few "sticky" modules
loaded and says so; that's expected.

TODO: Nibi's scratch purge policy, and whether a project directory is a better depot location.

## 2. One-time setup (login node)

```bash
bash setup/setup.sh
```

This installs Oceananigans, CUDA, MPI, NCDatasets and JLD2, then sets up MPI (step 6
explains why each part is needed). The last lines should show
`OpenMPI_jll.libmpi_path = /cvmfs/...`: a path under `/cvmfs`, not in your Julia depot.

TODO: expected output, and time taken.

## 3. Hello on a CPU node

Every job script takes your allocation with `--account`:

```bash
sbatch --account=def-YOURPI jobs/hello_cpu.sh
```

`hello_cpu_<jobid>.out` should end with a small grid and field:

```
TODO: paste from verification run
```

## 4. Hello on one GPU

```bash
sbatch --account=def-YOURPI jobs/hello_gpu.sh
```

The grid and field should now be on `CUDAGPU`:

```
TODO: paste from verification run
```

## 5. Multi-GPU checks

`jobs/checks.sh` runs four checks on any number of GPUs, one MPI rank per GPU:

```bash
sbatch --account=def-YOURPI --nodes=1 --ntasks-per-node=2 jobs/checks.sh            # 2 GPUs
sbatch --account=def-YOURPI --nodes=1 --ntasks-per-node=8 --mem=0 jobs/checks.sh    # a full node
sbatch --account=def-YOURPI --nodes=2 --ntasks-per-node=8 --mem=0 jobs/checks.sh    # two nodes
```

| Check | What it tests | Pass means |
| --- | --- | --- |
| `single_mpi` | Which MPI libraries are loaded, with NetCDF loaded too | All from `/cvmfs`: one MPI |
| `cuda_aware_mpi` | GPU arrays sent around a ring of ranks | Every rank receives the right data, on its own GPU |
| `distributed_vs_serial` | ∂c/∂x on a grid split across ranks, versus one GPU | Agreement to round-off |
| `output` | Writing and reading NetCDF and JLD2 files on every rank | Files read back exactly |

Each prints `PASS` or `FAIL`, and the job stops at the first failure.

**Every rank reports `CuDevice(0)`, and that's correct.** With `--gpus-per-task=h100:1`,
each rank sees only its own GPU, and it is numbered 0. The GPU UUIDs, printed at the start
of the job, show that the ranks really are on different GPUs.

Use `--mem=0` (all of a node's memory) when using all 8 GPUs of a node.

```
TODO: paste from verification run
```

## 6. Using MPI in your own scripts

Three steps make multi-GPU runs work on Nibi. `setup/setup.sh` does the first two; the
third goes in your own scripts.

1. **MPI.jl uses the system OpenMPI** (`MPIPreferences.use_system_binary()`), which is
   built for Nibi's network and for Slurm.
2. **Julia's own OpenMPI is redirected to the system library.** NetCDF and HDF5 output
   packages load `OpenMPI_jll`, Julia's own copy of OpenMPI. Without this step, two MPIs
   end up in one process.
3. **`OPAL_PREFIX` is reset before MPI starts.** Even when redirected, `OpenMPI_jll` sets
   `OPAL_PREFIX` to its own folder, and the system OpenMPI then loads Julia's plugins and
   crashes:
   ```
   symbol lookup error: .../artifacts/.../lib/openmpi/mca_pmix_pmix3x.so:
   undefined symbol: opal_libevent2022_evthread_use_pthreads
   ```
   `src/drac_mpi.jl` fixes this. Call it after your `using` lines and before anything that
   starts MPI:
   ```julia
   using Oceananigans, CUDA, NCDatasets
   include(joinpath(ENV["OCEANANIGANS_DRAC_ROOT"], "src", "drac_mpi.jl"))
   drac_mpi_init()

   arch = Distributed(GPU())
   ```
   TODO: link to the upstream issue.

If your runs only write JLD2 output and never load NetCDF packages, steps 2 and 3 are not
needed, but they are harmless.

For a job script, copy `jobs/checks.sh` and replace the checks with your own script.

## 7. Scaling on Nibi

Strong scaling of the Oceananigans benchmark suite (`earth_ocean`, lat-lon 1440 × 720 × 200,
Float64, WENO, CATKE), fastest of 5 windows of 100 steps:

| GPUs | Nodes | Time per step (s) | Speedup | Efficiency |
| --- | --- | --- | --- | --- |
| 1 | 1 | 1.0110 | 1.00 | 100% |
| 2 | 1 | 0.5228 | 1.93 | 97% |
| 4 | 1 | 0.2594 | 3.90 | 97% |
| 8 | 1 | 0.1438 | 7.03 | 88% |
| 16 | 2 | 0.0851 | 11.87 | 74% |
| 32 | 4 | 0.0689 | 14.67 | 46% |

Efficiency stays high within a node and falls across nodes, where communication is slower
and each GPU's share of this grid becomes small. Larger grids will scale further. Details:
`results/nibi_scaling.md`.

To run the benchmark suite yourself, see `jobs/benchmark.sh`; the benchmarking folder of
your Oceananigans checkout needs the same MPI setup as step 6 (TODO: exact steps).

## 8. Known issues

- **`OPAL_PREFIX` and NetCDF** (step 6). TODO: upstream issue link.
- **GPU memory missing in distributed benchmark results:** the benchmark suite only
  recorded memory for single-GPU runs. TODO: pull request link.

## 9. Tested with

| Date | Julia | Oceananigans | CUDA.jl | MPI.jl | Modules |
| --- | --- | --- | --- | --- | --- |
| TODO | 1.10.10 | TODO | TODO | TODO | StdEnv/2023, gcc/12.3, openmpi/4.1.5, cuda/12.6 |

## Other DRAC clusters

Fir and Rorqual have 4 GPUs per node (use `--ntasks-per-node=4`). Trillium is run by SciNet
and may need different job settings. TODO: test and add an `env/<cluster>.sh` for each.
