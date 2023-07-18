# Building OpenBLAS

This is a repository to trigger builds of OpenBLAS on Travis-CI (for aarch64,
ppc64, s390x) and github actions for all the others.

The OpenBLAS libraries get uploaded to
https://anaconda.org/scientific-python-nightly-wheels/openblas-libs/files

A project using these libraries, for Manylinux or macOS, will need the
``gfortran-install`` submodule used here, from
https://github.com/MacPython/gfortran-install

