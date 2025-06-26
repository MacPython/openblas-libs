# Replicate the workflow from posix.yml locally on posix
# This may bitrot, compare it to the original file before using

set -e

# Set extra env
if [[ $(uname -m) == "x86_64" ]]; then
    echo got x86_64
    export TRAVIS_OS_NAME=ubuntu-latest
    export PLAT=x86_64
    # export PLAT=i86
    DOCKER_TEST_IMAGE=multibuild/xenial_${PLAT}
elif [[ $(uname -m) == arm64 ]]; then
    echo got arm64
    exit -1
else
    echo got nothing
    exit -1
    export TRAVIS_OS_NAME=osx
    export LDFLAGS="-L/Library/Developer/CommandLineTools/SDKs/MacOSX12.1.sdk/usr/lib"
    export LIBRARY_PATH="-L/Library/Developer/CommandLineTools/SDKs/MacOSX12.1.sdk/usr/lib"
    export PLAT=x86_64
    # export PLAT=arm64
    export SUFFIX=gf_c469a42
fi
export REPO_DIR=OpenBLAS
export OPENBLAS_COMMIT="v0.3.30"

# export MB_ML_LIBC=musllinux
# export MB_ML_VER=_1_1
# export MB_ML_VER=2014
export INTERFACE64=1

function install_virtualenv {
    # Install VirtualEnv
    python3 -m pip install --upgrade pip
    pip install virtualenv
}

function clean_code_local {
    # Copied from common_utils.sh, with added debugging
    local repo_dir=${1:-$REPO_DIR}
    local build_commit=${2:-$BUILD_COMMIT}
    [ -z "$repo_dir" ] && echo "repo_dir not defined" && exit 1
    [ -z "$build_commit" ] && echo "build_commit not defined" && exit 1
    # The package $repo_dir may be a submodule. git submodules do not
    # have a .git directory. If $repo_dir is copied around, tools like
    # Versioneer which require that it be a git repository are unable
    # to determine the version.  Give submodule proper git directory
    # XXX no need to do this
    # fill_submodule "$repo_dir"
    pushd $repo_dir
    git fetch origin --tags
    git checkout $build_commit
    git clean -fxd 
    git reset --hard
    git submodule update --init --recursive
    popd
}

function build_openblas {
    if [[ -z VIRTUAL_ENV ]]; then
        echo "must be run in a virtualenv"
    fi
    # Build OpenBLAS
    set -xeo pipefail
    if [ "$PLAT" == "arm64" ]; then
      sudo xcode-select -switch /Applications/Xcode_12.5.1.app
      export SDKROOT=/Applications/Xcode_12.5.1.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX11.3.sdk
      clang --version
    fi
    source tools/build_steps.sh
    echo "------ BEFORE BUILD ---------"
    before_build
    if [[ "$NIGHTLY" = "true" ]]; then
      echo "------ CLEAN CODE --------"
      clean_code $REPO_DIR develop
      echo "------ BUILD LIB --------"
      build_lib "$PLAT" "$INTERFACE64" "1"
    else
      echo "------ CLEAN CODE --------"
      clean_code $REPO_DIR $OPENBLAS_COMMIT
      echo "------ BUILD LIB --------"
      build_lib "$PLAT" "$INTERFACE64" "0"
    fi
}

# install_virtualenv
build_openblas
