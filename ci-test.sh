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
if [ "${INTERFACE64}" != "1" ]; then
  # cibuildwheel will install the wheel automatically
  # $PYTHON -m pip install --no-index --find-links /tmp/cibuildwheel/repaired_wheel scipy_openblas32
  $PYTHON -m scipy_openblas32
else
  # $PYTHON -m pip install --no-index --find-links /tmp/cibuildwheel/repaired_wheel scipy_openblas64
  $PYTHON -m scipy_openblas64
fi

$PYTHON -m pip install pkgconf
$PYTHON -m pkgconf scipy-openblas --cflags
