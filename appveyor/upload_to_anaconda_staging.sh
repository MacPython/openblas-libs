#!/bin/bash
# Build script for OpenBLAS on Windows
set -e

our_wd=$(cygpath "$START_DIR")
cd $our_wd

pushd OpenBLAS
VERSION=$(git describe --tags)
popd

echo "Uploading OpenBLAS $VERSION to anaconda.org staging:"
ls -lh builds/openblas*.zip

anaconda -t $OPENBLAS_LIBS_STAGING_UPLOAD_TOKEN upload \
          --no-progress --force -u multibuild-wheels-staging \
          -t file -p "openblas" -v "$VERSION" \
          -d "OpenBLAS for multibuild wheels" \
          -s "OpenBLAS for multibuild wheels" \
          builds/openblas*.zip
