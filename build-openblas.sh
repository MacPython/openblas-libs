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


set -xeo pipefail
source tools/build_steps.sh
echo "------ BEFORE BUILD ---------"
before_build

function fill_submodule {
    # Restores .git directory to submodule, if necessary
    # See:
    # https://stackoverflow.com/questions/41776331/is-there-a-way-to-reconstruct-a-git-directory-for-a-submodule
    local repo_dir="$1"
    [ -z "$repo_dir" ] && echo "repo_dir not defined" && exit 1
    local git_loc="$repo_dir/.git"
    # For ordinary submodule, .git is a file.
    [ -d "$git_loc" ] && return
    # Need to recreate .git directory for submodule
    local origin_url=$(cd "$repo_dir" && git config --get remote.origin.url)
    local repo_copy="$repo_dir-$RANDOM"
    git clone --recursive "$repo_dir" "$repo_copy"
    rm -rf "$repo_dir"
    mv "${repo_copy}" "$repo_dir"
    (cd "$repo_dir" && git remote set-url origin $origin_url)
}

function clean_code {
    local repo_dir=${1:-$REPO_DIR}
    local build_commit=${2:-$BUILD_COMMIT}
    [ -z "$repo_dir" ] && echo "repo_dir not defined" && exit 1
    [ -z "$build_commit" ] && echo "build_commit not defined" && exit 1
    # The package $repo_dir may be a submodule. git submodules do not
    # have a .git directory. If $repo_dir is copied around, tools like
    # Versioneer which require that it be a git repository are unable
    # to determine the version.  Give submodule proper git directory
    fill_submodule "$repo_dir"
    (cd $repo_dir \
        && git fetch origin --tags \
        && git checkout $build_commit \
        && git clean -fxd \
        && git reset --hard \
        && git submodule update --init --recursive)
}


if [[ "$NIGHTLY" = "true" ]]; then
    echo "------ CLEAN CODE --------"
    clean_code $REPO_DIR develop
    echo "------ BUILD LIB --------"
    build_lib "$PLAT" "$INTERFACE64" "1"
else
    echo "------ CLEAN CODE --------"
    clean_code $REPO_DIR $OPENBLAS_COMMIT
    echo "------ BUILD LIB --------"
    build_lib "$PLAT" "$INTERFACE64" "0"
fi