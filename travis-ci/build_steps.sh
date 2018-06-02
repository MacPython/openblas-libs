# Build script for manylinux and OSX
BUILD_PREFIX=/usr/local
# OSX gfortran archive
GFORTRAN_DMG="archives/gfortran-4.9.0-Mavericks.dmg"

ROOT_DIR=$(dirname $(dirname "${BASH_SOURCE[0]}"))
source ${ROOT_DIR}/multibuild/common_utils.sh

MB_PYTHON_VERSION=3.5.1

function get_distutils_platform {
    # Report platform as given by disutils get_platform.
    # This is the platform tag that pip will use.
    python -c "import distutils.util; print(distutils.util.get_platform())"
}

function get_macosx_target {
    # Report MACOSX_DEPLOYMENT_TARGET as given by disutils get_platform.
    python -c "import distutils.util as du; t=du.get_platform(); print(t.split('-')[1])"
}

function before_build {
    # Manylinux Python version set in build_lib
    if [ -n "$IS_OSX" ]; then
        source ${ROOT_DIR}/multibuild/osx_utils.sh
        get_macpython_environment ${MB_PYTHON_VERSION} venv
        source ${ROOT_DIR}/gfortran-install/gfortran_utils.sh
        install_gfortran
        export MACOSX_DEPLOYMENT_TARGET=$(get_macosx_target)
        echo "Deployment target $MACOSX_DEPLOYMENT_TARGET"
    fi
}

function build_lib {
    # OSX or manylinux build
    #
    # Input arg
    #     plat - one of i686, x86_64
    #
    # Depends on globals
    #     BUILD_PREFIX - install suffix e.g. "/usr/local"
    #     GFORTRAN_DMG
    local plat=${1:-$PLAT}
    # Make directory to store built archive
    if [ -n "$IS_OSX" ]; then
        # Do build, add gfortran hash to end of name
        do_build_lib "$plat" "gf_${GFORTRAN_SHA:0:7}"
        return
    fi
    # Manylinux wrapper
    local docker_image=quay.io/pypa/manylinux1_$plat
    docker pull $docker_image
    # Docker sources this script, and runs `do_build_lib`
    docker run --rm \
        -e BUILD_PREFIX="$BUILD_PREFIX" \
        -e PLAT="${plat}" \
        -e PYTHON_VERSION="$MB_PYTHON_VERSION" \
        -v $PWD:/io \
        $docker_image /io/travis-ci/docker_build_wrap.sh
}

function patch_source {
    # Patches for compile error on Manylinux around v0.3.0
    # https://github.com/xianyi/OpenBLAS/issues/1586
    # Runs inside OpenBLAS directory
    git merge-base --is-ancestor e5752ff HEAD || return 0
    git merge-base --is-ancestor a8002e2 HEAD && return 0
    patch -p1 < ../manylinux-compile.patch
}

function do_build_lib {
    # Build openblas lib
    # Input arg
    #     plat - one of i686, x86_64
    #     suffix (optional) - suffix for output archive name
    #                         Suffix added with hyphen prefix
    #
    # Depends on globals
    #     BUILD_PREFIX - install suffix e.g. "/usr/local"
    local plat=$1
    local suffix=$2
    case $plat in
        x86_64) local bitness=64 ;;
        i686) local bitness=32 ;;
        *) echo "Strange plat value $plat"; exit 1 ;;
    esac
    mkdir -p libs
    start_spinner
    (cd OpenBLAS \
    && patch_source \
    && make DYNAMIC_ARCH=1 USE_OPENMP=0 NUM_THREADS=64 BINARY=$bitness > /dev/null \
    && make PREFIX=$BUILD_PREFIX install )
    stop_spinner
    local version=$(cd OpenBLAS && git describe --tags)
    local plat_tag=$(get_distutils_platform)
    local suff=""
    [ -n "$suffix" ] && suff="-$suffix"
    local out_name="openblas-${version}-${plat_tag}${suff}.tar.gz"
    tar zcvf libs/$out_name \
        $BUILD_PREFIX/include/*blas* \
        $BUILD_PREFIX/include/*lapack* \
        $BUILD_PREFIX/lib/libopenblas* \
        $BUILD_PREFIX/lib/cmake/openblas
}
