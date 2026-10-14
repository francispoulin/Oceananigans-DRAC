# Oceananigans-DRAC

Scripts and instructions for running [Oceananigans.jl](https://github.com/CliMA/Oceananigans.jl)
on GPUs, including multi-GPU runs with CUDA-aware MPI: on the clusters of the Digital Research
Alliance of Canada (DRAC), and on the Waterloo fluids group's own servers.

## Machines

| Machine | GPUs per node | Scheduler | Environment file | Guide | Platform tests |
| --- | --- | --- | --- | --- | --- |
| Nibi (Alliance) | 8 × H100 | Slurm | `env/drac.sh` | [docs/drac.md](docs/drac.md) | Oct 2026, all passed |
| Fir (Alliance) | 4 × H100 | Slurm | `env/drac.sh` | [docs/drac.md](docs/drac.md) | Oct 2026, all passed |
| Rorqual (Alliance) | 4 × H100 | Slurm | `env/drac.sh` | [docs/drac.md](docs/drac.md) | Oct 2026, all passed |
| Trillium GPU (Alliance, SciNet) | 4 × H100 | Slurm, 1 GPU or whole nodes | `env/drac.sh` | [docs/drac.md](docs/drac.md), section 11 | Oct 2026, all passed |
| pelee, rondeau (Waterloo fluids group) | 4 × A100 | none (`tools/run_local.sh`) | `env/fluidsgpu.sh` | [docs/fluidsgpu.md](docs/fluidsgpu.md) | rondeau Oct 2026, all passed (pelee: same setup, shared drive) |

The same command, `source env/ocean_setup.sh`, sets up every machine: it detects which one it is
on. Test summaries, with the package versions tested, are in [results/tests/](results/tests/).
pelee and rondeau are private (group members only); `env/fluidsgpu.sh` is also a worked example
for any machine without Slurm.

## Authors

- **Francis Poulin** (University of Waterloo): direction, testing and verification on
  every machine, and maintenance.
- **Claude** (Anthropic's AI assistant): co-developed the scripts, checks and
  documentation with Francis.

All results in this repository were run and verified by Francis: hydrostatic scaling on Nibi,
nonhydrostatic benchmarks on rondeau, platform tests on every machine above.

## Quick start

**Alliance clusters** (on Trillium, from the GPU login node; see section 11 of the guide first):

```bash
git clone https://github.com/francispoulin/Oceananigans-DRAC.git        # works for everyone
# or, if you have a GitHub SSH key set up:
# git clone git@github.com:francispoulin/Oceananigans-DRAC.git
cd Oceananigans-DRAC

export SBATCH_ACCOUNT=def-yourpi     # your group's allocation
export SALLOC_ACCOUNT=$SBATCH_ACCOUNT

source env/ocean_setup.sh            # every new terminal (or the ocean_setup alias below)
bash setup/setup.sh                  # login node, once
bash setup/setup_viz.sh              # plotting environment, once
bash tools/run_tests.sh              # platform tests: submits one job (~10 min)
```

**pelee and rondeau** (shared drive: set up once, from either):

```bash
git clone https://github.com/francispoulin/Oceananigans-DRAC.git
cd Oceananigans-DRAC
source env/ocean_setup.sh            # every new terminal (or the ocean_setup alias below)
bash setup/setup.sh
bash setup/setup_viz.sh
bash tools/run_tests.sh              # runs on free GPUs via tools/run_local.sh (~10 min)
```

Runs there go through `tools/run_local.sh` instead of `sbatch` (it picks free GPUs, survives
logout and writes a log): see [docs/fluidsgpu.md](docs/fluidsgpu.md).

**Start with [docs/overview.md](docs/overview.md)** (how the pieces fit together).
The full Alliance walkthrough is [docs/drac.md](docs/drac.md), which is also posted in the
Oceananigans Discussions (https://github.com/CliMA/Oceananigans.jl/discussions/6150).

## What's here

| Path | Contents |
| --- | --- |
| `env/ocean_setup.sh` | Sourced by setup and every job; picks the machine's env file (`env/README.md`) |
| `env/drac.sh` | Modules and environment for the Alliance clusters (Nibi, Fir, Rorqual, Trillium) |
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
| `tests/` | Platform tests (1 and 4 GPUs by default); run all with `tools/run_tests.sh` (`tests/README.md`) |
| `results/` | Scaling and benchmark results; platform test summaries in `results/tests/` |
| `docs/` | Overview and machine guides (`drac.md`, `fluidsgpu.md`) |

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
bash $OCEANANIGANS_DRAC_ROOT/tools/run_tests.sh                       # platform tests (after setup or updates)
julia --project=$OCEANANIGANS_DRAC_ROOT/viz scripts/make_movies.jl      # plots, with viz/
```

Plotting jobs on the Alliance: `sbatch $OCEANANIGANS_DRAC_ROOT/jobs/viz.sh scripts/make_movies.jl`.
On pelee and rondeau: `bash $OCEANANIGANS_DRAC_ROOT/tools/run_local.sh -n 0 --viz scripts/make_movies.jl`.

## Contributing

Corrections and other clusters are welcome: open an issue or a pull request. A new machine
needs an `env/<machine>.sh` providing the variables in [env/README.md](env/README.md), and a case
in `env/ocean_setup.sh`.

## License

MIT; see [LICENSE](LICENSE).
