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

First, OpenBLAS is built using `build_lib` in `tools/build_steps.sh` (on
posix in a docker and drectly on macos) or `tools/build_steps_windows.sh` on windows.

Then the shared object and header files are used to build the
wheel via `tools/build_prepare_wheel.sh` and `pip build wheel`.

If the build is on the `main` branch, the wheels are uploaded to
https://anaconda.org/scientific=python-nightly-wheels/scipy_openblas32 and
https://anaconda.org/scientific=python-nightly-wheels/scipy_openblas64 via
`tools/upload_to_anaconda_staging.sh`.

There are workflow triggers for repo admins. They can trigger a testpypi build
or a pypi build with the publish workflow, which will upload the wheels using
trusted publishing. In order to publish to PyPI, there must be a tag at the HEAD
of the branch used to publish. After merging a PR, be sure to update to main and
use annotated tags:
```
git checkout main; git pull
git tag -a v0.3.31.126.4 -m"fixed something"
```
The wheel is self-contained, it includes all needed gfortran support libraries.
On windows, this is a single DLL.

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
