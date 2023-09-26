#!/bin/bash
# Upload tar.gz and wheels to ananconda.org

set -e

if [[ "$(uname -s)" == CYGWIN* ]]; then 
    our_wd=$(cygpath "$START_DIR")
    cd $our_wd
fi

pushd OpenBLAS
VERSION=$(git describe --tags --abbrev=8)
popd

if [ "$ANACONDA_SCIENTIFIC_PYTHON_UPLOAD" == "" ]; then
    echo "ANACONDA_SCIENTIFIC_PYTHON_UPLOAD is not defined: skipping."
else
    echo "Uploading OpenBLAS $VERSION to anaconda.org staging:"

    anaconda -t $ANACONDA_SCIENTIFIC_PYTHON_UPLOAD upload \
            --no-progress --force -u scientific-python-nightly-wheels \
            -t file -p "openblas-libs" -v "$VERSION" \
            -d "OpenBLAS for multibuild wheels" \
            -s "OpenBLAS for multibuild wheels" \
            builds/openblas*.zip libs/openblas*.tar.gz

    anaconda -t $ANACONDA_SCIENTIFIC_PYTHON_UPLOAD upload \
            --no-progress --force -u scientific-python-nightly-wheels \
            dist/scipy_openblas*.whl
fi
