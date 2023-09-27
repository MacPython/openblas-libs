#!/bin/bash
# Upload tar.gz and wheels to ananconda.org

upload_wheels() {
    set +e -x
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

        tarballs=$(ls -d builds/openblas*.zip libs/openblas*.tar.gz 2>/dev/null)
        anaconda -t $ANACONDA_SCIENTIFIC_PYTHON_UPLOAD upload \
                --no-progress --force -u scientific-python-nightly-wheels \
                -t file -p "openblas-libs" -v "$VERSION" \
                -d "OpenBLAS for multibuild wheels" \
                -s "OpenBLAS for multibuild wheels" \
                ${tarballs}

        anaconda -t $ANACONDA_SCIENTIFIC_PYTHON_UPLOAD upload \
                --no-progress --force -u scientific-python-nightly-wheels \
                dist/scipy_openblas*.whl
    fi
}
