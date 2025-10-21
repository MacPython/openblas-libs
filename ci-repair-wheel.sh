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
    if [ "$MB_ML_LIBC" == "musllinux" ]; then
      apk add zip
    else
      yum install -y zip
    fi
    unzip $1/*.whl "*libgfortran*"
    patchelf --force-rpath --set-rpath '$ORIGIN' */lib/libgfortran*
    zip $1/*.whl */lib/libgfortran*
    mkdir -p /output
    # copy libs/openblas*.tar.gz to dist/
    cp libs/openblas*.tar.gz /output/
fi
