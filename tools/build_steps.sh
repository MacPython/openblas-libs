#!bash

# Build script for posix platforms
BUILD_PREFIX=${BUILD_PREFIX:-/usr/local}

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

source $(dirname "${BASH_SOURCE[0]}")/gfortran_compat.sh

function before_build {
    # install gfortran, objconv on macOS
    if [ "$MB_ML_LIBC" == "macosx" ]; then
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

        # The tarball ships libgfortran as a dylib only; fetch the static
        # archive of the same gcc release (tools/gfortran_compat.sh).
        local libgfortran_a
        if ! libgfortran_a=$(download_macos_libgfortran_a "${PLAT}"); then
            echo "ERROR: cannot fetch the static libgfortran for ${PLAT}" >&2
            exit 1
        fi
        export LIBGFORTRAN_A="$libgfortran_a"

        # Build the objconv tool
        if [[ ! -x  objconv/objconv ]]; then
            (cd ${ROOT_DIR}/objconv && bash ../tools/build_objconv.sh)
        fi
    elif [[ "$MB_ML_LIBC" == *linux ]]; then
        # Red Hat keeps static libraries in separate *-static subpackages, so
        # the images on a system gcc rather than a gcc-toolset (manylinux_2_39,
        # i.e. riscv64) have no libgfortran.a.  The archive is in the CRB repo,
        # which they already enable.  A no-op on gcc-toolset images and Alpine.
        if ! find_libgfortran_a > /dev/null; then
            echo "no static libgfortran; installing libgfortran-static"
            { dnf install -y libgfortran-static \
              || yum install -y libgfortran-static; } \
              || echo "WARNING: could not install libgfortran-static"
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
    git checkout .
    git clean -fxdq
    git submodule update --init --recursive
    popd
}

