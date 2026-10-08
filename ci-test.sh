#!/bin/bash
# Test that the wheel works with a different python
set -xe

if [ "${PLAT}" == "arm64" ]; then
    # Cannot test
    exit 0
fi

PYTHON=python3.9
if [ "$(uname)" == "Darwin" -a "${PLAT}" == "x86_64" ]; then
    which python3.9
    PYTHON="arch -x86_64 python3.9"
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

# Check the Fortran-runtime story of the installed wheel.
#
# Note this asks the *library* what happened rather than asking
# want_no_libgfortran what we intended: build_gfortran_compat falls back to
# linking libgfortran on toolchains it cannot support (no static
# libgfortran.a on riscv64, for instance), and such a wheel legitimately
# still bundles the runtime.  The build already asserts the clean case on the
# library it produces; repeating it here catches anything
# auditwheel/delocate might reintroduce while repairing the wheel.
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

if [ -n "$(fortran_runtime_deps "$openblas_lib")" ]; then
    echo "NOTE: $(basename "$openblas_lib") links the Fortran runtime, so this"
    echo "      platform took the fallback path in build_gfortran_compat and the"
    echo "      wheel is expected to bundle it.  Nothing to assert."
else
    # The library needs no Fortran runtime, so the wheel must not ship one.
    found=$(find "$pkgdir" \( -name 'libgfortran*' -o -name 'libquadmath*' \) -print)
    if [ -n "$found" ]; then
        echo "FAIL: $(basename "$openblas_lib") needs no Fortran runtime, yet the"
        echo "      wheel still bundles it:"
        echo "$found"
        exit 1
    fi
    assert_no_fortran_runtime "$openblas_lib"
fi
