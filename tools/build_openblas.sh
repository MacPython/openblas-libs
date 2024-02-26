#!/bin/bash
# Build script for OpenBLAS on Windows
#
# Usage: build_openblas.sh [openblas_root [build_bits [if_bits]]]
#
# e.g build_openblas.sh c:\\opt 64 32
#
# Uses the optional environment variables.  We always prefer command line argument
# values above to environment variable values:
#
#  OPENBLAS_ROOT  (default directory root for binaries, unspecified -> c:\opt).
#  BUILD_BITS  (default binary architecture, 32 or 64, unspec -> 64).
#  INTERFACE64  (1 for 64-bit interface, anything else or undefined for 32,
#                This gives the default value if if_bits not specified above).
#  START_DIR  (directory containing OpenBLAS source, unspec -> .. from here)
#  OPENBLAS_COMMIT  (unspec -> current submodule commit)
#  LDFLAGS  (example: "-lucrt -static -static-libgcc")
#
# Expects at leasts these binaries on the PATH:
# realpath, cygpath, zip, gcc, make, ar, dlltool
# usually as part of an msys installation.

set -xe

# Convert to Unix-style path
openblas_root="$(cygpath ${1:-${OPENBLAS_ROOT:-c:\\opt}})"
build_bits="${2:-${BUILD_BITS:-64}}"
if [ "$INTERFACE64" == "1" ]; then if_default=64; else if_default=32; fi
if_bits=${3:-${if_default}}
# Our directory for later copying
if [ -z "$START_DIR" ]; then
    our_wd="$(realpath $(dirname "${BASH_SOURCE[0]}")/..)"
else
    our_wd=$(cygpath "$START_DIR")
fi

echo "Building from $our_wd, to $openblas_root"
echo "Binaries are $build_bits bit, interface is $if_bits bit"
echo "Using gcc at $(which gcc), --version:"
gcc --version

# Make output directory for build artifacts
builds_dir="$our_wd/builds"
rm -rf $builds_dir
mkdir $builds_dir

cd "${our_wd}/OpenBLAS"
git submodule update --init --recursive


# Get / clean code
git fetch origin
if [ -n "$OPENBLAS_COMMIT" ]; then
    git checkout $OPENBLAS_COMMIT
fi
git clean -fxd
git reset --hard
rm -rf $openblas_root/$build_bits

# Set architecture flags
if [ "$build_bits" == 64 ]; then
    march="x86-64"
    # https://csharp.wekeepcoding.com/article/10463345/invalid+register+for+.seh_savexmm+in+Cygwin
    extra="-fno-asynchronous-unwind-tables"
    vc_arch="X64"
    plat_tag="win_amd64"
else
    march=pentium4
    extra="-mfpmath=sse -msse2"
    fextra="-m32"
    vc_arch="i386"
    plat_tag="win32"
fi
cflags="-O2 -march=$march -mtune=generic $extra"
fflags="$fextra $cflags -frecursive -ffpe-summary=invalid,zero"

# Set suffixed-ILP64 flags
if [ "$if_bits" == "64" ]; then
    SYMBOLSUFFIX="64_"
    interface_flags="INTERFACE64=1 SYMBOLSUFFIX=${SYMBOLSUFFIX}"
    # We override FCOMMON_OPT, so we need to set default integer manually
    fflags="$fflags -fdefault-integer-8"
else
    interface_flags=""
fi
# On windows, the LIBNAMEPREFIX is not needed, SYMBOLPREFIX is added to the lib
# name LIBPREFIX in Makefile.system.
interface_flags="$interface_flags SYMBOLPREFIX=scipy_ FIXED_LIBNAME=1"

