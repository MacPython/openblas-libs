# Build 32-bit gfortran binary against OpenBLAS
cd $(dirname "${BASH_SOURCE[0]}")
OBP=$(cygpath $OPENBLAS_ROOT\\$BUILD_BITS)
GCC_VER=$(gcc -dumpversion | tr . _)
gfortran -I $OBP/include -o test.exe test.f90 \
    $OBP/lib/libopenblas_${OPENBLAS_COMMIT}_gcc${GCC_VER}.a
./test
