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

        # Build the objconv tool
        (cd ${ROOT_DIR}/objconv && bash ../tools/build_objconv.sh)
    fi
}

function get_plat_tag {
    # Copied from gfortran-install/gfortran_utils.sh, modified for MB_ML_LIBC

    # Modify fat architecture tags on macOS to reflect compiled architecture
    # For non-darwin, report manylinux version
    local plat=$1
    local mb_ml_ver=${MB_ML_VER:-1}
    local mb_ml_libc=${MB_ML_LIBC:-manylinux}
    case $plat in
        i686|x86_64|arm64|universal2|intel|aarch64|s390x|ppc64le) ;;
        *) echo Did not recognize plat $plat; return 1 ;;
    esac
    local uname=${2:-$(uname)}
    if [ "$uname" != "Darwin" ]; then
        if [ "$plat" == "intel" ]; then
            echo plat=intel not allowed for Manylinux
            return 1
        fi
        echo "${mb_ml_libc}${mb_ml_ver}_${plat}"
        return
    fi
    # macOS 32-bit arch is i386
    [ "$plat" == "i686" ] && plat="i386"
    local target=$(echo $MACOSX_DEPLOYMENT_TARGET | tr .- _)
    echo "macosx_${target}_${plat}"
}

function build_lib {
    # OSX or manylinux build
    #
    # Input arg
    #     plat - one of i686, x86_64, arm64
    #     interface64 - 1 if build with INTERFACE64 and SYMBOLSUFFIX
    #     nightly - 1 if building for nightlies
    #
    # Depends on globals
    #     BUILD_PREFIX - install suffix e.g. "/usr/local"
    #     GFORTRAN_DMG
    #     MB_ML_VER
    set -x
    local plat=${1:-$PLAT}
    local interface64=${2:-$INTERFACE64}
    local nightly=${3:0}
    local manylinux=${MB_ML_VER:-1}
    # Make directory to store built archive
    if [ -n "$IS_OSX" ]; then
        # Do build, add gfortran hash to end of name
        wrap_wheel_builder do_build_lib "$plat" "gf_${GFORTRAN_SHA:0:7}" "$interface64" "$nightly"
        return
    fi
    # Manylinux wrapper
    local libc=${MB_ML_LIBC:-manylinux}
    local docker_image=quay.io/pypa/${libc}${manylinux}_${plat}
    docker pull $docker_image
    # Docker sources this script, and runs `do_build_lib`
    docker run --rm \
        -e BUILD_PREFIX="$BUILD_PREFIX" \
        -e PLAT="${plat}" \
        -e INTERFACE64="${interface64}" \
        -e NIGHTLY="${nightly}" \
        -e PYTHON_VERSION="$MB_PYTHON_VERSION" \
        -e MB_ML_VER=${manylinux} \
        -e MB_ML_LIBC=${libc} \
        -v $PWD:/io \
        $docker_image /io/tools/docker_build_wrap.sh
}

function patch_source {
    # Runs inside OpenBLAS directory
    # Make the patches by git format-patch <old commit>
    for f in $(ls ../patches); do
        echo applying patch $f
        git apply ../patches/$f
    done 
}