# Build name for output library from gcc version and OpenBLAS commit.
GCC_TAG="gcc_$(gcc -dumpversion | tr .- _)"
OPENBLAS_VERSION=$(git describe --tags --abbrev=8)
# Build OpenBLAS
# Variable used in creating output libraries
make BINARY=$build_bits DYNAMIC_ARCH=1 USE_THREAD=1 USE_OPENMP=0 \
     NUM_THREADS=24 NO_WARMUP=1 NO_AFFINITY=1 CONSISTENT_FPCSR=1 \
     BUILD_LAPACK_DEPRECATED=1 TARGET=PRESCOTT BUFFERSIZE=20\
     LDFLAGS="$LDFLAGS" \
     COMMON_OPT="$cflags" \
     FCOMMON_OPT="$fflags" \
     MAX_STACK_ALLOC=2048 \
     $interface_flags
make PREFIX=$openblas_root/$build_bits $interface_flags install
DLL_BASENAME=libscipy_openblas${SYMBOLSUFFIX}${LIBNAMESUFFIX}

# OpenBLAS does not build a symbol-suffixed static library on Windows:
# do it ourselves. On 32-bit builds, the objcopy.def names need a '_' prefix
static_libname=$(find . -maxdepth 1 -type f -name '*.a' \! -name '*.dll.a' | tail -1)
make -C exports $interface_flags objcopy.def

if [ "$build_bits" == "32" ]; then
  sed -i "s/^/_/" exports/objcopy.def
  sed -i "s/scipy_/_scipy_/" exports/objcopy.def
else
  echo not updating objcopy,def, buildbits=$build_bits
fi
echo "\nshow some of objcopy.def"
head -10 exports/objcopy.def
echo
objcopy --redefine-syms exports/objcopy.def "${static_libname}" "${static_libname}.renamed"
cp -f "${static_libname}.renamed" "$openblas_root/$build_bits/lib/${static_libname}"
cp -f "${static_libname}.renamed" "$openblas_root/$build_bits/lib/${DLL_BASENAME}.a"

cd $openblas_root
# Copy library link file for custom name
pushd $build_bits/lib
cp ${our_wd}/OpenBLAS/exports/${DLL_BASENAME}.def ${DLL_BASENAME}.def
# At least for the mingwpy wheel, we have to use the VC tools to build the
# export library. Maybe fixed in later binutils by patch referred to in
# https://sourceware.org/ml/binutils/2016-02/msg00002.html
# "lib.exe" /machine:${vc_arch} /def:${DLL_BASENAME}.def
# Maybe this will now work (after 2016 patch above).
dlltool --input-def ${DLL_BASENAME}.def \
    --output-exp ${DLL_BASENAME}.exp \
    --dllname ${DLL_BASENAME}.dll \
    --output-lib ${DLL_BASENAME}.lib
# Replace the DLL name with the generated name.
sed -i "s/ -lopenblas.*$/ -l${DLL_BASENAME:3}/g" pkgconfig/openblas*.pc
mv pkgconfig/*.pc pkgconfig/scipy-openblas.pc
if [ "$if_bits" == "64" ]; then
    sed -e "s/^Cflags.*/\0 -DBLAS_SYMBOL_PREFIX=scipy_ -DBLAS_SYMBOL_SUFFIX=64_/" -i pkgconfig/scipy-openblas.pc
else
    sed -e "s/^Cflags.*/\0 -DBLAS_SYMBOL_PREFIX=scipy_/" -i pkgconfig/scipy-openblas.pc
fi
popd
# Build template site.cfg for using this build
cat > ${build_bits}/site.cfg.template << EOF
[openblas${SYMBOLSUFFIX}]
libraries = $DLL_BASENAME
library_dirs = {openblas_root}\\${build_bits}\\lib
include_dirs = {openblas_root}\\${build_bits}\\include
EOF

ls $openblas_root/$build_bits/lib

zip_name="openblas${SYMBOLSUFFIX}-${OPENBLAS_VERSION}-${plat_tag}-${GCC_TAG}.zip"
zip -r $zip_name $build_bits
cp $zip_name ${builds_dir}
