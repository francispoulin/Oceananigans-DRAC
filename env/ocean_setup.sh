#!/bin/bash
# The environment for Oceananigans on any supported machine. Source it, don't run it:
#
#     source /path/to/oceananigans-hpc/env/ocean_setup.sh
#
# It works out which machine it is on and sources the matching file:
#
#     Alliance clusters (Nibi, Fir, Rorqual)  ->  env/drac.sh
#     pelee, rondeau (Waterloo fluids group)  ->  env/fluidsgpu.sh
#
# A convenient alias for ~/.bashrc (the same line on every machine; only the path differs):
#
#     alias ocean_setup='source /path/to/oceananigans-hpc/env/ocean_setup.sh'
#
# To add a machine: write env/<machine>.sh (copy fluidsgpu.sh for a machine without Slurm)
# and add a case below. Every env file must export the variables listed in env/README.md.

_ocean_env_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_ocean_host="$(hostname -s 2>/dev/null || hostname)"

if [[ -n "$CC_CLUSTER" ]]; then                       # set on every Alliance cluster
    source "$_ocean_env_dir/drac.sh"
else
    case "$_ocean_host" in
        pelee*|rondeau*) source "$_ocean_env_dir/fluidsgpu.sh" ;;
        *) echo "ocean_setup: no environment file for machine '$_ocean_host'." >&2
           echo "             Add env/<machine>.sh and a case in env/ocean_setup.sh." >&2 ;;
    esac
fi

unset _ocean_env_dir _ocean_host
