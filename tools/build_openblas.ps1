# Build script for OpenBLAS on Windows
# Expects environment variables:
# $OPENBLAS_ROOT="c:\opt\openblas"
# $INTERFACE64
# $BITS
$SUFFIX = "_m64"
# Expects "gcc" to be on the path
$march="x86-64"
# https://csharp.wekeepcoding.com/article/10463345/invalid+register+for+.seh_savexmm+in+Cygwin
$extra="-fno-asynchronous-unwind-tables"
$long_double="mlong-double-64"
$plat_tag="win_amd64"
$cflags="-O2 -march=$march -mtune=generic $extra $long_double"
$fflags="$extra $cflags -frecursive -ffpe-summary=invalid,zero $long_double"

# Set suffixed-ILP64 flags
if [ "$INTERFACE64" == "1" ]; then
    interface64_flags="INTERFACE64=1 SYMBOLSUFFIX=64_"
    SYMBOLSUFFIX=64_
    # We override FCOMMON_OPT, so we need to set default integer manually
    fflags="$fflags -fdefault-integer-8"
} else {
    $interface64_flags = ""
    $SYMBOL_SUFFIX = ""
}

# https://gcc.gnu.org/bugzilla/show_bug.cgi?id=90329
$fflags="$fflags -fno-optimize-sibling-calls"

# Build OpenBLAS
make BINARY=$BUILD_BITS DYNAMIC_ARCH=1 USE_THREAD=1 USE_OPENMP=0 `
     NUM_THREADS=24 NO_WARMUP=1 NO_AFFINITY=1 CONSISTENT_FPCSR=1 `
     BUILD_LAPACK_DEPRECATED=1 TARGET=PRESCOTT BUFFERSIZE=20 `
     COMMON_OPT="$cflags" `
     FCOMMON_OPT="$fflags" `
     LDFLAGS="-lucrt -static" `
     MAX_STACK_ALLOC=2048 `
     $interface64_flags
$out_root="$OPENBLAS_ROOT\if_$IF_BITS$SUFFIX\$BUILD_BITS"
make PREFIX=$out_root $interface64_flags install
# Powershell specific?  Paths in pkg-config file lack separators.
# Patch
$pkg_cfg_pc = "$out_root\lib\pkgconfig\openblas.pc"
$unix_out_root = $out_root -replace '\\','/'
(Get-Content -path $pkg_cfg_pc -Raw)  `
    -replace "(?m)^libdir=.*$", "libdir=$unix_out_root/lib"  `
    -replace "(?m)^includedir=.*$", "includedir=$unix_out_root/include"  `
| Set-Content -Path "${pkg_cfg_pc}"
