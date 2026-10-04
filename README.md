# Oceananigans-DRAC

Scripts and instructions for running [Oceananigans.jl](https://github.com/CliMA/Oceananigans.jl)
on the GPU clusters of the Digital Research Alliance of Canada (DRAC), including multi-GPU
runs with CUDA-aware MPI.

**Status:** verified on Nibi (October 2026). Fir, and Rorqual (October 2026).
Trillium is not yet tested.

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

The full walkthrough is [docs/drac.md](docs/drac.md), which is also posted in the
Oceananigans Discussions (TODO: link).

## What's here

| Path | Contents |
| --- | --- |
| `env/drac.sh` | Modules and environment, sourced by setup and every job |
| `setup/setup.sh` | One-time setup: packages, system MPI, OpenMPI_jll redirect |
| `src/drac_mpi.jl` | `drac_mpi_init()`: starts MPI safely when NetCDF is loaded |
| `examples/` | A first Oceananigans script, on CPU or GPU |
| `jobs/` | Slurm scripts: hello on CPU and GPU, multi-GPU checks, benchmarks |
| `checks/` | Single MPI, CUDA-aware MPI, distributed vs single-GPU, NetCDF/JLD2 output |
| `results/` | Scaling results |
| `docs/` | Cluster guides |

`LocalPreferences.toml` is written by `setup/setup.sh` on each machine and is not under
version control. `Project.toml` and `Manifest.toml` will record the tested package versions.

## Contributing

Corrections and other clusters are welcome: open an issue or a pull request. A new cluster
needs an `env/<cluster>.sh` and a section in its guide.

## License

MIT; see [LICENSE](LICENSE).
