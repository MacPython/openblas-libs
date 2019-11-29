# Build gfortran binary against OpenBLAS
cd $(cygpath "$START_DIR")
OBP=$(cygpath $OPENBLAS_ROOT\\$BUILD_BITS)

if [ "$INTERFACE64" == "1" ]; then
  gfortran -I $OBP/include -fdefault-integer-8 -o test.exe test64_.f90 \
      `ls $OBP/lib/libopenblas64__*.a|grep -Ev '\.(dll|dev)\.a'`
else
  gfortran -I $OBP/include -o test.exe test.f90 \
      $OBP/lib/libopenblas_*.a
fi

./test
