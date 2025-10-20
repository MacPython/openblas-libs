# Needs:
# $INTERFACE64 ("1" or "0")
# $PLAT (x86_64, i686, arm64, aarch64, s390x, ppc64le)

# The code below is for Travis use only.

set -xe

if [[ ! -e tools/build_prepare.sh ]];then
    cd /openblas
fi

source tools/build_prepare.sh

$PYTHON -m pip wheel -w dist -v .

auditwheel repair -w dist --lib-sdir /lib dist/*.whl
rm dist/scipy_openblas*-none-any.whl
# Add an RPATH to libgfortran:
# https://github.com/pypa/auditwheel/issues/451
if [ "$MB_ML_LIBC" == "musllinux" ]; then
    apk add zip
else
    yum install -y zip
fi
unzip dist/*.whl "*libgfortran*"
patchelf --force-rpath --set-rpath '$ORIGIN' */lib/libgfortran*
zip dist/*.whl */lib/libgfortran*

# Test that the wheel works with a different python
PYTHON=python3.11

if [ "${INTERFACE64}" != "1" ]; then
  $PYTHON -m pip install --no-index --find-links dist scipy_openblas32
  $PYTHON -m scipy_openblas32
else
  $PYTHON -m pip install --no-index --find-links dist scipy_openblas64
  $PYTHON -m scipy_openblas64
fi