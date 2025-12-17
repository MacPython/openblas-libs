- [ ] I updated the package version in pyproject.toml and made sure the first 3 numbers match  `./openblas_commit.txt`. If I did not update `./openblas_commit.txt`, I incremented the wheel build number (i.e. 0.3.29.0.0 to 0.3.29.0.1)

Note: update `./openblas_commit.txt` with `cd OpenBLAS; git describe --tags --abbrev=8 > ../openblas_commit.txt`
