# Build script for manylinux and OSX
BUILD_PREFIX=${BUILD_PREFIX:-/usr/local}

ROOT_DIR=$(dirname $(dirname "${BASH_SOURCE[0]}"))

MB_PYTHON_VERSION=3.9

function any_python {
    for cmd in $PYTHON_EXE python3 python; do
        if [ -n "$(type -t $cmd)" ]; then
            echo $cmd
            return
        fi
    done
    echo "Could not find python or python3"
    exit 1
}

function get_os {
    # Report OS as given by uname
    # Use any Python that comes to hand.
    $(any_python) -c 'import platform; print(platform.uname()[0])'
}


function before_build {
    if [ ! -e /usr/local/lib ]; then
        sudo mkdir -p /usr/local/lib
        sudo chmod 777 /usr/local/lib
        touch /usr/local/lib/.dir_exists
    fi
    if [ ! -e /usr/local/include ]; then
        sudo mkdir -p /usr/local/include
        sudo chmod 777 /usr/local/include
        touch /usr/local/include/.dir_exists
    fi
    if [ -n "$IS_OSX" ]; then
        # get_macpython_environment ${MB_PYTHON_VERSION} venv
        python3.9 -m venv venv
        source venv/bin/activate
        # Use gfortran from conda
        # Since install_fortran uses `uname -a` to determine arch,
        # force the architecture when using rosetta
        unalias gfortran || true
        arch -${PLAT} bash -s << "        EOF"
            set -xe
            source tools/gfortran_utils.sh
            install_gfortran
        EOF
        # re-export these, since we ran in a shell
        export FC=$(find /opt/gfortran/gfortran-darwin-${PLAT}-native/bin -name "*-gfortran")
        local libdir=/opt/gfortran/gfortran-darwin-${PLAT}-native/lib
        export FFLAGS="-L${libdir} -Wl,-rpath,${libdir}"

        # Build the objconv tool
        (cd ${ROOT_DIR}/objconv && bash ../tools/build_objconv.sh)
    fi
}

function clean_code {
    set -ex
    # Copied from common_utils.sh, with added debugging
    local build_commit=$1
    [ -z "$build_commit" ] && echo "build_commit not defined" && exit 1
    pushd OpenBLAS
    git fetch origin --tags
    git checkout $build_commit
    git clean -fxd 
    git submodule update --init --recursive
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
    #     MB_ML_VER
    set -x
    local plat=${1:-$PLAT}
    local interface64=${2:-$INTERFACE64}
    local nightly=${3:0}
    local manylinux=${MB_ML_VER:-1}
    if [ -n "$IS_OSX" ]; then
        # Do build, add gfortran hash to end of name
        do_build_lib "$plat" "gf_${GFORTRAN_SHA:0:7}" "$interface64" "$nightly"
    else
        do_build_lib "$plat" "" "$interface64" "$nightly"
    fi
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
            export DYLD_LIBRARY_PATH=/usr/local/lib:$DYLD_LIBRARY_PATH
            CFLAGS="$CFLAGS -arch x86_64"
            export SDKROOT=${SDKROOT:-$(xcrun --show-sdk-path)}
            local dynamic_list="CORE2 NEHALEM SANDYBRIDGE HASWELL SKYLAKEX"
            MACOSX_DEPLOYMENT_TARGET="10.9"
            ;;
        *-i686)
            local bitness=32
            local target="PRESCOTT"
            local dynamic_list="PRESCOTT NEHALEM SANDYBRIDGE HASWELL"
            ;;
        Linux-aarch64)
            local bitness=64
            local target="ARMV8"
            # manylinux2014 image uses gcc-10, which miscompiles ARMV8SVE and up
            if [ "$MB_ML_VER" == "2014" ]; then
                echo setting DYNAMIC_LIST for manylinux2014 to ARMV8 only
                local dynamic_list="ARMV8"
            fi
            ;;
        Darwin-arm64)
            local bitness=64
            local target="VORTEX"
            CFLAGS="$CFLAGS -ftrapping-math -mmacos-version-min=11.0"
            MACOSX_DEPLOYMENT_TARGET="11.0"
            export SDKROOT=${SDKROOT:-$(xcrun --show-sdk-path)}
            export DYLD_LIBRARY_PATH=/usr/local/lib:$DYLD_LIBRARY_PATH
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
    if [ -n "$dynamic_list" ]; then
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


function build_lib_on_travis {
    # OSX or manylinux build
    #
    # Input arg
    #     plat - one of i686, x86_64, arm64
    #     interface64 - 1 if build with INTERFACE64 and SYMBOLSUFFIX
    #     nightly - 1 if building for nightlies
    #
    # Depends on globals
    #     BUILD_PREFIX - install suffix e.g. "/usr/local"
    #     MB_ML_VER
    set -x
    local plat=${1:-$PLAT}
    local interface64=${2:-$INTERFACE64}
    local nightly=${3:0}
    local manylinux=${MB_ML_VER:-1}

    # Manylinux wrapper
    local libc=${MB_ML_LIBC:-manylinux}
    local docker_image=quay.io/pypa/${libc}${manylinux}_${plat}
    docker pull $docker_image
    # run `do_build_lib` in the docker image
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



function build_on_travis {
    if [ ${TRAVIS_EVENT_TYPE} == "cron" ]; then
        build_lib_on_travis "$PLAT" "$INTERFACE64" 1
        version=$(cd OpenBLAS && git describe --tags --abbrev=8 | sed -e "s/^v\(.*\)-g.*/\1/" | sed -e "s/-/./g")
        sed -e "s/^version = .*/version = \"${version}\"/" -i.bak pyproject.toml
    else
        build_lib_on_travis "$PLAT" "$INTERFACE64" 0
    fi
}
