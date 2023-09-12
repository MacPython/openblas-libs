# Needs:
# $INTERFACE64 ("1" or "0")
# $PLAT (x86_64, i686, arm64, aarch64, s390x, ppc64le)


set -xe

ls libs/openblas* >/dev/null 2>&1 && true
if [ "$?" != "0" ]; then
    # inside docker
    cd /openblas
fi

mkdir -p local/openblas
mkdir -p dist
python3.7 -m pip install wheel auditwheel

# This will fail if there is more than one file in libs
tar -C local/scipy_openblas64 --strip-components=2 -xf libs/openblas*.tar.gz

# do not package the static libs and symlinks, only take the shared object
find local/scipy_openblas64/lib -maxdepth 1 -type l -delete
rm local/scipy_openblas64/lib/*.a
# cleanup from a possible earlier run of the script
rm -f local/scipy_openblas64/lib/libopenblas_python.so
mv local/scipy_openblas64/lib/libopenblas* local/scipy_openblas64/lib/libopenblas_python.so

if [ $(uname) != "Darwin" ]; then
    patchelf --set-soname libopenblas_python.so local/scipy_openblas64/lib/libopenblas_python.so
elif [ "{PLAT}" == "arm64" ]; then
    source multibuild/osx_utils.sh
    macos_arm64_cross_build_setup
fi

if [ "${INTERFACE64}" != "1" ]; then
    # rewrite the name of the project to scipy_openblas32
    # this is a hack, but apparently there is no other way to change the name
    # of a pyproject.toml project
    #
    # use the BSD variant of sed -i and remove the backup
    sed -e "s/openblas64/openblas32/" -i.bak pyproject.toml
    rm *.bak
    mv local/scipy_openblas64 local/scipy_openblas32
    sed -e "s/openblas_get_config64_/openblas_get_config/" -i.bak local/scipy_openblas32/__init__.py
    sed -e "s/openblas64/openblas32/" -i.bak local/scipy_openblas32/__main__.py
    rm local/scipy_openblas32/*.bak
fi

python3.7 -m pip wheel -w dist -vv .

if [ $(uname) == "Darwin" ]; then
    python3.7 -m pip install delocate
    delocate-wheel dist/*.whl
else
    auditwheel repair -w dist dist/*.whl
fi

if [ "${PLAT}" == "arm64" ]; then
    # Cannot test
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
