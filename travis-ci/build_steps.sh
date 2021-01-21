# Build script for manylinux and OSX
BUILD_PREFIX=/usr/local
# OSX gfortran archive
GFORTRAN_DMG="archives/gfortran-4.9.0-Mavericks.dmg"

ROOT_DIR=$(dirname $(dirname "${BASH_SOURCE[0]}"))
source ${ROOT_DIR}/multibuild/common_utils.sh
source ${ROOT_DIR}/gfortran-install/gfortran_utils.sh

MB_PYTHON_VERSION=3.9

function before_build {
    # Manylinux Python version set in build_lib
    if [ -n "$IS_OSX" ]; then
        source ${ROOT_DIR}/multibuild/osx_utils.sh
        get_macpython_environment ${MB_PYTHON_VERSION} venv
        source ${ROOT_DIR}/gfortran-install/gfortran_utils.sh
        install_gfortran
        # Deployment target set by gfortran_utils
        echo "Deployment target $MACOSX_DEPLOYMENT_TARGET"

        if [ "$INTERFACE64" = "1" ]; then
            # Build the objconv tool
            (cd ${ROOT_DIR}/objconv && bash ../travis-ci/build_objconv.sh)
        fi
    fi
}

function build_lib {
    # OSX or manylinux build
    #
    # Input arg
    #     plat - one of i686, x86_64
    #     interface64 - 1 if build with INTERFACE64 and SYMBOLSUFFIX
    #
    # Depends on globals
    #     BUILD_PREFIX - install suffix e.g. "/usr/local"
    #     GFORTRAN_DMG
    #     MB_ML_VER
    set -x
    local plat=${1:-$PLAT}
    local interface64=${2:-$INTERFACE64}
    local manylinux=${MB_ML_VER:-1}
    # Make directory to store built archive
    if [ -n "$IS_OSX" ]; then
        # Do build, add gfortran hash to end of name
        do_build_lib "$plat" "gf_${GFORTRAN_SHA:0:7}" "$interface64"
        return
    fi
    # Manylinux wrapper
    local docker_image=quay.io/pypa/manylinux${manylinux}_${plat}
    docker pull $docker_image
    # Docker sources this script, and runs `do_build_lib`
    docker run --rm \
        -e BUILD_PREFIX="$BUILD_PREFIX" \
        -e PLAT="${plat}" \
        -e INTERFACE64="${interface64}" \
        -e PYTHON_VERSION="$MB_PYTHON_VERSION" \
        -e MB_ML_VER=${manylinux} \
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
    #     interface64 (optional) - whether to build ILP64 openblas
    #                              with 64_ symbol suffix
    #
    # Depends on globals
    #     BUILD_PREFIX - install suffix e.g. "/usr/local"
    local plat=$1
    local suffix=$2
    local interface64=$3
    echo "Building with settings: '$plat' '$suffix' '$interface64'"
    case $plat in
        x86_64)
            local bitness=64
            local target_flags="TARGET=PRESCOTT"
            if [ -n "$IS_OSX" ]; then
                target_flags="TARGET=CORE2"
            fi
            ;;
        i686)
            local bitness=32
            local target_flags="TARGET=PRESCOTT"
            ;;
        aarch64)
            local bitness=64
            local target_flags="TARGET=ARMV8"
            ;;
        arm64)
            local bitness=64
            local target_flags="TARGET=VORTEX"
            ;;
        s390x)
            local bitness=64
            ;;
        ppc64le)
            local bitness=64
            local target_flags="TARGET=POWER8"
            ;;
        *) echo "Strange plat value $plat"; exit 1 ;;
    esac
    case $interface64 in
        1)
            local interface64_flags="INTERFACE64=1 SYMBOLSUFFIX=64_ OBJCONV=$PWD/objconv/objconv";
            local symbolsuffix="64_";
            if [ -n "$IS_OSX" ]; then
                $PWD/objconv/objconv --help
            fi
            ;;
        *)
            local interface64_flags=""
            local symbolsuffix="";
            ;;
    esac
    mkdir -p libs
    start_spinner
    set -x
    (cd OpenBLAS \
    && patch_source \
    && make BUFFERSIZE=20 DYNAMIC_ARCH=1 USE_OPENMP=0 NUM_THREADS=64 BINARY=$bitness $interface64_flags $target_flags \
    && make PREFIX=$BUILD_PREFIX $interface64_flags install )
    stop_spinner
    local version=$(cd OpenBLAS && git describe --tags --abbrev=8)
    local plat_tag=$(get_distutils_platform_ex $plat)
    local suff=""
    [ -n "$suffix" ] && suff="-$suffix"
    if [ "$interface64" = "1" ]; then
        # OpenBLAS does not install the symbol suffixed static library,
        # do it ourselves
        static_libname=$(basename `find OpenBLAS -maxdepth 1 -type f -name '*.a' \! -name '*.dll.a'`)
        renamed_libname=$(basename `find OpenBLAS -maxdepth 1 -type f -name '*.renamed'`)
        # set -x  # echo commands
        cp -f "OpenBLAS/${renamed_libname}" "$BUILD_PREFIX/lib/${static_libname}"
        # set +x
    fi
    local out_name="openblas${symbolsuffix}-${version}-${plat_tag}${suff}.tar.gz"
    tar zcvf libs/$out_name \
        $BUILD_PREFIX/include/*blas* \
        $BUILD_PREFIX/include/*lapack* \
        $BUILD_PREFIX/lib/libopenblas* \
        $BUILD_PREFIX/lib/cmake/openblas
}

function upload_to_anaconda {
    if [ "$OPENBLAS_LIBS_STAGING_UPLOAD_TOKEN" == "" ]; then
        echo "OPENBLAS_LIBS_STAGING_UPLOAD_TOKEN is not defined: skipping."
    else
        anaconda -t $OPENBLAS_LIBS_STAGING_UPLOAD_TOKEN upload \
            --no-progress --force -u multibuild-wheels-staging \
            -t file -p "openblas-libs" \
            -v "$(cd OpenBLAS && git describe --tags --abbrev=8)" \
            -d "OpenBLAS for multibuild wheels" \
            -s "OpenBLAS for multibuild wheels" \
            libs/openblas*.tar.gz
    fi
}
