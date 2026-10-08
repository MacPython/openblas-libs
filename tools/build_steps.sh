#!bash

# Build script for manylinux and OSX
BUILD_PREFIX=${BUILD_PREFIX:-/usr/local}

ROOT_DIR=$(dirname $(dirname "${BASH_SOURCE[0]}"))

MB_PYTHON_VERSION=3.9

source $(dirname "${BASH_SOURCE[0]}")/gfortran_compat.sh

# Whether to build without a runtime dependency on libgfortran (and so
# without libquadmath, which is only ever a dependency of libgfortran itself).
#
# Enabled for every manylinux and musllinux target.  The set of libgfortran
# entry points the Fortran LAPACK sources reference is identical on all of
# them -- _gfortran_concat_string and _gfortran_etime, plus _gfortran_pow_r*_i8
# for INTERFACE64 -- because it comes from the LAPACK Fortran itself
# (`SIDE // TRANS`, `x**n`) rather than from anything architecture specific.
# If a toolchain cannot support it anyway, build_gfortran_compat returns
# non-zero and the build falls back to linking libgfortran as before.
#
# macOS is excluded for now: the link needs -Wl,--exclude-libs to keep the
# compat symbols out of the dylib's export table, and ld64 has no equivalent,
# so it would be a hard link failure rather than a fallback.  See
# tools/gfortran_compat.sh.  Windows never gets here -- it uses
# tools/build_steps_windows.sh, which already static-links libgfortran and
# asserts that libquadmath is not pulled in.
#
# Set NO_LIBGFORTRAN=0 in a CI matrix row to opt that row out, or
# NO_LIBGFORTRAN=1 to force it on.
function want_no_libgfortran {
    # want_no_libgfortran <plat>   (plat accepted but not currently needed --
    # the decision is per-OS, and callers already have it to hand)
    [ -n "$NO_LIBGFORTRAN" ] && { [ "$NO_LIBGFORTRAN" = "1" ]; return $?; }
    case "$(uname -s)" in
        Linux) return 0 ;;
        *)     return 1 ;;
    esac
}

function before_build {
    # install gfortran, objconv on macOS
    if [ "$(uname -s)" == "Darwin" ]; then
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
        # get_macpython_environment ${MB_PYTHON_VERSION} venv
        python3.9 -m venv venv
        source venv/bin/activate

        unalias gfortran 2>/dev/null || true
        source tools/gfortran_utils.sh
        download_and_unpack_gfortran ${PLAT} native
        export FC=/opt/gfortran/gfortran-darwin-${PLAT}-native/bin/gfortran
        which ${FC}
        ${FC} --version
        local libdir=/opt/gfortran/gfortran-darwin-${PLAT}-native/lib
        # Remove conflicting shared objects
        rm -fv ${libdir}/libiconv*
        export FFLAGS="-L${libdir} -Wl,-rpath,${libdir}"
        # Not clear why this is needed for tests on arm64...
        export LDFLAGS="$FFLAGS"

        # Deployment target set by gfortran_utils
        echo "Deployment target $MACOSX_DEPLOYMENT_TARGET"

        # Build the objconv tool
        if [[ ! -x  objconv/objconv ]]; then
            (cd ${ROOT_DIR}/objconv && bash ../tools/build_objconv.sh)
        fi
    fi
}

function clean_code {
    set -ex
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
        i686|x86_64|arm64|universal2|intel|aarch64|s390x|ppc64le|loongarch64|riscv64) ;;
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

function patch_source {
    # Runs inside OpenBLAS directory
    # Make the patches by git format-patch <old commit>
    for f in $(ls ../patches); do
        echo applying patch $f
        git apply ../patches/$f
    done
}

