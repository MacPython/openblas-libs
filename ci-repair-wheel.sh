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
    
    # No libgfortran rpath fixup (auditwheel #451) any more: the wheels
    # bundle no libgfortran, which is the only reason it was ever needed.
    mkdir -p /output
    # copy libs/openblas*.tar.gz to dist/
    cp libs/openblas*.tar.gz /output/
fi
