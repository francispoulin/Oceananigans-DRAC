# Oceananigans-DRAC

Scripts and instructions for running [Oceananigans.jl](https://github.com/CliMA/Oceananigans.jl)
on the GPU clusters of the Digital Research Alliance of Canada (DRAC), including multi-GPU
runs with CUDA-aware MPI.

**Status:** verified on Nibi, Fir and Rorqual (October 2026). Trillium is not yet tested.

## Authors

- **Francis Poulin** (University of Waterloo): direction, testing and verification on
  DRAC clusters, and maintenance.
- **Claude** (Anthropic's AI assistant): co-developed the scripts, checks and
  documentation with Francis.

All results in this repository, including the scaling benchmarks, were run on Nibi and
verified by Francis.

## Quick start

```bash
git clone https://github.com/francispoulin/Oceananigans-DRAC.git        # works for everyone
# or, if you have a GitHub SSH key set up:
# git clone git@github.com:francispoulin/Oceananigans-DRAC.git
cd Oceananigans-DRAC

export SBATCH_ACCOUNT=def-yourpi     # your group's allocation
export SALLOC_ACCOUNT=$SBATCH_ACCOUNT

bash setup/setup.sh                                                     # login node, once
sbatch jobs/hello_cpu.sh
sbatch jobs/hello_gpu.sh
sbatch --nodes=1 --ntasks-per-node=2 jobs/checks.sh
```

**Start with [docs/overview.md](docs/overview.md)** (how the pieces fit together).
The full Alliance walkthrough is [docs/drac.md](docs/drac.md), which is also posted in the
Oceananigans Discussions (https://github.com/CliMA/Oceananigans.jl/discussions/6150).

## What's here

| Path | Contents |
| --- | --- |
| `env/ocean_setup.sh` | Sourced by setup and every job; picks the machine's env file (`env/README.md`) |
| `env/drac.sh` | Modules and environment for the Alliance clusters |
| `env/fluidsgpu.sh` | The same for the Waterloo fluids group's servers (pelee, rondeau; no Slurm) |
| `setup/setup.sh` | One-time setup: packages, system MPI, OpenMPI_jll redirect |
| `setup/configure_mpi.sh` | The MPI part of the setup, for your own project folder |
| `setup/setup_viz.sh` | One-time setup of `viz/`, the plotting environment (CairoMakie, NCDatasets) |
| `viz/` | Plotting environment, kept separate so simulations never load Makie |
| `tools/check_env.sh` | Checks the environment and a project, and says what looks wrong |
| `tools/run_local.sh` | Background runs on free GPUs, with a log, on machines without Slurm |
| `src/drac_mpi.jl` | `drac_mpi_init()`: starts MPI safely when NetCDF is loaded |
| `examples/` | A first Oceananigans script, on CPU or GPU |
| `jobs/` | Slurm scripts: hello on CPU and GPU, multi-GPU checks, benchmarks, plotting (`viz.sh`) |
| `checks/` | Single MPI, CUDA-aware MPI, distributed vs single-GPU, NetCDF/JLD2 output |
| `benchmarks/` | Nonhydrostatic box benchmark, 1 to many GPUs (`benchmarks/README.md`) |
| `tests/` | Sanity tests of the whole setup; run all with `tools/run_tests.sh` (`tests/README.md`) |
| `results/` | Scaling results |
| `docs/` | Cluster guides |

`LocalPreferences.toml` is written by `setup/setup.sh` on each machine and is not under
version control. `Project.toml` and `Manifest.toml` record the tested package versions.

## Everyday use

Add one alias to `~/.bashrc` on each machine (only the path differs):

```bash
alias ocean_setup='source /path/to/Oceananigans-DRAC/env/ocean_setup.sh'
alias check_env='bash $OCEANANIGANS_DRAC_ROOT/tools/check_env.sh'
```

Then, in any project folder:

```bash
ocean_setup                     # modules, depot, MPI, for this machine
check_env                       # anything wrong with the environment or this project?
bash $OCEANANIGANS_DRAC_ROOT/tools/run_tests.sh                       # full sanity tests (after setup or updates)
julia --project=$OCEANANIGANS_DRAC_ROOT/viz scripts/make_movies.jl      # plots, with viz/
```

Plotting jobs on the Alliance: `sbatch $OCEANANIGANS_DRAC_ROOT/jobs/viz.sh scripts/make_movies.jl`.
On pelee and rondeau, see [docs/fluidsgpu.md](docs/fluidsgpu.md).

## Contributing

Corrections and other clusters are welcome: open an issue or a pull request. A new machine
needs an `env/<machine>.sh` providing the variables in [env/README.md](env/README.md), and a case
in `env/ocean_setup.sh`.

## License

MIT; see [LICENSE](LICENSE).
