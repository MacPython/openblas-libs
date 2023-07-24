#!/bin/bash
# Build script for OpenBLAS on Windows
set -e

our_wd=$(cygpath "$START_DIR")
cd $our_wd

pushd OpenBLAS
VERSION=$(git describe --tags --abbrev=8)
popd

if [ "$ANACONDA_SCIENTIFIC_PYTHON_UPLOAD" == "" ]; then
    echo "ANACONDA_SCIENTIFIC_PYTHON_UPLOAD is not defined: skipping."
else
    echo "Uploading OpenBLAS $VERSION to anaconda.org staging:"
    ls -lh builds/openblas*.zip

    anaconda -t $ANACONDA_SCIENTIFIC_PYTHON_UPLOAD upload \
            --no-progress --force -u scientific-python-nightly-wheels \
            -t file -p "openblas-libs" -v "$VERSION" \
            -d "OpenBLAS for multibuild wheels" \
            -s "OpenBLAS for multibuild wheels" \
            builds/openblas*.zip
fi
