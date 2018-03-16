# Build script for manylinux and OSX
BUILD_PREFIX=/usr/local
# OSX gfortran archive
GFORTRAN_DMG="archives/gfortran-4.9.0-Mavericks.dmg"

function before_build {
    if [ "$(uname)" == "Darwin" ]; then
        source multibuild/osx_utils.sh
        get_macpython_environment 3.5.1 venv
        source gfortran-install/gfortran_utils.sh
        install_gfortran
    fi
}

function build_lib {
    # OSX or manylinux build
    #
    # Input arg
    #     plat - one of i686, x86_64
    #
    # Depends on globals
    #     BUILD_SUFFIX - install suffix e.g. "/usr/local"
    #     GFORTRAN_DMG
    local plat=${1:-$PLAT}
    # Make directory to store built archive
    if [ "$(uname)" == "Darwin" ]; then
        # Do build, add gfortran hash to end of name
        do_build_lib "$plat" "-${GFORTRAN_SHA:0:7}"
        return
    fi
    # Manylinux wrapper
    local docker_image=quay.io/pypa/manylinux1_$plat
    docker pull $docker_image
    # Docker sources this script, and runs `do_build_lib`
    docker run --rm \
        -e BUILD_PREFIX="$BUILD_PREFIX" \
        -e PLAT="${plat}" \
        -v $PWD:/io \
        $docker_image /io/docker_build_wrap.sh
}

function do_build_lib {
    # Build openblas lib
    # Input arg
    #     plat - one of i686, x86_64
    #     suffix (optional) - suffix for output archive name
    #
    # Depends on globals
    #     BUILD_SUFFIX - install suffix e.g. "/usr/local"
    local plat=$1
    local suffix=$2
    case $plat in
        x86_64) local bitness=64 ;;
        i686) local bitness=32 ;;
        *) echo "Strange plat value $plat"; exit 1 ;;
    esac
    mkdir -p libs
    local version=$(cd OpenBLAS && git describe)
    (cd OpenBLAS \
        && make DYNAMIC_ARCH=1 USE_OPENMP=0 NUM_THREADS=64 BINARY=$bitness > /dev/null \
        && make PREFIX=$BUILD_PREFIX install )
    # Chop "v" prefix from git-describe output.
    local out_name="openblas-${version:1}-$(uname)-${plat}${suffix}.tar.gz"
    tar zcvf libs/$out_name \
        $BUILD_PREFIX/include/*blas* \
        $BUILD_PREFIX/include/*lapack* \
        $BUILD_PREFIX/lib/libopenblas* \
        $BUILD_PREFIX/lib/cmake/openblas
}
