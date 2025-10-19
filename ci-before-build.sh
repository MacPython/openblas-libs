#! /bin/bash


# Most of the content in this file comes from https://github.com/multi-build/multibuild, with some modifications 
# Follow the license below



# .. _license:

# *********************
# Copyright and License
# *********************

# The multibuild package, including all examples, code snippets and attached
# documentation is covered by the 2-clause BSD license.

#     Copyright (c) 2013-2024, Matt Terry and Matthew Brett; all rights
#     reserved.

#     Redistribution and use in source and binary forms, with or without
#     modification, are permitted provided that the following conditions are
#     met:

#     1. Redistributions of source code must retain the above copyright notice,
#     this list of conditions and the following disclaimer.

#     2. Redistributions in binary form must reproduce the above copyright
#     notice, this list of conditions and the following disclaimer in the
#     documentation and/or other materials provided with the distribution.

#     THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS
#     IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
#     THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
#     PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR
#     CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
#     EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
#     PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
#     PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
#     LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
#     NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
#     SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.



#! /bin/bash
set -xe

if [[ "$NIGHTLY" = "true" ]]; then
    # Set the pyproject.toml version: convert v0.3.24-30-g138ed79f to 0.3.34.30
    version=$(cd OpenBLAS && git describe --tags --abbrev=8 | sed -e "s/^v\(.*\)-g.*/\1/" | sed -e "s/-/./g")
    sed -e "s/^version = .*/version = \"${version}\"/" -i.bak pyproject.toml
fi


#!/bin/bash
# Utilities for both OSX and Docker Linux
# python or python3 should be on the PATH

# Only source common_utils once
if [ -n "$COMMON_UTILS_SOURCED" ]; then
    return
fi
COMMON_UTILS_SOURCED=1

# Turn on exit-if-error
set -e

MULTIBUILD_DIR=$(dirname "${BASH_SOURCE[0]}")
DOWNLOADS_SDIR=downloads
PYPY_URL=https://downloads.python.org/pypy
# For back-compatibility.  We use the "ensurepip" module now
# instead of get-pip.py
GET_PIP_URL=https://bootstrap.pypa.io/get-pip.py

# Unicode width, default 32. Used here and in travis_linux_steps.sh
# In docker_build_wrap.sh it is passed in when calling "docker run"
# The docker test images also use it when choosing the python to run
# with, so it is passed in when calling "docker run" for tests.
UNICODE_WIDTH=${UNICODE_WIDTH:-32}

if [ $(uname) == "Darwin" ]; then
  IS_MACOS=1; IS_OSX=1;
else
  # In the manylinux_2_24 image, based on Debian9, "python" is not installed
  # so link in something for the various system calls before PYTHON_EXE is set
  which python || export PATH=/opt/python/cp39-cp39/bin:$PATH

  if [ "$MB_ML_LIBC" == "musllinux" ]; then
    IS_ALPINE=1;
    MB_ML_VER=${MB_ML_VER:-"_1_2"}
  else
    # Default Manylinux version
    MB_ML_VER=${MB_ML_VER:-2014}
  fi
fi

# Work round bug in travis xcode image described at
# https://github.com/direnv/direnv/issues/210
shell_session_update() { :; }

# Workaround for https://github.com/travis-ci/travis-ci/issues/8703
# suggested by Thomas K at
# https://github.com/travis-ci/travis-ci/issues/8703#issuecomment-347881274
unset -f cd
unset -f pushd
unset -f popd

function cmd_notexit {
    # wraps a command, capturing its return code and preventing it
    # from exiting the shell. Handles -e / +e modes.
    # Parameters
    #    cmd - command
    #    any further parameters are passed to the wrapped command
    # If called without an argument, it will exit the shell with an error
    local cmd=$1
    if [ -z "$cmd" ];then echo "no command"; exit 1; fi
    if [[ $- = *e* ]]; then errexit_set=true; fi
    set +e
    ("${@:1}") ; retval=$?
    [[ -n $errexit_set ]] && set -e
    return $retval
}

# Build OpenBLAS
source build-openblas.sh


ls libs/openblas* >/dev/null 2>&1 && true
if [ "$?" != "0" ]; then
    # inside docker
    cd /project
fi
PYTHON=${PYTHON:-python3.9}

mkdir -p local/openblas
mkdir -p dist
$PYTHON -m pip install wheel auditwheel

# This will fail if there is more than one file in libs
tar -C local/scipy_openblas64 --strip-components=2 -xf libs/openblas*.tar.gz

# do not package the static libs and symlinks, only take the shared object
find local/scipy_openblas64/lib -maxdepth 1 -type l -delete
rm local/scipy_openblas64/lib/*.a
# Check that the pyproject.toml and the pkgconfig versions agree.
py_version=$(grep "^version" pyproject.toml | sed -e "s/version = \"//")
pkg_version=$(grep "version=" ./local/scipy_openblas64/lib/pkgconfig/scipy-openblas*.pc | sed -e "s/version=//" | sed -e "s/dev//")
if [[ -z "$pkg_version" ]]; then
  echo Could not read version from pkgconfig file
  exit 1
fi
if [[ $py_version != $pkg_version* ]]; then
  echo Version from pyproject.toml "$py_version" does not match version from build "pkg_version"
  exit 1
fi

if [ $(uname) == "Darwin" ]; then
  soname=$(cd local/scipy_openblas64/lib; ls libscipy_openblas*.dylib)
  echo otool -D local/scipy_openblas64/lib/$soname
  otool -D local/scipy_openblas64/lib/$soname
  # issue 153: there is a ".0" in the install_name. Remove it
  # also add a @rpath
  install_name_tool -id @rpath/$soname local/scipy_openblas64/lib/$soname
fi

rm -rf local/scipy_openblas64/lib/pkgconfig
echo "" >> LICENSE.txt
echo "----" >> LICENSE.txt
echo "" >> LICENSE.txt
if [ $(uname) == "Darwin" ]; then
    cat tools/LICENSE_osx.txt >> LICENSE.txt
else
    cat tools/LICENSE_linux.txt >> LICENSE.txt
fi

if [ "${INTERFACE64}" != "1" ]; then
    # rewrite the name of the project to scipy-openblas32
    # this is a hack, but apparently there is no other way to change the name
    # of a pyproject.toml project
    #
    # use the BSD variant of sed -i and remove the backup
    sed -e "s/openblas64/openblas32/" -i.bak pyproject.toml
    rm *.bak
    mv local/scipy_openblas64 local/scipy_openblas32
    sed -e "s/openblas_get_config64_/openblas_get_config/" -i.bak local/scipy_openblas32/__init__.py
    sed -e "s/cflags =.*/cflags = '-DBLAS_SYMBOL_PREFIX=scipy_'/" -i.bak local/scipy_openblas32/__init__.py
    sed -e "s/openblas64/openblas32/" -i.bak local/scipy_openblas32/__main__.py
    sed -e "s/openblas64/openblas32/" -i.bak local/scipy_openblas32/__init__.py
    rm local/scipy_openblas32/*.bak
fi

rm -rf dist/*
