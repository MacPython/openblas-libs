# OpenBLAS

We build OpenBLAS on Travis-CI (for linux aarch64, ppc64, s390x) and github actions
for linux, windows, macOS x86_64 and macOS arm64.

Tarballs are at
https://anaconda.org/scientific-python-nightly-wheels/openblas-libs/files

A project using the tarball, for Manylinux or macOS, will need the
``gfortran-install`` submodule used here, from
https://github.com/MacPython/gfortran-install

We also build and upload a pip-installable wheel. The wheel is self-contained,
it includes all needed gfortran support libraries. On windows, this is a single
DLL. On linux we use `auditwheel repair` to mangle the shared object names.

The wheel supplies interfaces for building and using OpenBLAS in a python
project like SciPy or NumPy:

## Buildtime

- `get_include_dir()`, `get_lib_dir()` and `get_library()` for use in compiler
  or project arguments
- `get_pkg_config()` will return a multi-line text that can be saved into a
  file and used with pkg-config for build systems like meson. This works around
  the problem of [relocatable pkg-config
  files](https://docs.conan.io/en/1.43/integrations/build_system/pkg_config_pc_files.html)
  since the windows build uses pkgconfiglite v0.28 which does not support
  `--define-prefix`.

## Runtime

- importing will load openblas into the executable and provide the openblas
  symbols.
