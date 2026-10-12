# Checks one Julia project folder for tools/check_env.sh. Uses only the standard library and
# loads no packages, so it is quick and safe on a login node. Exit code = number of warnings.

using TOML

const project = abspath(get(ARGS, 1, "."))
const mpiroot = get(ENV, "OCEAN_MPI_ROOT", "")
const vizdir  = joinpath(get(ENV, "OCEANANIGANS_DRAC_ROOT", ""), "viz")
nwarn = 0
ok(s)   = println("  \e[32mOK\e[0m    ", s)
warn(s) = (global nwarn += 1; println("  \e[33mWARN\e[0m  ", s))
info(s) = println("        ", s)

readtoml(f) = isfile(f) ? TOML.parsefile(f) : nothing

proj = readtoml(joinpath(project, "Project.toml"))
if proj === nothing
    warn("no Project.toml here. Wrong folder? `julia --project=.` would create a new, empty project.")
    exit(nwarn)
end
deps = sort(collect(keys(get(proj, "deps", Dict()))))
ok("Project.toml: " * (isempty(deps) ? "no packages" : join(deps, ", ")))

manifest = readtoml(joinpath(project, "Manifest.toml"))
if manifest === nothing
    warn("no Manifest.toml: run `julia --project=. -e 'using Pkg; Pkg.instantiate()'` (login node)")
else
    mv = get(manifest, "julia_version", "?")
    if mv == string(VERSION)
        ok("Manifest made with this Julia ($mv)")
    elseif startswith(mv, "$(VERSION.major).$(VERSION.minor).")
        info("Manifest made with Julia $mv, running $VERSION: same series, usually fine")
    else
        warn("Manifest made with Julia $mv but running $VERSION: expect re-resolution or errors")
    end
end

is_viz = isdir(vizdir) && samefile(project, vizdir)
if !is_viz && any(d -> occursin("Makie", d), deps)
    info("this project has Makie ($(join(filter(d -> occursin("Makie", d), deps), ", "))). " *
         "Plotting can use viz/ instead, so simulation jobs don't load it.")
end

# MPI setup: only relevant if the project uses MPI (directly or through Oceananigans).
uses_mpi = any(in(deps), ("MPI", "Oceananigans", "NumericalEarth"))
prefs = readtoml(joinpath(project, "LocalPreferences.toml"))
if uses_mpi
    if prefs === nothing
        warn("no LocalPreferences.toml: MPI.jl will use its own MPI. Run once on this machine:")
        info("bash \$OCEANANIGANS_DRAC_ROOT/setup/configure_mpi.sh $project")
    else
        mp  = get(prefs, "MPIPreferences", Dict())
        lib = get(get(prefs, "OpenMPI_jll", Dict()), "libmpi_path", "")
        binary = get(mp, "binary", "(not set)")
        binary == "system" ? ok("MPI.jl uses the system MPI") :
                             warn("MPIPreferences binary = $binary (expected \"system\")")
        if isempty(lib)
            warn("OpenMPI_jll not redirected (NetCDF output + MPI may crash at MPI.Init)")
        elseif !isempty(mpiroot) && !startswith(lib, mpiroot)
            warn("OpenMPI_jll -> $lib, which is not this machine's MPI ($mpiroot).")
            info("LocalPreferences.toml was probably made on another machine: rerun configure_mpi.sh here.")
        else
            ok("OpenMPI_jll -> $lib")
        end
    end
end

if !is_viz
    depot = first(split(get(ENV, "JULIA_DEPOT_PATH", joinpath(homedir(), ".julia")), ':'))
    installed = isdir(joinpath(depot, "packages", "CairoMakie"))   # Manifest alone may be from git
    if !isdir(vizdir)
        info("viz/ not found in the repository")
    elseif !installed
        warn("viz/ not set up on this machine: bash \$OCEANANIGANS_DRAC_ROOT/setup/setup_viz.sh")
    else
        ok("viz/ is set up (plot with julia --project=\$OCEANANIGANS_DRAC_ROOT/viz ...)")
    end
end

exit(nwarn)
