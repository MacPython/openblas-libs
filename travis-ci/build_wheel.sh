set -xe
ls libs/openblas* >/dev/null 2>&1 && true
if [ "$?" != "0" ]; then
    # inside docker
    cd /openblas
fi

mkdir -p local/openblas
# This will fail if there is more than one file in libs
tar -C local/openblas --strip-components=2 -xf libs/openblas*.tar.gz

# do not package the static libs and symlinks, only take the shared object
find local/openblas/lib -maxdepth 1 -type l -delete
rm local/openblas/lib/*.a

mv local/openblas/lib/libopenblas* local/openblas/lib/libopenblas_python.so
patchelf --set-soname libopenblas_python.so local/openblas/lib/libopenblas_python.so
python3.7 -m pip install wheel auditwheel
python3.7 -m pip wheel -w /tmp/wheelhouse -vv .
auditwheel repair -w dist/ /tmp/wheelhouse/openblas-*.whl

# Test that the wheel works with a different python
python3.11 -m pip install --no-index --find-links dist openblas
python3.11 -m openblas
