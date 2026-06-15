## OpenBLAS v0.3.33

### 0.3.33.112.0 (2026-06-15)
- Update to v0.3.33.112

### 0.3.33.0.0 (2026-05-03)
- Update to OpenBLAS 0.3.33

## OpenBLAS v0.3.31.188 (v0.3.31-188-g4956446c)

### 0.3.31.188.1 (2026-03-23)
- Build manylinux_2_28 wheels

### 0.3.31.188.0 (2026-03-22)
- Update to v0.3.31.188

## OpenBLAS v0.3.31.159 (v0.3.31-159-g7a95460b)

### 0.3.31.159.0 (2026-03-17)
- Update to v0.3.31.159

## OpenBLAS v0.3.31.126 (v0.3.31-126-g55b16e59)

### 0.3.31.126.6 (2026-03-17)
- Replace the VERSION = in Makefile.rule with the one from pyproject.toml

### 0.3.31.126.5 (2026-03-12)
- use single workflow step for publishing to PyPI

### 0.3.31.126.4 (2026-03-12)
- refactor, add pypi publishing

### 0.3.31.126.3 (2026-03-10)
- disambiguate bewteen a NIGHTLY build and a publish build

### 0.3.31.126.2 (2026-03-10)
- Trusted publishing work

### 0.3.31.126.1 (2026-03-08)
- fix bad re-zip: use 'w' not 'a'

### 0.3.31.126.0 (2026-03-06)
- update to 0.3.31-126-g55b16e59

## OpenBLAS v0.3.31.22 (v0.3.31-22-g5ffbf38b)

### 0.3.31.22.1 (2026-02-01)
- feat: build riscv64+glibc wheel

### 0.3.31.22.0 (2026-01-20)
- update to v0.3.31-22-g5ffbf38b

## OpenBLAS v0.3.30.443 (v0.3.30-443-g52ec7faf)

### 0.3.30.443.1 (2026-01-14)
- fix typo which created bad pkgconfig file on arm64 32-bit interface

### 0.3.30.443.0 (2026-01-11)
- version

## OpenBLAS v0.3.30.359 (v0.3.30-359-g29fab2b9)

### 0.3.30.359.2 (2026-01-11)
- update OpenBLAS version

### 0.3.30.359.1 (2025-12-17)
- cleanup and single-use OPENBLAS_COMMIT via a file

### 0.3.30.359.0 (2025-11-30)
- Use clang instead of gcc to build on Linux

## OpenBLAS v0.3.30.349

### 0.3.30.349.1 (2025-11-29)
- Always use gfortran-11 on macos

### 0.3.30.349.0 (2025-11-17)
- update OpenBLAS version to v0.3.30-322-gef6f9762

## OpenBLAS v0.3.30.0

### 0.3.30.0.7 (2025-11-03)
- patch out extraneous lock/unlock

### 0.3.30.0.6 (2025-10-29)
- use gfortran-11 on macos-x86_64 build

### 0.3.30.0.5 (2025-10-23)
- cleanup clean_code, remove repo_dir, checkout OpenBLAS commit in ci-before-build.sh

### 0.3.30.0.4 (2025-10-22)
- patch to remove OpenBLAS PR 4741, cleanup unused bash code

### 0.3.30.0.3 (2025-10-21)
- Use cibuildwheel to replace multibuild

### 0.3.30.0.2 (2025-10-12)
- Using USE_THREADS & NUM_THREADS while building openblas for win arm64

### 0.3.30.0.0 (2025-06-26)
- update OpenBLAS to 0.3.30

## OpenBLAS v0.3.29.265

### 0.3.29.265.2 (2025-06-09)
- fix cmake and README

### 0.3.29.265.1 (2025-06-06)
- Refactor confusing BUILD_BITS variable in CI

### 0.3.29.265.0 (2025-06-04)
- Refactor CI to produce 64-bit integer interface wheels for WoA

## OpenBLAS v0.3.29.0

### 0.3.29.0.0 (2025-04-03)
- Add build script for Windows on ARM64
