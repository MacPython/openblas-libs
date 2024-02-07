# Needs:
# $INTERFACE64 ("1" or "0")
# $PLAT (x86_64, i686, arm64, aarch64, s390x, ppc64le)


set -xe

ls libs/openblas* >/dev/null 2>&1 && true
if [ "$?" != "0" ]; then
    # inside docker
    cd /openblas
fi
PYTHON=${PYTHON:-python3.9}

mkdir -p local/openblas
mkdir -p dist
$PYTHON -m pip install wheel

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
$PYTHON -m pip wheel -w dist -vv .

if [ $(uname) == "Darwin" ]; then
    $PYTHON -m pip install delocate
    # move the mis-named scipy_openblas64-none-any.whl to a platform-specific name
    if [ "${PLAT}" == "arm64" ]; then
        for f in dist/*.whl; do mv $f "${f/%any.whl/macosx_11_0_$PLAT.whl}"; done
    else
        for f in dist/*.whl; do mv $f "${f/%any.whl/macosx_10_9_$PLAT.whl}"; done
    fi
    delocate-wheel -v dist/*.whl
else
    $PYTHON -m pip install "auditwheel>=6"
    auditwheel repair -w dist --lib-sdir /lib dist/*.whl
    rm dist/scipy_openblas*-none-any.whl
    # prepare for changing the wheel name before the upload to anaconda
    chmod a+w dist
fi

if [ "${PLAT}" == "arm64" ]; then
    # Cannot test cross-platform
    exit 0
fi
# Test that the wheel works with a different python
if [ "${INTERFACE64}" != "1" ]; then
  python3.11 -m pip install --no-index --find-links dist scipy_openblas32
  python3.11 -m scipy_openblas32
else
  python3.11 -m pip install --no-index --find-links dist scipy_openblas64
  python3.11 -m scipy_openblas64
fi
