# Environment files

`ocean_setup.sh` is the only file you source directly. It detects the machine and sources one of:

| File | Machines | Scheduler |
| --- | --- | --- |
| `drac.sh` | Alliance clusters: Nibi, Fir, Rorqual | Slurm |
| `fluidsgpu.sh` | pelee, rondeau (Waterloo fluids group servers; shared drive) | none |

`fluidsgpu.sh` is specific to our group's servers, which not everyone can use. It is kept here as
a worked example for any machine without Slurm and with locally built modules.

## What every environment file must provide

Scripts in `setup/`, `jobs/` and `tools/` rely only on these, so a new machine needs nothing else:

| Variable | Meaning |
| --- | --- |
| `OCEANANIGANS_DRAC_ROOT` | root of this repository |
| `OCEAN_MACHINE` | short machine name, for messages and logs |
| `OCEAN_MPI_ROOT` | installation prefix of the system OpenMPI (contains `lib/libmpi.so`) |
| `OPAL_PREFIX` | set to `$OCEAN_MPI_ROOT` (see `src/drac_mpi.jl`) |
| `JULIA_DEPOT_PATH` | one depot, set after loading modules |
| `JULIA_NUM_THREADS` | default 1 |
| `JULIA_NUM_PRECOMPILE_TASKS` | default 2, so precompiling doesn't hit login-node thread limits |

plus the modules that put `julia` and the system `mpiexec` on `PATH`.
