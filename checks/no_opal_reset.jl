# Does MPI start correctly WITHOUT the OPAL_PREFIX reset in src/drac_mpi.jl?
#
# Before OpenMPI_jll 4.1.10, loading NetCDF (which loads OpenMPI_jll) overwrote OPAL_PREFIX,
# and MPI.Init() then crashed with a symbol lookup error. 4.1.10 leaves OPAL_PREFIX alone when
# its library is redirected to the system OpenMPI (Yggdrasil issue #14991), so this script
# should pass with 4.1.10 and fail with 4.1.9. Run with two ranks, OPAL_PREFIX unset:
#
#     sbatch --account=def-YOURPI --nodes=1 --ntasks-per-node=2 --gpus-per-task=h100:1 \
#            --time=0:15:00 --wrap='source env/nibi.sh; unset OPAL_PREFIX; srun julia --project=. checks/no_opal_reset.jl'

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
