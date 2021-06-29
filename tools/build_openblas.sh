#!/bin/bash
# Build script for OpenBLAS on Windows
# Expects environment variables:
#  OPENBLAS_ROOT
#  OPENBLAS_COMMIT
#  BUILD_BITS
#  START_DIR
# Expects "lib.exe" and "gcc" to be on the path

set -ex

# Paths in Unix format
OPENBLAS_ROOT=$(cygpath "$OPENBLAS_ROOT")

# Our directory for later copying
our_wd=$(cygpath "$START_DIR")
cd $our_wd
# Make output directory for build artifacts
rm -rf builds
mkdir builds

cd OpenBLAS
git submodule update --init --recursive

# Check which gcc we're using
which gcc
gcc --version

# Get / clean code
git fetch origin
git checkout $OPENBLAS_COMMIT
git clean -fxd
git reset --hard
rm -rf $OPENBLAS_ROOT/$BUILD_BITS

# Set architecture flags
if [ "$BUILD_BITS" == 64 ]; then
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
if [ "$INTERFACE64" == "1" ]; then
    interface64_flags="INTERFACE64=1 SYMBOLSUFFIX=64_"
    SYMBOLSUFFIX=64_
    # We override FCOMMON_OPT, so we need to set default integer manually
    fflags="$fflags -fdefault-integer-8"
else
    interface64_flags=""
fi

# Build name for output library from gcc version and OpenBLAS commit.
GCC_TAG="gcc_$(gcc -dumpversion | tr .- _)"
OPENBLAS_VERSION=$(git describe --tags)
# Build OpenBLAS
# Variable used in creating output libraries
export LIBNAMESUFFIX=${OPENBLAS_VERSION}-${GCC_TAG}
make BINARY=$BUILD_BITS DYNAMIC_ARCH=1 USE_THREAD=1 USE_OPENMP=0 \
     NUM_THREADS=24 NO_WARMUP=1 NO_AFFINITY=1 CONSISTENT_FPCSR=1 \
     BUILD_LAPACK_DEPRECATED=1 TARGET=PRESCOTT BUFFERSIZE=20\
     COMMON_OPT="$cflags" \
     FCOMMON_OPT="$fflags" \
     MAX_STACK_ALLOC=2048 \
     $interface64_flags
make PREFIX=$OPENBLAS_ROOT/$BUILD_BITS $interface64_flags install
DLL_BASENAME=libopenblas${SYMBOLSUFFIX}_${LIBNAMESUFFIX}
if [ "$INTERFACE64" == "1" ]; then
    # OpenBLAS does not build a symbol-suffixed static library on Windows:
    # do it ourselves
    set -x  # echo commands
    static_libname=$(find . -maxdepth 1 -type f -name '*.a' \! -name '*.dll.a' | head -1)
    make -C exports $interface64_flags objcopy.def
    objcopy --redefine-syms exports/objcopy.def "${static_libname}" "${static_libname}.renamed"
    cp -f "${static_libname}.renamed" "$OPENBLAS_ROOT/$BUILD_BITS/lib/${static_libname}"
    cp -f "${static_libname}.renamed" "$OPENBLAS_ROOT/$BUILD_BITS/lib/${DLL_BASENAME}.a"
    set +x
fi
cd $OPENBLAS_ROOT
# Copy library link file for custom name
cd $BUILD_BITS/lib
# At least for the mingwpy wheel, we have to use the VC tools to build the
# export library. Maybe fixed in later binutils by patch referred to in
# https://sourceware.org/ml/binutils/2016-02/msg00002.html
cp ${our_wd}/OpenBLAS/exports/${DLL_BASENAME}.def ${DLL_BASENAME}.def
"lib.exe" /machine:${vc_arch} /def:${DLL_BASENAME}.def
cd ../..
# Build template site.cfg for using this build
cat > ${BUILD_BITS}/site.cfg.template << EOF
[openblas${SYMBOLSUFFIX}]
libraries = $DLL_BASENAME
library_dirs = {openblas_root}\\${BUILD_BITS}\\lib
include_dirs = {openblas_root}\\${BUILD_BITS}\\include
EOF
ZIP_NAME="openblas${SYMBOLSUFFIX}-${OPENBLAS_VERSION}-${plat_tag}-${GCC_TAG}.zip"
zip -r $ZIP_NAME $BUILD_BITS
cp $ZIP_NAME $our_wd/builds
