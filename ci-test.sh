#!/bin/bash
set -xe

PYTHON=python3
if [ "$CIBUILDWHEEL_BUILD_IDENTIFIER" = "macosx_x86_64" ]; then
    PYTHON="arch -x86_64 python3"
fi

# Make sure the module works and that the version strings match
# cibuildwheel will install the wheel automatically
if [ "${INTERFACE64}" != "1" ]; then
  config_str=$($PYTHON -m scipy_openblas32)
else
  config_str=$($PYTHON -m scipy_openblas64)
fi
version=$($PYTHON -m pip list | grep scipy-openblas | sed 's/.*[[:space:]]//')
if [[ "$config_str" != *"$version"* ]]; then
    echo "config_str version does not match the pyproject.toml"
    exit -1
fi



$PYTHON -m pip install pkgconf
$PYTHON -m pkgconf scipy-openblas --cflags

# Check that the installed wheel carries no Fortran runtime.
source tools/gfortran_compat.sh

if [ "${INTERFACE64}" != "1" ]; then
    pkgdir=$($PYTHON -c "import scipy_openblas32 as m, pathlib; print(pathlib.Path(m.__file__).parent)")
else
    pkgdir=$($PYTHON -c "import scipy_openblas64 as m, pathlib; print(pathlib.Path(m.__file__).parent)")
fi
echo "checking installed package $pkgdir"

openblas_lib=$(ls "$pkgdir"/lib/libscipy_openblas*.so "$pkgdir"/lib/libscipy_openblas*.dylib 2>/dev/null | head -1 || true)
if [ -z "$openblas_lib" ]; then
    echo "FAIL: no OpenBLAS library found under $pkgdir/lib"
    exit 1
fi

# The library needs no Fortran runtime, so the wheel must not ship one.
found=$(find "$pkgdir" \( -name 'libgfortran*' -o -name 'libquadmath*' \) -print)
if [ -n "$found" ]; then
    echo "FAIL: the wheel still bundles the Fortran runtime:"
    echo "$found"
    exit 1
fi
assert_no_fortran_runtime "$openblas_lib"
