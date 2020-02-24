# Building OpenBLAS

This is a repository to trigger builds of OpenBLAS on Travis-CI and Appveyor.

The OpenBLAS libraries get uploaded to
https://anaconda.org/multibuild-wheels-staging/openblas-libs/files

A project using these libraries, for Manylinux or macOS, will need the
``gfortran-install`` submodule used here, from
https://github.com/MacPython/gfortran-install