function build_lib {
    # OSX or manylinux build
    #
    # Input arg
    #     plat - one of i686, x86_64, arm64
    #     interface64 - 1 if build with INTERFACE64 and SYMBOLSUFFIX
    #
    # Depends on globals
    #     BUILD_PREFIX - install suffix e.g. "/usr/local"
    #     MB_ML_VER

    set -x
    local plat=${1:-$PLAT}
    local interface64=${2:-$INTERFACE64}

    case $(uname -s)-$plat in
        Linux-x86_64)
            local bitness=64
            local target="PRESCOTT"
            local dynamic_list="PRESCOTT NEHALEM SANDYBRIDGE HASWELL SKYLAKEX"
            ;;
        Darwin-x86_64)
            local bitness=64
            local target="CORE2"
            CFLAGS="$CFLAGS -arch x86_64"
            MACOSX_DEPLOYMENT_TARGET="10.9"
            export SDKROOT=${SDKROOT:-$(xcrun --show-sdk-path)}
            local dynamic_list="CORE2 NEHALEM SANDYBRIDGE HASWELL SKYLAKEX"
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
            CFLAGS="$CFLAGS -ftrapping-math -mmacos-version-min=11.0"
            MACOSX_DEPLOYMENT_TARGET="11.0"
            export SDKROOT=${SDKROOT:-$(xcrun --show-sdk-path)}
            ;;
        *-s390x)
            # The TargetList.txt has only ZARCH_GENERIC, Z13, Z14. Not worth
            # messing with dynamic lists.
            local bitness=64
            local target="ZARCH_GENERIC"
            ;;
        *-ppc64le)
            local bitness=64
            local target="POWER8"
            ;;
        Linux-loongarch64)
            local target="GENERIC"
            ;;
        Linux-riscv64)
            local target="GENERIC"
            ;;
        *) echo "Strange plat value $plat"; exit 1 ;;
    esac
    case $interface64 in
        1)
            local interface_flags="INTERFACE64=1 SYMBOLSUFFIX=64_ LIBNAMESUFFIX=64_ OBJCONV=$PWD/objconv/objconv";
            local symbolsuffix="64_";
            ;;
        *)
            local interface_flags="OBJCONV=$PWD/objconv/objconv"
            local symbolsuffix="";
            ;;
    esac
    interface_flags="$interface_flags SYMBOLPREFIX=scipy_ LIBNAMEPREFIX=scipy_ FIXED_LIBNAME=1"

    # Drop the libgfortran/libquadmath runtime dependency where we can.  If
    # the toolchain cannot support it (no static libgfortran.a, or the
    # objects we need are no longer self-contained) fall back to the old
    # behaviour rather than failing the build -- see tools/gfortran_compat.sh.
    local compat_lib=""
    if want_no_libgfortran "$plat"; then
        if compat_lib=$(build_gfortran_compat "$PWD/build/gfortran_compat" "$interface64"); then
            # TIMER=NONE selects LAPACK's second_NONE.f/dsecnd_NONE.f, which
            # removes the only reference to _gfortran_etime.  SECOND/DSECND
            # then return 0.0, as they already do in a C_LAPACK build.
            interface_flags="$interface_flags NO_LIBGFORTRAN=1 LIBGFORTRAN_COMPAT=$compat_lib TIMER=NONE"
            echo "building without a libgfortran runtime dependency"
        else
            compat_lib=""
            echo "WARNING: cannot drop libgfortran on ${MB_ML_LIBC:-manylinux}-$plat, linking it as usual"
        fi
    fi

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
    elif [ "$plat" == "s390x" ]; then
        sed -i 's/CTEST(samin, positive_step_1_N_70){/CTEST_SKIP(samin, positive_step_1_N_70){/g' ./utest/test_extensions/test_samin.c
        sed -i 's/CTEST(samin, negative_step_1_N_70){/CTEST_SKIP(samin, negative_step_1_N_70){/g' ./utest/test_extensions/test_samin.c
        sed -i 's/CTEST(damin, positive_step_1_N_70){/CTEST_SKIP(damin, positive_step_1_N_70){/g' ./utest/test_extensions/test_damin.c
        sed -i 's/CTEST(damin, negative_step_1_N_70){/CTEST_SKIP(damin, negative_step_1_N_70){/g' ./utest/test_extensions/test_damin.c
        echo "the utest samin/damin have been temporarily disabled."
        echo "QEMU does not support the 'lper' /'lpdr' instructions used"
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
    mv $BUILD_PREFIX/lib/pkgconfig/openblas*.pc $BUILD_PREFIX/lib/pkgconfig/scipy-openblas.pc
    local plat_tag=$(get_plat_tag $plat)
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

    if [ -n "$compat_lib" ]; then
        # The shared library picked these up from the link line (see
        # LIBGFORTRAN_COMPAT_LINK in the patch), but the static library is
        # assembled from OpenBLAS's own objects only.  Add them so
        # that linking libscipy_openblas*.a does not need libgfortran either
        # -- the .pc file no longer advertises -lgfortran in Libs.private.
        # Done after the INTERFACE64 branch above, which overwrites the
        # installed archive with the symbol-renamed one.  The renaming does
        # not touch _gfortran_* names, so order is safe either way.
        local compat_dir=$(dirname "$compat_lib")
        for static_lib in $BUILD_PREFIX/lib/libscipy_openblas*.a; do
            ar crs "$static_lib" "$compat_dir"/*.o
        done
        assert_no_fortran_runtime $BUILD_PREFIX/lib/libscipy_openblas*.so \
                                  $BUILD_PREFIX/lib/libscipy_openblas*.dylib
    fi

    local out_name="openblas.tar.gz"
    tar zcvf libs/$out_name \
        $BUILD_PREFIX/include/*blas* \
        $BUILD_PREFIX/include/*lapack* \
        $BUILD_PREFIX/lib/libscipy_openblas* \
        $BUILD_PREFIX/lib/pkgconfig/scipy-openblas* \
        $BUILD_PREFIX/lib/cmake/openblas
}
