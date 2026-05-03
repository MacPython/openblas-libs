#! /bin/bash

set -xe

if [[ "$NIGHTLY" = "true" ]]; then
    pushd OpenBLAS
    git checkout develop
    export OPENBLAS_COMMIT=$(git describe --tags --abbrev=8)
    # Set the pyproject.toml version: convert v0.3.24-30-g138ed79f to 0.3.34.30.0
    version=$(echo $OPENBLAS_COMMIT | sed -e "s/^v\(.*\)-g.*/\1/" | sed -e "s/-/./g").0
    popd
    sed -e "s/^version = .*/version = \"${version}\"/" -i.bak pyproject.toml
else
    export OPENBLAS_COMMIT=$(cat openblas_commit.txt)
    version=$(grep "^version =" pyproject.toml | sed 's/version = "//;s/"//')
fi

obcommit=$OPENBLAS_COMMIT
# add .0 if OPENBLAS_COMMIT is an actual tag
[[ "$obcommit" == *-* ]] || obcommit="$obcommit.0"

# convert - to . in OPENBLAS_COMMIT
# strip off the last (build) number from version
if [[ "${obcommit//-/.}" != *"${version%.*}"* ]]; then
    echo "OPENBLAS_COMMIT $OPENBLAS_COMMIT does not match the pyproject.toml version $version"
    exit -1
fi

export OPENBLAS_VERSION=version
echo "creating wheel from $OPENBLAS_COMMIT (NIGHTLY is $NIGHTLY)"

case "$PLAT" in
    ppc64le|s390x|riscv64)
        ./tools/install-static-clang.sh
        export PATH=/opt/clang/bin:$PATH
        export CC="/opt/clang/bin/clang"
        export CXX="/opt/clang/bin/clang++"
        export LDFLAGS="-fuse-ld=lld"
        ;;
esac

# Build OpenBLAS
source build-openblas.sh

# Build wheel
source tools/build_prepare_wheel.sh
