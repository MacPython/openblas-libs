# Wheels containing OpenBLAS

1. The primary purposes of the scipy-openblas32 and scipy-openblas64 wheels are:
   - (a) to use them as build and runtime dependencies in CI and local development for NumPy and SciPy
   - (b) to be vendored into NumPy and SciPy wheels
   - (c) possibly, in the future, being used as runtime dependencies for NumPy
       and/or SciPy.
2. Other Python projects are also welcome to use these wheels for 1(a) and 1(b).
   - Please note that there is no strong guarantee of backwards compatibility
     for the symbol names nor the small Python API shipped in the wheels to
     enable linking against the shared library. If you want to use them, you
     should probably use `==` pins in the relevant CI/lock files, like NumPy
     and SciPy also do.

> [!WARNING]
> Please do not add a runtime dependency on these wheels if you're not
> NumPy or SciPy. This is not supported and likely to lead to breakage or symbol
> conflicts due to either changes in this repository or due to NumPy or SciPy
> starting to depend on a particular version of this package.

# OpenBLAS library build process

First, tarballs are built using `do_build_lib` in `tools/build_steps.sh` (on
posix in a docker and drectly on macos) or `build_openblas.sh` on windows.

Then the shared object and header files from the tarball are used to build the
wheel via `tools/build_wheel.sh`, and the wheels uploaded to
https://anaconda.org/scientific=python-nightly-wheels/scipy_openblas32 and
https://anaconda.org/scientific=python-nightly-wheels/scipy_openblas64 via
`tools/upload_to_anaconda_staging.sh`. For a release, the wheels are uploaded
to PyPI by downloading them via tools/dowlnload-wheels.py and uploading via
[twine](https://twine.readthedocs.io/en/stable/).

The wheel is self-contained, it includes all needed gfortran support libraries.
On windows, this is a single DLL. 

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
  symbols to the exectuable.
