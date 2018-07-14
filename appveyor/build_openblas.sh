#!/bin/bash
# Build script for OpenBLAS on Windows
# Expects environment variables:
#  OPENBLAS_ROOT
#  OPENBLAS_COMMIT
#  BUILD_BITS
#  VC9_ROOT

# Paths in Unix format
OPENBLAS_ROOT=$(cygpath "$OPENBLAS_ROOT")
VC9_ROOT=$(cygpath "$VC9_ROOT")

# Our directory for later copying
our_wd=$(cygpath "$START_DIR")
cd $our_wd
# Make output directory for build artifacts
rm -rf builds
mkdir builds

cd OpenBLAS

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
    vc_arch="i386"
    plat_tag="win32"
fi
cflags="-O2 -march=$march -mtune=generic $extra"
fflags="$cflags -frecursive -ffpe-summary=invalid,zero"

# Build name for output library from gcc version and OpenBLAS commit.
GCC_TAG="gcc_$(gcc -dumpversion | tr .- _)"
OPENBLAS_VERSION=$(git describe --tags)
# Build OpenBLAS
# Variable used in creating output libraries
export LIBNAMESUFFIX=${OPENBLAS_VERSION}-${GCC_TAG}
make BINARY=$BUILD_BITS DYNAMIC_ARCH=1 USE_THREAD=1 USE_OPENMP=0 \
     NUM_THREADS=24 NO_WARMUP=1 NO_AFFINITY=1 CONSISTENT_FPCSR=1 \
     BUILD_LAPACK_DEPRECATED=1 \
     COMMON_OPT="$cflags" \
     FCOMMON_OPT="$fflags" \
     MAX_STACK_ALLOC=2048
make PREFIX=$OPENBLAS_ROOT/$BUILD_BITS install
DLL_BASENAME=libopenblas_${LIBNAMESUFFIX}
cd $OPENBLAS_ROOT
# Copy library link file for custom name
cd $BUILD_BITS/lib
# At least for the mingwpy wheel, we have to use the VC tools to build the
# export library. Maybe fixed in later binutils by patch referred to in
# https://sourceware.org/ml/binutils/2016-02/msg00002.html
cp ${our_wd}/OpenBLAS/exports/libopenblas.def ${DLL_BASENAME}.def
"$VC9_ROOT/bin/lib.exe" /machine:${vc_arch} /def:${DLL_BASENAME}.def
cd ../..
# Build template site.cfg for using this build
cat > ${BUILD_BITS}/site.cfg.template << EOF
[openblas]
libraries = $DLL_BASENAME
library_dirs = {openblas_root}\\${BUILD_BITS}\\lib
include_dirs = {openblas_root}\\${BUILD_BITS}\\include
EOF
ZIP_NAME="openblas-${OPENBLAS_VERSION}-${plat_tag}-${GCC_TAG}.zip"
zip -r $ZIP_NAME $BUILD_BITS
cp $ZIP_NAME $our_wd/builds
