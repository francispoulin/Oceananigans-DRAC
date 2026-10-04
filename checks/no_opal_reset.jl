# Does MPI start correctly WITHOUT the OPAL_PREFIX reset in src/drac_mpi.jl?
#
# env/*.sh sets OPAL_PREFIX to the system OpenMPI. OpenMPI_jll >= 4.1.10 keeps an existing
# value (`get!(ENV, "OPAL_PREFIX", artifact_dir)`, Yggdrasil #14991); 4.1.9 and earlier
# overwrite it, and MPI.Init() then crashes with a symbol lookup error. Passes with 4.1.10,
# fails with 4.1.9. Run with two ranks (no GPU needed):
#
#     sbatch --nodes=1 --ntasks=2 --mem=4G --time=0:10:00 \
#            --wrap='source env/drac.sh; srun julia --project=. checks/no_opal_reset.jl'

using NCDatasets      # loads NetCDF_jll and OpenMPI_jll, as in a real run with NetCDF output
using MPI
import OpenMPI_jll

MPI.Init()            # deliberately WITHOUT drac_mpi_init()
comm = MPI.COMM_WORLD
rank, nranks = MPI.Comm_rank(comm), MPI.Comm_size(comm)
total = MPI.Allreduce(rank + 1, +, comm)

if rank == 0
    println("OpenMPI_jll $(pkgversion(OpenMPI_jll)), library $(OpenMPI_jll.libmpi_path)")
    println("OPAL_PREFIX = ", get(ENV, "OPAL_PREFIX", "(unset)"))
    ok = total == nranks * (nranks + 1) ÷ 2
    println(ok ? "PASS: MPI started on $nranks ranks without the OPAL_PREFIX reset" :
                 "FAIL: Allreduce gave $total")
end
MPI.Finalize()
