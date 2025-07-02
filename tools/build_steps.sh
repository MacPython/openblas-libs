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

function clean_code_local {
    set -ex
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
    echo in $repo_dir
    git fetch origin --tags
    echo after git fetch origin
    git checkout $build_commit
    echo after git checkout $build_commit
    git clean -fxd 
    echo after git clean
    git reset --hard
    echo after git reset
    git submodule update --init --recursive
    echo after git submodule update
    popd
}

function get_plat_tag {
    # Copied from gfortran-install/gfortran_utils.sh, modified for MB_ML_LIBC

    # Modify fat architecture tags on macOS to reflect compiled architecture
    # For non-darwin, report manylinux version
    local plat=$1
    local mb_ml_ver=${MB_ML_VER:-1}
    local mb_ml_libc=${MB_ML_LIBC:-manylinux}
    case $plat in
        i686|x86_64|arm64|universal2|intel|aarch64|s390x|ppc64le|loongarch64) ;;
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
    case $(get_os)-$plat in
        Linux-x86_64)
            local bitness=64
            local target="PRESCOTT"
            local dynamic_list="PRESCOTT NEHALEM SANDYBRIDGE HASWELL SKYLAKEX"
            ;;
        Darwin-x86_64)
            local bitness=64
            local target="CORE2"
            # Pick up the gfortran runtime libraries
            export DYLD_LIBRARY_PATH=/usr/local/lib:$DYLD_LIBRARY_PATH
            ;;
        *-i686)
            local bitness=32
            local target="PRESCOTT"
            local dynamic_list="PRESCOTT NEHALEM SANDYBRIDGE HASWELL"
            ;;
        Linux-aarch64)
            local bitness=64
            local target="ARMV8"
            ;;
        Darwin-arm64)
            local bitness=64
            local target="VORTEX"
            CFLAGS="$CFLAGS -ftrapping-math"
            ;;
        *-s390x)
            local bitness=64
            ;;
        *-ppc64le)
            local bitness=64
            local target="POWER8"
            ;;
        Linux-loongarch64)
            local target="GENERIC"
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
    set -x
    git config --global --add safe.directory '*'
    pushd OpenBLAS
    patch_source
    echo start building
    if [ "$plat" == "loongarch64" ]; then
        # https://github.com/OpenMathLib/OpenBLAS/blob/develop/.github/workflows/loongarch64.yml#L65
        echo -n > utest/test_dsdot.c
        echo "Due to the qemu versions 7.2 causing utest cases to fail,"
        echo "the utest dsdot:dsdot_n_1 have been temporarily disabled."
    fi
    if [ -v dynamic_list ]; then
        CFLAGS="$CFLAGS -fvisibility=protected -Wno-uninitialized" \
        make BUFFERSIZE=20 DYNAMIC_ARCH=1 QUIET_MAKE=1 \
            USE_OPENMP=0 NUM_THREADS=64 \
            DYNAMIC_LIST="$dynamic_list" \
            BINARY="$bitness" $interface_flags \
            TARGET="$target"
    else
        CFLAGS="$CFLAGS -fvisibility=protected -Wno-uninitialized" \
        make BUFFERSIZE=20 DYNAMIC_ARCH=1 QUIET_MAKE=1 \
            USE_OPENMP=0 NUM_THREADS=64 \
            BINARY="$bitness" $interface_flags \
            TARGET="$target"
    fi
    make PREFIX=$BUILD_PREFIX $interface_flags install
    popd
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

function build_on_travis {
    if [ ${TRAVIS_EVENT_TYPE} == "cron" ]; then
        build_lib "$PLAT" "$INTERFACE64" 1
        version=$(cd OpenBLAS && git describe --tags --abbrev=8 | sed -e "s/^v\(.*\)-g.*/\1/" | sed -e "s/-/./g")
        sed -e "s/^version = .*/version = \"${version}\"/" -i.bak pyproject.toml
    else
        build_lib "$PLAT" "$INTERFACE64" 0
    fi
}
