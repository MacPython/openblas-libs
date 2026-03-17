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
version=$($PYTHON -m pip list | grep scipy-openblas | sed 's/.*\s//')
if [[ "$config_str" != *"$version"* ]]; then
    echo "config_str version does not match the pyproject.toml"
    exit -1
fi



$PYTHON -m pip install pkgconf
$PYTHON -m pkgconf scipy-openblas --cflags
