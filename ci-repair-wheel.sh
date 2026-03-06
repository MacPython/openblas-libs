#! /bin/bash
set -xe

PYTHON=${PYTHON:-python3.9}

if [ $(uname) == "Darwin" ]; then
    $PYTHON -m pip install delocate
    # move the mis-named scipy_openblas64-none-any.whl to a platform-specific name
    # if [ "${PLAT}" == "arm64" ]; then
    #     for f in $2/*.whl; do mv $f "${f/%any.whl/macosx_11_0_$PLAT.whl}"; done
    # else
    #     for f in $2/*.whl; do mv $f "${f/%any.whl/macosx_10_9_$PLAT.whl}"; done
    # fi
    delocate-wheel -w $1 -v $2

    cp libs/openblas*.tar.gz dist/
else
    auditwheel repair -w $1 --lib-sdir /lib $2
    # rm dist/scipy_openblas*-none-any.whl
    # rm {dest_dir}/*.whl
    
    # Add an RPATH to libgfortran:
    # https://github.com/pypa/auditwheel/issues/451
    # Use zipfile since the manylinux images do not have `zip`
    python3 -c "
import re, sys, zipfile, pathlib
whl = next(pathlib.Path(sys.argv[1]).glob('*.whl'))
with zipfile.ZipFile(whl, 'a') as z:
    members = [m for m in z.namelist() if re.search(r'libgfortran', m)]
    z.extractall(members=members)
    " "$1"
    patchelf --force-rpath --set-rpath '$ORIGIN' */lib/libgfortran*
    python3 -c "
import sys, zipfile, pathlib, glob
whl = next(pathlib.Path(sys.argv[1]).glob('*.whl'))
with zipfile.ZipFile(whl, 'a') as z:
    for f in glob.glob('*/lib/libgfortran*'):
        z.write(f)
    " "$1"
    mkdir -p /output
    # copy libs/openblas*.tar.gz to dist/
    cp libs/openblas*.tar.gz /output/
fi
