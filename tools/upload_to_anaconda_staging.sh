#!/bin/bash
# Upload tar.gz and wheels to ananconda.org

upload_wheels() {
    # use +e since the ls command will error: either zip files or tar.gz files exist
    set +e -x
    if [[ "$(uname -s)" == CYGWIN* ]]; then
        our_wd=$(cygpath "$START_DIR")
        cd $our_wd
    fi

    pushd OpenBLAS
    VERSION=$(git describe --tags --abbrev=8)
    popd

    if [ "$MULTIBUILD_WHEELS_STAGING_ACCESS" != "" ]; then
        echo "Uploading OpenBLAS $VERSION to anaconda.org/multibuild-wheels-staging"

        anaconda -t $MULTIBUILD_WHEELS_STAGING_ACCESS upload \
            --no-progress --force -u multibuild-wheels-staging \
            -t file -p "openblas-libs" -v "$VERSION" \
            -d "OpenBLAS for multibuild wheels" \
            -s "OpenBLAS for multibuild wheels" \
            libs/openblas*

    fi
}