function patch_source {
    # Runs inside OpenBLAS directory
    # Make the patches by git format-patch <old commit>
    for f in ../patches-common/*.patch ../patches/*.patch; do
        [ -e "$f" ] || continue
        echo applying patch $f
        git apply "$f"
    done
}

function build_lib {
    # Input arg
    #     plat - one of i686, x86_64, arm64
    #     interface64 - 1 if build with INTERFACE64 and SYMBOLSUFFIX
    #
    # Depends on globals
    #     BUILD_PREFIX - install suffix e.g. "/usr/local"
    #     MB_ML_LIBC

    set -x
    local plat=${1:-$PLAT}
    local interface64=${2:-$INTERFACE64}

    local libc_plat=${MB_ML_LIBC}_$plat
    case $libc_plat in
        *linux_x86_64)
            local bitness=64
            local target="PRESCOTT"
            local dynamic_list="PRESCOTT NEHALEM SANDYBRIDGE HASWELL SKYLAKEX"
            ;;
        macosx_x86_64)
            local bitness=64
            local target="CORE2"
            CFLAGS="$CFLAGS -arch x86_64"
            MACOSX_DEPLOYMENT_TARGET="10.9"
            export SDKROOT=${SDKROOT:-$(xcrun --show-sdk-path)}
            local dynamic_list="CORE2 NEHALEM SANDYBRIDGE HASWELL SKYLAKEX"
            ;;
        android_x86_64)
            # This target corresponds to the instruction set extensions listed at
            # https://developer.android.com/ndk/guides/abis#86-64.
            local bitness=64
            local target="NEHALEM"
            ;;
        *_i686)
            local bitness=32
            local target="PRESCOTT"
            local dynamic_list="PRESCOTT NEHALEM SANDYBRIDGE HASWELL"
            ;;
        *linux_aarch64 | android_arm64_v8a)
            local bitness=64
            local target="ARMV8"
            ;;
        macosx_arm64)
            local bitness=64
            local target="VORTEX"
            CFLAGS="$CFLAGS -ftrapping-math -mmacos-version-min=11.0"
            MACOSX_DEPLOYMENT_TARGET="11.0"
            export SDKROOT=${SDKROOT:-$(xcrun --show-sdk-path)}
            ;;
        *_s390x)
            # The TargetList.txt has only ZARCH_GENERIC, Z13, Z14. Not worth
            # messing with dynamic lists.
            local bitness=64
            local target="ZARCH_GENERIC"
            ;;
        *_ppc64le)
            local bitness=64
            local target="POWER8"
            ;;
        *linux_loongarch64)
            local target="GENERIC"
            ;;
        *linux_riscv64)
            local target="GENERIC"
            ;;
        *) echo "Strange libc_plat value '$libc_plat'"; exit 1 ;;
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

    if [ "$MB_ML_LIBC" = "android" ]; then
        # It's difficult to install a Fortran compiler for this platform.
        interface_flags+=" NOFORTRAN=1"

        # This is the compiler for the build machine, which is used to generate some
        # build files.
        interface_flags+=" HOSTCC=cc"

        # OpenBLAS assumes objcopy has the same filename prefix as CC.
        interface_flags+=" OBJCOPY=$(dirname "$CC")/llvm-objcopy"
    else
        # DYNAMIC_ARCH isn't enabled on Android because library size is more important
        # on that platform.
        interface_flags+=" DYNAMIC_ARCH=1"

        # Replace the libgfortran/libquadmath runtime dependency with the compat
        # archive; a toolchain that cannot supply it fails the build.  TIMER=NONE
        # selects LAPACK's second_NONE.f/dsecnd_NONE.f, removing the only
        # reference to _gfortran_etime.  See tools/gfortran_compat.sh.
        local compat_lib
        if ! compat_lib=$(build_gfortran_compat "$PWD/build/gfortran_compat" "$interface64"); then
            echo "ERROR: cannot build the libgfortran compat archive for $libc_plat" >&2
            exit 1
        fi
        interface_flags="$interface_flags NO_LIBGFORTRAN=1 LIBGFORTRAN_COMPAT=$compat_lib TIMER=NONE"
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
        make BUFFERSIZE=20 QUIET_MAKE=1 \
            USE_OPENMP=0 NUM_THREADS=64 \
            DYNAMIC_LIST="$dynamic_list" \
            BINARY="$bitness" $interface_flags \
            TARGET="$target"
    else
        CFLAGS="$CFLAGS -fvisibility=protected -Wno-uninitialized" \
        make BUFFERSIZE=20 QUIET_MAKE=1 \
            USE_OPENMP=0 NUM_THREADS=64 \
            BINARY="$bitness" $interface_flags \
            TARGET="$target"
    fi
    make PREFIX=$BUILD_PREFIX $interface_flags install
    popd
    mv $BUILD_PREFIX/lib/pkgconfig/openblas*.pc $BUILD_PREFIX/lib/pkgconfig/scipy-openblas.pc
    if [ "$interface64" = "1" ]; then
        # OpenBLAS does not install the symbol suffixed static library,
        # do it ourselves
        static_libname=$(basename `find OpenBLAS -maxdepth 1 -type f -name '*.a' \! -name '*.dll.a'`)
        renamed_libname=$(basename `find OpenBLAS -maxdepth 1 -type f -name '*.renamed'`)
        cp -f "OpenBLAS/${renamed_libname}" "$BUILD_PREFIX/lib/${static_libname}"
        sed -e "s/\(^Cflags.*\)/\1 -DBLAS_SYMBOL_PREFIX=scipy_ -DBLAS_SYMBOL_SUFFIX=64_/" -i.bak $BUILD_PREFIX/lib/pkgconfig/scipy-openblas.pc
    else
        sed -e "s/\(^Cflags.*\)/\1 -DBLAS_SYMBOL_PREFIX=scipy_/" -i.bak $BUILD_PREFIX/lib/pkgconfig/scipy-openblas.pc
    fi
    rm $BUILD_PREFIX/lib/pkgconfig/scipy-openblas.pc.bak

    if [ -n "$compat_lib" ]; then
        # The shared library picked these up from the link line (see
        # LIBGFORTRAN_COMPAT_LINK in the patch), but the static one is assembled
        # from OpenBLAS's own objects only; add them there too, so that linking
        # libscipy_openblas*.a does not need libgfortran either.  Must come after
        # the INTERFACE64 branch above, which overwrites the installed archive.
        local compat_dir=$(dirname "$compat_lib")
        for static_lib in $BUILD_PREFIX/lib/libscipy_openblas*.a; do
            # An unmatched glob arrives as a literal, and `ar crs` would happily
            # create an archive at that bogus path.
            [ -f "$static_lib" ] || continue
            ar crs "$static_lib" "$compat_dir"/*.o
        done
        assert_no_fortran_runtime $BUILD_PREFIX/lib/libscipy_openblas*.so \
                                $BUILD_PREFIX/lib/libscipy_openblas*.dylib
    fi

    local out_name="openblas.tar.gz"
    pushd $BUILD_PREFIX
    tar zcvf $ROOT_DIR/libs/$out_name \
        include/*blas* \
        include/*lapack* \
        lib/libscipy_openblas* \
        lib/pkgconfig/scipy-openblas* \
        lib/cmake/openblas
    popd
}
