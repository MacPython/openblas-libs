#!/bin/bash
# Build script for OpenBLAS on Windows
set -e

our_wd=$(cygpath "$START_DIR")
cd $our_wd

pushd OpenBLAS
VERSION=$(git describe --tags)
popd

if [ "$OPENBLAS_LIBS_STAGING_UPLOAD_TOKEN" == "" ]; then
    echo "OPENBLAS_LIBS_STAGING_UPLOAD_TOKEN is not defined: skipping."
else
    echo "Uploading OpenBLAS $VERSION to anaconda.org staging:"
    ls -lh builds/openblas*.zip

    anaconda -t $OPENBLAS_LIBS_STAGING_UPLOAD_TOKEN upload \
            --no-progress --force -u multibuild-wheels-staging \
            -t file -p "openblas-libs" -v "$VERSION" \
            -d "OpenBLAS for multibuild wheels" \
            -s "OpenBLAS for multibuild wheels" \
            builds/openblas*.zip
fi