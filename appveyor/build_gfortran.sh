# Build 32-bit gfortran binary against OpenBLAS
cd $(cygpath "$START_DIR")
OBP=$(cygpath $OPENBLAS_ROOT\\$BUILD_BITS)
GCC_TAG="$(gcc -dumpversion | tr . _)"
OPENBLAS_VERSION=$(cd OpenBLAS && git describe --tags)
gfortran -I $OBP/include -o test.exe test.f90 \
    $OBP/lib/libopenblas_${OPENBLAS_VERSION}-${GCC_TAG}.a
./test
