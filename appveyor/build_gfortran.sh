# Build gfortran binary against OpenBLAS
cd $(cygpath "$START_DIR")
OBP=$(cygpath $OPENBLAS_ROOT\\$BUILD_BITS)
gfortran -I $OBP/include -o test.exe test.f90 \
    $OBP/lib/libopenblas_*.a
./test
