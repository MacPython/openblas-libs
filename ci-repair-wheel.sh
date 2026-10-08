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
    #
    # Platforms built with NO_LIBGFORTRAN=1 bundle no libgfortran (and so no
    # libquadmath, which is the only reason this fixup is needed at all), so
    # there is nothing to repair there.  Count what we extracted and skip the
    # rest when the wheel is already clean.
    n_gfortran=$(python3 -c "
import re, sys, zipfile, pathlib
whl = next(pathlib.Path(sys.argv[1]).glob('*.whl'))
with zipfile.ZipFile(whl, 'a') as z:
    members = [m for m in z.namelist() if re.search(r'libgfortran', m)]
    z.extractall(members=members)
print(len(members))
    " "$1")
    if [ "$n_gfortran" = "0" ]; then
        echo "wheel bundles no libgfortran; skipping the auditwheel #451 rpath fixup"
    else
    patchelf --force-rpath --set-rpath '$ORIGIN' */lib/libgfortran*
    python3 -c "
import sys, zipfile, pathlib, glob
whl = next(pathlib.Path(sys.argv[1]).glob('*.whl'))
patched = {f: pathlib.Path(f).read_bytes() for f in glob.glob('*/lib/libgfortran*')}

# Read all original entries, replacing patched one
entries = {}
with zipfile.ZipFile(whl, 'r') as z:
    for item in z.infolist():
        entries[item] = patched.get(item.filename, z.read(item.filename))

# Rewrite the archive
with zipfile.ZipFile(whl, 'w', compression=zipfile.ZIP_DEFLATED) as z:
    for item, data in entries.items():
        z.writestr(item, data)    
" "$1"
    fi
    mkdir -p /output
    # copy libs/openblas*.tar.gz to dist/
    cp libs/openblas*.tar.gz /output/
fi
