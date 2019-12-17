# Build gfortran binary against OpenBLAS
cd $(cygpath "$START_DIR")
OBP=$(cygpath $OPENBLAS_ROOT\\$BUILD_BITS)

static_libname=`find $OBP/lib -maxdepth 1 -type f -name '*.a' \! -name '*.dll.a'`
dynamic_libname=`find $OBP/lib -maxdepth 1 -type f -name '*.dll.a'`

if [ "$INTERFACE64" == "1" ]; then
  gfortran -I $OBP/include -fdefault-integer-8 -o test.exe test64_.f90 $static_libname
  gfortran -I $OBP/include -fdefault-integer-8 -o test_dyn.exe test64_.f90 $dynamic_libname
else
  gfortran -I $OBP/include -o test.exe test.f90 $static_libname
  gfortran -I $OBP/include -o test_dyn.exe test.f90 $dynamic_libname
fi
