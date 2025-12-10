#! /bin/bash


# Most of the content in this file comes from https://github.com/multi-build/multibuild, with some modifications
# Follow the license below

# .. _license:

# *********************
# Copyright and License
# *********************

# The multibuild package, including all examples, code snippets and attached
# documentation is covered by the 2-clause BSD license.

#     Copyright (c) 2013-2024, Matt Terry and Matthew Brett; all rights
#     reserved.

#     Redistribution and use in source and binary forms, with or without
#     modification, are permitted provided that the following conditions are
#     met:

#     1. Redistributions of source code must retain the above copyright notice,
#     this list of conditions and the following disclaimer.

#     2. Redistributions in binary form must reproduce the above copyright
#     notice, this list of conditions and the following disclaimer in the
#     documentation and/or other materials provided with the distribution.

#     THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS
#     IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
#     THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
#     PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR
#     CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
#     EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
#     PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
#     PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
#     LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
#     NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
#     SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

set -xe

if [[ "$NIGHTLY" = "true" ]]; then
    pushd OpenBLAS
    git checkout develop
    export OPENBLAS_COMMIT=$(git describe --tags --abbrev=8)
    # Set the pyproject.toml version: convert v0.3.24-30-g138ed79f to 0.3.34.30.0
    version=$(echo $OPENBLAS_COMMIT | sed -e "s/^v\(.*\)-g.*/\1/" | sed -e "s/-/./g")
    popd
    sed -e "s/^version = .*/version = \"${version}.0\"/" -i.bak pyproject.toml
else
    export OPENBLAS_COMMIT=$(cat openblas_commit.txt)
fi

if [ "$(uname)" != "Darwin" ]; then
  ./tools/install-static-clang.sh
  export PATH=/opt/clang/bin:$PATH
fi

# Work round bug in travis xcode image described at
# https://github.com/direnv/direnv/issues/210
shell_session_update() { :; }

# Workaround for https://github.com/travis-ci/travis-ci/issues/8703
# suggested by Thomas K at
# https://github.com/travis-ci/travis-ci/issues/8703#issuecomment-347881274
unset -f cd
unset -f pushd
unset -f popd

# Build OpenBLAS
source build-openblas.sh

# Build wheel
source tools/build_prepare_wheel.sh
