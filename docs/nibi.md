# Using DRAC's Nibi cluster

## Overview

[Nibi](https://docs.alliancecan.ca/wiki/Nibi) is a cluster of the Digital Research Alliance
of Canada (DRAC), run by SHARCNET at the University of Waterloo. Its GPU nodes each have
**8 NVIDIA H100 80 GB GPUs** and Intel Xeon Platinum 8570 CPUs. Jobs are scheduled with
**Slurm**.

This post covers running Oceananigans on Nibi, from a first CPU job to multi-node GPU runs:
installing packages, setting up CUDA-aware MPI, Slurm scripts, checking that the setup is
correct, and scaling results. All the scripts are in the
[Oceananigans-DRAC](https://github.com/francispoulin/Oceananigans-DRAC) repository, which
is tested and kept up to date. Please comment below if something doesn't work.

**Three things that save time on Nibi:**

- **Login nodes have internet access but no GPUs.** Install packages on a login node;
  `nvidia-smi` failing there is normal.
- **Keep the Julia depot out of `$HOME`**, which has a small quota, and **set it after
  loading modules** (step 2).
- **Multi-GPU runs need three MPI settings** (steps 3 and 7), or they crash at
  `MPI.Init()`, typically as soon as NetCDF output is involved.

## 1. Get the scripts

```bash
cd $SCRATCH          # or wherever you keep software
git clone https://github.com/francispoulin/Oceananigans-DRAC.git
cd Oceananigans-DRAC
```

## 2. Environment and Julia depot

Every step uses `env/drac.sh`, which loads the modules (`StdEnv/2023`, `gcc/12.3`,
`openmpi/4.1.5`, `cuda/12.6`, `julia/1.10.10`) and sets the Julia depot: the folder where
packages and compiled code are stored. It is `$SCRATCH/julia_depot` unless you set
`JULIA_DEPOT_PATH` before sourcing the file. `module purge` leaves a few "sticky" modules
loaded and lists them; that's expected.

**Why the depot needs care on DRAC clusters.** The `julia` module runs
`append_path("JULIA_DEPOT_PATH", ":")`, so every time it is loaded it adds a colon to the
depot path. Julia reads empty entries in the depot path as "add the default depots here",
and those include `~/.julia` in your home directory. Packages can then come from, or be
written to, an unexpected place. `env/drac.sh` strips whatever the module added.

If you also use Julia interactively, set the depot in your `~/.bashrc` **after** any
`module load` lines, in the same way:

```bash
export JULIA_DEPOT_PATH="${JULIA_DEPOT_PATH%%:*}"                    # drop what the module added
export JULIA_DEPOT_PATH="${JULIA_DEPOT_PATH:-$SCRATCH/julia_depot}"  # default if unset
```

A single line such as `export JULIA_DEPOT_PATH=${JULIA_DEPOT_PATH:-$SCRATCH/julia_depot}`
is not enough: the module's `:` counts as "set".

## 3. One-time setup (login node)

```bash
bash setup/setup.sh
```

The first run downloads and precompiles everything; allow 20 to 30 minutes. It does four
things:

1. **Installs the tested package versions** from the repository's `Manifest.toml`
   (Oceananigans, CUDA, MPI, NCDatasets, JLD2).
2. **Makes MPI.jl use the system OpenMPI**, which is built for Nibi's network and for
   Slurm. DRAC modules don't set `LD_LIBRARY_PATH`, so `MPIPreferences.use_system_binary()`
   can't find `libmpi` by searching; the script passes the module's `lib` folder as
   `extra_paths`.
3. **Redirects Julia's own OpenMPI to the system library.** NetCDF and HDF5 output packages
   load `OpenMPI_jll`, Julia's own copy of OpenMPI. Without the redirect, two MPIs end up in
   one process. The redirect only works when both are the same series, so the repository
   restricts `OpenMPI_jll` to **4.1.10 or later in the 4.1 series**, matching the `openmpi/4.1.5` module;
   the newest `OpenMPI_jll` (5.x) fails with `undefined symbol: ompi_instance_count`.
4. **Precompiles.**

The key lines of the output:

```
┌ Info: MPI implementation identified
│   libmpi = "/cvmfs/soft.computecanada.ca/easybuild/software/2023/x86-64-v4/Compiler/gcc12/openmpi/4.1.5/lib/libmpi"
│   version_string = "Open MPI v4.1.5, ..."
...
== 3. OpenMPI_jll -> system OpenMPI library
   OpenMPI_jll.libmpi_path = /cvmfs/soft.computecanada.ca/easybuild/software/2023/x86-64-v4/Compiler/gcc12/openmpi/4.1.5/lib/libmpi.so
```

Both paths must be under `/cvmfs`, not in your Julia depot. The setup writes
`LocalPreferences.toml`, which holds these machine-specific settings.

## 4. Hello on a CPU node

Every job script takes your allocation with `--account`:

```bash
sbatch --account=def-YOURPI jobs/hello_cpu.sh
```

`hello_cpu_<jobid>.out` should end with:

```
[ Info: hello from Oceananigans on CPU!
grid = 8×8×8 RectilinearGrid{Float64, Periodic, Periodic, Bounded} on CPU with 3×3×3 halo
├── Periodic x ∈ [0.0, 1.0)  regularly spaced with Δx=0.125
├── Periodic y ∈ [0.0, 2.0)  regularly spaced with Δy=0.25
└── Bounded  z ∈ [-3.0, 0.0] regularly spaced with Δz=0.375
c = 8×8×8 Field{Center, Center, Center} on RectilinearGrid on CPU
...
    └── max=2.625, min=-2.625, mean=0.0
```

## 5. Hello on one GPU

```bash
sbatch --account=def-YOURPI jobs/hello_gpu.sh
```

The same grid and field, now on `CUDAGPU`:

```
[ Info: hello from Oceananigans on GPU!
grid = 8×8×8 RectilinearGrid{Float64, Periodic, Periodic, Bounded} on CUDAGPU with 3×3×3 halo
...
└── data: 14×14×14 OffsetArray(::CuArray{Float64, 3, CUDACore.DeviceMemory}, ...)
    └── max=2.625, min=-2.625, mean=0.0
```

## 6. Multi-GPU checks

`jobs/checks.sh` runs four checks on any number of GPUs, one MPI rank per GPU:

```bash
sbatch --account=def-YOURPI --nodes=1 --ntasks-per-node=2 jobs/checks.sh            # 2 GPUs
sbatch --account=def-YOURPI --nodes=1 --ntasks-per-node=8 --mem=0 jobs/checks.sh    # a full node
sbatch --account=def-YOURPI --nodes=2 --ntasks-per-node=8 --mem=0 jobs/checks.sh    # two nodes
```

Use `--mem=0` (all of a node's memory) when using all 8 GPUs of a node.

| Check | What it tests | Pass means |
| --- | --- | --- |
| `single_mpi` | Which MPI runtime is loaded, with NetCDF loaded too | Library, runtime and plugins all from `/cvmfs` |
| `cuda_aware_mpi` | GPU arrays sent around a ring of ranks | Every rank receives the right data, on its own GPU |
| `distributed_vs_serial` | ∂c/∂x on a grid split across ranks, versus one GPU | Agreement to round-off (in practice, exactly) |
| `output` | Writing and reading NetCDF and JLD2 files on every rank | Files read back exactly |

Each prints `PASS` or `FAIL`, and the job stops at the first failure. On two nodes
(16 GPUs) the output ends with:

```
== Check: single_mpi
OPAL_PREFIX = /cvmfs/soft.computecanada.ca/easybuild/software/2023/x86-64-v4/Compiler/gcc12/openmpi/4.1.5
...
PASS: one MPI, the system OpenMPI
== Check: cuda_aware_mpi
...
PASS: 16 ranks on 16 different GPUs
PASS: CUDA-aware MPI
== Check: distributed_vs_serial
max |distributed - single GPU| / max |∂c/∂x| = 0.0 on 16 ranks
PASS: distributed matches single GPU
== Check: output
...
PASS: NetCDF and JLD2 output
== All checks passed
```

Two things that may look wrong but aren't:

- **Every rank reports `CuDevice(0)`.** With `--gpus-per-task=h100:1`, each rank sees only
  its own GPU, numbered 0. The GPU UUIDs, printed at the start of the job and by
  `cuda_aware_mpi`, show the ranks are on different GPUs.
- **`single_mpi` lists three files from the Julia depot:** `libmpi_mpifh.so`,
  `libmpi_usempi_ignore_tkr.so` and `libmpi_usempif08.so`. These are OpenMPI's Fortran
  interface libraries, loaded by `OpenMPI_jll`; they pass calls on to the system `libmpi`
  and are harmless. Only the runtime (`libmpi.so`, `libopen-pal`, `libopen-rte`) and the
  `mca_*` plugins must come from `/cvmfs`.

## 7. Using MPI in your own scripts

The setup handles the system MPI and the `OpenMPI_jll` redirect. One more step goes in your
own scripts: **`OPAL_PREFIX` must be reset before MPI starts.** Even when redirected,
`OpenMPI_jll` sets the environment variable `OPAL_PREFIX` to its own folder when it loads,
and overwrites any existing value. The system OpenMPI then loads Julia's plugins at
`MPI.Init()` and crashes:

```
symbol lookup error: .../artifacts/.../lib/openmpi/mca_pmix_pmix3x.so:
undefined symbol: opal_libevent2022_evthread_use_pthreads
```

`src/drac_mpi.jl` fixes this: it points `OPAL_PREFIX` at the OpenMPI installation whose
library is actually loaded, then initializes MPI. Call it after your `using` lines and
before anything that starts MPI:

```julia
using Oceananigans, CUDA, NCDatasets
include(joinpath(ENV["OCEANANIGANS_DRAC_ROOT"], "src", "drac_mpi.jl"))
drac_mpi_init()

arch = Distributed(GPU())
```

(`OCEANANIGANS_DRAC_ROOT` is set by `env/drac.sh`.) For a job script, copy
`jobs/checks.sh` and replace the checks with your own script.

If your runs write only JLD2 output and never load NetCDF packages, `OpenMPI_jll` isn't
loaded and this step isn't needed, but it's harmless.

## 8. Scaling on Nibi

The Oceananigans benchmark suite, case `earth_ocean` on a latitude–longitude grid with 200
levels, Float64, WENO advection, CATKE, 2 tracers. Median of 5 windows of 100 steps; one
MPI rank per GPU; grid split in x. Throughput is for the whole grid.

**Strong scaling at three resolutions:**

| Resolution (cells) | GPUs | Nodes | Time per step (s) | Efficiency | Throughput (cells/s) | Memory per GPU (GiB) |
| --- | --- | --- | --- | --- | --- | --- |
| 1/4°, 1440 × 720 × 200 (0.21 billion) | 1 | 1 | 1.0114 | 100% | 2.05e8 | 45.95 |
| | 2 | 1 | 0.5228 | 96.7% | 3.97e8 | 24.05 |
| | 4 | 1 | 0.2597 | 97.4% | 7.99e8 | 12.67 |
| | 8 | 1 | 0.1441 | 87.7% | 1.44e9 | 6.98 |
| | 16 | 2 | 0.0857 | 73.8% | 2.42e9 | 4.14 |
| | 32 | 4 | 0.0693 | 45.6% | 2.99e9 | 2.71 |
| 1/8°, 2880 × 1440 × 200 (0.83 billion) | 4 | 1 | 1.0364 | 100% | 8.00e8 | 47.65 |
| | 8 | 1 | 0.5279 | 98.2% | 1.57e9 | 25.10 |
| | 16 | 2 | 0.2837 | 91.3% | 2.92e9 | 13.83 |
| | 32 | 4 | 0.1609 | 80.5% | 5.16e9 | 8.19 |
| 1/16°, 5760 × 2880 × 200 (3.3 billion) | 16 | 2 | 1.0526 | 100% | 3.15e9 | 49.97 |
| | 32 | 4 | 0.5649 | 93.2% | 5.87e9 | 27.53 |
| | 64 | 8 | pending | | | |

Efficiency is relative to the smallest GPU count at each resolution.

**Weak scaling** (about 207 million cells per GPU):

| Resolution | GPUs | Nodes | Time per step (s) | Efficiency |
| --- | --- | --- | --- | --- |
| 1/4° | 1 | 1 | 1.0114 | 100% |
| 1/8° | 4 | 1 | 1.0364 | 97.6% |
| 1/16° | 16 | 2 | 1.0526 | 96.1% |
| 1/32° | 64 | 8 | pending | |

Within one node, efficiency stays above 87%. A fixed-size problem scales well across nodes
as long as each GPU keeps enough work: at 1/4°, 32 GPUs leave only 45 columns each, while
at 1/8° and 1/16° efficiency on 16–32 GPUs stays at 80–93%. With the work per GPU held
fixed, going from 1 GPU to 16 GPUs on 2 nodes costs under 4%. Memory use is about 240 bytes
per cell (plus halo overhead), so one H100 holds up to about 300 million cells. Details:
`results/nibi_scaling.md`.

**Running the benchmark suite.** `jobs/benchmark.sh` runs the suite in an Oceananigans
checkout (its `benchmarking/` folder, set with `BENCH_DIR`). That folder has its own Julia
environment, which needs the same MPI setup as step 3 (system MPI with `extra_paths`,
`OpenMPI_jll` at 4.1 and redirected) plus the `OPAL_PREFIX` reset of step 7 before MPI
starts in `run_benchmarks.jl`. Grid size and time step are set with environment variables,
for example:

```bash
sbatch --account=def-YOURPI --job-name=b8_gpu16 --nodes=2 --ntasks-per-node=8 --mem=0 \
       --export=ALL,SIZE=2880x1440x200,DT=30 jobs/benchmark.sh
```

Reduce `DT` at higher resolution to stay stable (we used 60, 30, 15 and 7.5 s for 1/4°,
1/8°, 1/16° and 1/32°).

   ## 9. Known issues, now fixed upstream

   - **`OPAL_PREFIX` and NetCDF** (step 7): `OpenMPI_jll` overwrote `OPAL_PREFIX` even when its
     library was redirected to a system OpenMPI, which crashed multi-GPU runs writing NetCDF
     output ([Yggdrasil issue #14991](https://github.com/JuliaPackaging/Yggdrasil/issues/14991)).
     Fixed in `OpenMPI_jll` 4.1.10.  `get!` keeps an existing `OPAL_PREFIX`, which is why the env script sets it.
   - **GPU memory missing in distributed benchmark results:** the benchmark suite recorded memory
     only for single-GPU runs. Fixed in
     [Oceananigans pull request #6136](https://github.com/CliMA/Oceananigans.jl/pull/6136).
     
## 10. Tested with

| Date | Julia | Oceananigans | CUDA.jl | MPI.jl | OpenMPI_jll | Modules |
| --- | --- | --- | --- | --- | --- | --- |
| 2026-10-02 | 1.10.10 | 0.113.5 | 6.4.1 | 0.20.27 | 4.1.9 | StdEnv/2023, gcc/12.3, openmpi/4.1.5, cuda/12.6, julia/1.10.10 |

Verified from scratch: fresh depot, setup, both hello jobs, and all checks on 2 GPUs and on
16 GPUs across 2 nodes. The benchmarks used Oceananigans 0.113.5 with CUDA.jl 6.1.0.

## Other DRAC clusters

## Other DRAC clusters

**Fir** (4 H100 GPUs per node) is tested: the setup, both hello jobs and all checks pass on
2 GPUs, on a full node (4 GPUs) and across 2 nodes (8 GPUs, InfiniBand), with only the Slurm
node options changed (`--ntasks-per-node=4`, `--mem=0` for a full node). Rorqual has the same
node layout and should work the same way. Trillium is run by SciNet and may need different job
settings. Contributions from other clusters are welcome.

Fir and Rorqual have 4 GPUs per node (use `--ntasks-per-node=4`, and `--mem=0` for a full
node). Trillium is run by SciNet and may need different job settings. Testing on these is
planned; contributions are welcome as an `env/<cluster>.sh` and a section here.

## Authors

Francis Poulin, with Claude (Anthropic's AI assistant).
