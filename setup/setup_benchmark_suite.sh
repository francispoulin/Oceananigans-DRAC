#!/bin/bash
# Set up the Oceananigans benchmark suite (benchmarking/ in an Oceananigans checkout) on a cluster
# other than Nibi, matching the version used for the Nibi scaling results, plus NCCL for
# MPI-vs-NCCL comparisons. Once per cluster, on a LOGIN node (needs internet), after ocean_setup:
#
#     bash setup/setup_benchmark_suite.sh          # checkout in $SCRATCH/software/Oceananigans.jl
#     BENCH_ROOT=/other/path bash setup/setup_benchmark_suite.sh
#
# Steps: clone Oceananigans at commit 8743c40d0 (v0.113.5 + 5 commits, as on Nibi); apply
# setup/patches/oceananigans_benchmarking_8743c40d0.patch (GPU memory for distributed runs, as on
# Nibi; OPAL_PREFIX from OCEAN_MPI_ROOT; new --comm MPI|NCCL option); configure_mpi.sh on
# benchmarking/; add NCCL.jl to it. Not for Nibi, whose checkout already has its own local edits.
# Then: jobs/benchmark.sh (COMM=NCCL for NCCL) or jobs/submit_hydro_nccl.sh.

set -eo pipefail
: "${OCEANANIGANS_DRAC_ROOT:?run ocean_setup first}"
ROOT="$OCEANANIGANS_DRAC_ROOT"
BENCH_ROOT="${BENCH_ROOT:-$SCRATCH/software/Oceananigans.jl}"
COMMIT=8743c40d01555030bc776110ba08edee0b041e5b
PATCH="$ROOT/setup/patches/oceananigans_benchmarking_8743c40d0.patch"

echo "== 1. Oceananigans checkout at $COMMIT in $BENCH_ROOT"
if [[ ! -d "$BENCH_ROOT/.git" ]]; then
    mkdir -p "$(dirname "$BENCH_ROOT")"
    git clone https://github.com/CliMA/Oceananigans.jl.git "$BENCH_ROOT"
fi
cd "$BENCH_ROOT"
if git apply --reverse --check "$PATCH" 2>/dev/null; then
    echo "   suite patch already applied"
else
    [[ -z "$(git status --porcelain --untracked-files=no)" ]] || {
        echo "ERROR: $BENCH_ROOT has local changes and the suite patch is not applied:"; git status --short; exit 1; }
    git cat-file -e "$COMMIT^{commit}" 2>/dev/null || { echo "   fetching (existing clone without $COMMIT)"; git fetch -q origin; }
    git checkout -q "$COMMIT"
    git apply "$PATCH"
    echo "   checked out $(git log --oneline -1) and applied the suite patch"
fi

echo "== 2. System MPI for benchmarking/ (configure_mpi.sh)"
bash "$ROOT/setup/configure_mpi.sh" "$BENCH_ROOT/benchmarking"

echo "== 3. Add NCCL.jl to benchmarking/ (other packages kept at their versions)"
julia --project="$BENCH_ROOT/benchmarking" -e 'using Pkg; Pkg.add(Pkg.PackageSpec(name="NCCL"); preserve=Pkg.PRESERVE_ALL)' || {
    echo "ERROR adding NCCL. If the message mentions CUDA compat, the suite's Project.toml allows only"
    echo "CUDA 6.0-6.1: send the error before changing anything."; exit 1; }

echo "== 4. Check: packages load and Oceananigans' NCCL extension is available"
julia --project="$BENCH_ROOT/benchmarking" -e '
    using Pkg; Pkg.status(["Oceananigans", "CUDA", "MPI", "NCCL"])
    using Oceananigans, CUDA, NCCL
    ok = Base.get_extension(Oceananigans, :OceananigansNCCLExt) !== nothing
    println(ok ? "OK: suite ready on $(gethostname()), NCCL extension loaded" : "FAIL: NCCL extension did not load")
    ok || exit(1)'
echo "Done. BENCH_DIR for jobs/benchmark.sh: $BENCH_ROOT/benchmarking"
