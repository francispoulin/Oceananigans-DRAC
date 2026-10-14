#!/bin/bash
# Make a SEPARATE Julia environment with NCCL.jl added, to test Oceananigans' NCCLDistributed
# without touching the main environment: same packages and versions as this repository's
# Manifest, plus NCCL. Once per machine (needs internet: run it on a login node / pelee):
#
#     bash setup/setup_nccl_env.sh [DIR]     # default DIR: $OCEANANIGANS_DRAC_ROOT/envs/nccl
#
# Then run with it:  bash tools/run_local.sh -p envs/nccl ...  (envs/ is not committed).
# Delete the folder to remove it; nothing else changes.

set -eo pipefail
: "${OCEANANIGANS_DRAC_ROOT:?run ocean_setup first}"
ROOT="$OCEANANIGANS_DRAC_ROOT"
DIR="${1:-$ROOT/envs/nccl}"
mkdir -p "$DIR"
DIR="$(cd "$DIR" && pwd)"
cp "$ROOT/Project.toml" "$ROOT/Manifest.toml" "$DIR/"

echo "== 1. Add NCCL.jl to $DIR, keeping every other package at its current version"
julia --project="$DIR" -e 'using Pkg; Pkg.add(Pkg.PackageSpec(name="NCCL"); preserve=Pkg.PRESERVE_ALL)'

echo "== 2. System MPI for this environment (as for any project folder)"
bash "$ROOT/setup/configure_mpi.sh" "$DIR"

echo "== 3. Check versions and that Oceananigans' NCCL extension loads"
julia --project="$DIR" -e '
    using Pkg; Pkg.status(["Oceananigans", "CUDA", "NCCL", "NCCL_jll"]; mode=Pkg.PKGMODE_MANIFEST)
    using Oceananigans, CUDA, NCCL
    ext = Base.get_extension(Oceananigans, :OceananigansNCCLExt)
    println(ext === nothing ? "FAIL: OceananigansNCCLExt did not load" : "OK: OceananigansNCCLExt loaded")
    ext === nothing && exit(1)'

echo "Done. Use: bash tools/run_local.sh -p $DIR ... (Oceananigans version must match the main environment above)."
