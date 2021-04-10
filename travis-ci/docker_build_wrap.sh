#!/bin/bash
# Depends on:
#   BUILD_PREFIX
#   PLAT
set -e

if [ "${MB_ML_VER}" == "_2_24" ]; then
    # Install gcc-9, gcc-6 is too old to build OpenBLAS
    # OpenBLAS being C/Fortran, there's very little risk of
    # symbol version issues
    apt-get update -y
    apt-get install -y --no-install-recommends dirmngr
    apt-key adv --recv-keys --keyserver keyserver.ubuntu.com 1E9377A2BA9EF27F
    echo "deb http://ppa.launchpad.net/ubuntu-toolchain-r/test/ubuntu xenial main" >> /etc/apt/sources.list
    apt-get update -y
    apt-get install -y --no-install-recommends gcc-9 gfortran-9
    export CC=gcc-9
    export FC=gfortran-9
    # Install an up-to-date binutils
    apt-get install -y --no-install-recommends bison flex gettext texinfo dejagnu quilt chrpath dwz debugedit python3 file xz-utils lsb-release zlib1g-dev procps
    curl -fsSL https://ftp.gnu.org/gnu/binutils/binutils-2.36.1.tar.xz | tar -x --xz
    pushd binutils-2.36.1
    ./configure > /dev/null
    make -j$(nproc) > /dev/null
    make install > /dev/null
    popd
fi

${CC:-gcc} --version
${FC:-gfortran} --version
as --version
ld --version

# Change into root directory of repo
cd /io
source travis-ci/build_steps.sh
do_build_lib "$PLAT" "" "$INTERFACE64"
