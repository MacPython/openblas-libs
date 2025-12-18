#! /bin/bash

set -xe

ls libs/openblas* >/dev/null 2>&1 && true
if [ "$?" != "0" ]; then
    # inside docker
    cd /project
fi
PYTHON=${PYTHON:-python3.9}

mkdir -p local/openblas
mkdir -p dist

tar -C local/scipy_openblas64 --strip-components=2 -xf libs/openblas.tar.gz

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
mkdir local/scipy_openblas64/lib/pkgconfig
echo "" >> LICENSE.txt
echo "----" >> LICENSE.txt
echo "" >> LICENSE.txt
if [ $(uname) == "Darwin" ]; then
    cat tools/LICENSE_osx.txt >> LICENSE.txt
else
    cat tools/LICENSE_linux.txt >> LICENSE.txt
fi

if [ "$(uname)" == "Darwin" -a "${PLAT}" == "x86_64" ]; then
    local PYTHON="arch -x86_64 python3"
else
    local PYTHON=python3
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
    PYTHONPATH=$PWD/local $PYTHON -c "import scipy_openblas32 as s; print(s.get_pkg_config(use_prefix=True))" > local/scipy_openblas32/lib/pkgconfig/scipy-openblas.pc
else
    PYTHONPATH=$PWD/local $PYTHON -c "import scipy_openblas64 as s; print(s.get_pkg_config(use_prefix=True))" > local/scipy_openblas64/lib/pkgconfig/scipy-openblas.pc
fi

rm -rf dist/*


echo "The build preparation is done."