function do_build_lib {
    # Build openblas lib
    # Input arg
    #     plat - one of i686, x86_64, arm64
    #     suffix (optional) - suffix for output archive name
    #                         Suffix added with hyphen prefix
    #     interface64 (optional) - whether to build ILP64 openblas
    #                              with 64_ symbol suffix
    #     nightly (optional) - whether to build for nightlies
    #
    # Depends on globals
    #     BUILD_PREFIX - install suffix e.g. "/usr/local"
    local plat=$1
    local suffix=$2
    local interface64=$3
    local nightly=$4
    echo "Building with settings: '$plat' '$suffix' '$interface64'"
    case $(get_os)-$plat in
        Linux-x86_64)
            local bitness=64
            local target_flags="TARGET=PRESCOTT"
            ;;
        Darwin-x86_64)
            local bitness=64
            local target_flags="TARGET=CORE2"
            # Pick up the gfortran runtime libraries
            export DYLD_LIBRARY_PATH=/usr/local/lib:$DYLD_LIBRARY_PATH
            ;;
        *-i686)
            local bitness=32
            local target_flags="TARGET=PRESCOTT"
            ;;
        Linux-aarch64)
            local bitness=64
            local target_flags="TARGET=ARMV8"
            ;;
        Darwin-arm64)
            local bitness=64
            local target_flags="TARGET=VORTEX"
            ;;
        *-s390x)
            local bitness=64
            ;;
        *-ppc64le)
            local bitness=64
            local target_flags="TARGET=POWER8"
            ;;
        *) echo "Strange plat value $plat"; exit 1 ;;
    esac
    case $interface64 in
        1)
            local interface_flags="INTERFACE64=1 SYMBOLSUFFIX=64_ LIBNAMESUFFIX=64_ OBJCONV=$PWD/objconv/objconv";
            local symbolsuffix="64_";
            if [ -n "$IS_OSX" ]; then
                $PWD/objconv/objconv --help
            fi
            ;;
        *)
            local interface_flags="OBJCONV=$PWD/objconv/objconv"
            local symbolsuffix="";
            ;;
    esac
    interface_flags="$interface_flags SYMBOLPREFIX=scipy_ LIBNAMEPREFIX=scipy_ FIXED_LIBNAME=1"
    mkdir -p libs
    start_spinner
    set -x
    git config --global --add safe.directory '*'
    pushd OpenBLAS
    patch_source
    CFLAGS="$CFLAGS -fvisibility=protected -Wno-uninitialized" \
    make BUFFERSIZE=20 DYNAMIC_ARCH=1 \
        USE_OPENMP=0 NUM_THREADS=64 \
        BINARY=$bitness $interface_flags $target_flags > /dev/null
    make PREFIX=$BUILD_PREFIX $interface_flags install
    popd
    stop_spinner
    if [ "$nightly" = "1" ]; then
        local version="HEAD"
    else
        local version=$(cd OpenBLAS && git describe --tags --abbrev=8)
    fi
    mv $BUILD_PREFIX/lib/pkgconfig/openblas*.pc $BUILD_PREFIX/lib/pkgconfig/scipy-openblas.pc
    local plat_tag=$(get_plat_tag $plat)
    local suff=""
    [ -n "$suffix" ] && suff="-$suffix"
    if [ "$interface64" = "1" ]; then
        # OpenBLAS does not install the symbol suffixed static library,
        # do it ourselves
        static_libname=$(basename `find OpenBLAS -maxdepth 1 -type f -name '*.a' \! -name '*.dll.a'`)
        renamed_libname=$(basename `find OpenBLAS -maxdepth 1 -type f -name '*.renamed'`)
        cp -f "OpenBLAS/${renamed_libname}" "$BUILD_PREFIX/lib/${static_libname}"
        sed -e "s/\(^Cflags.*\)/\1 -DBLAS_SYMBOL_PREFIX=scipy_ -DBLAS_SYMBOL_SUFFIX=64_/" -i.bak $BUILD_PREFIX/lib/pkgconfig/scipy-openblas.pc
    else
        sed -e "s/\(^Cflags.*\)/\1 -DBLAS_SYMBOL_PREFIX=scipy_/" -i.bak $BUILD_PREFIX/lib/pkgconfig/scipy-openblas.pc
    rm $BUILD_PREFIX/lib/pkgconfig/scipy-openblas.pc.bak
    fi

    local out_name="openblas${symbolsuffix}-${version}-${plat_tag}${suff}.tar.gz"
    tar zcvf libs/$out_name \
        $BUILD_PREFIX/include/*blas* \
        $BUILD_PREFIX/include/*lapack* \
        $BUILD_PREFIX/lib/libscipy_openblas* \
        $BUILD_PREFIX/lib/pkgconfig/scipy-openblas* \
        $BUILD_PREFIX/lib/cmake/openblas
}
