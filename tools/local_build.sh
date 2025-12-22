#!bash

# Replicate the workflow from posix.yml locally on posix
# This may bitrot, compare it to the original file before using

set -e

# Set extra env
if [[ $(uname) == "Darwin" ]]; then
    # export PLAT=x86_64
    export PLAT=arm64
elif [[ $(uname -m) == "x86_64" ]]; then
    echo got x86_64
    export PLAT=x86_64
    # export PLAT=i86
elif [[ $(uname -m) == arm64 ]]; then
    echo got arm64
    exit -1
else
    echo got nothing
    exit -1
fi
export OPENBLAS_COMMIT="v0.3.30-359-g29fab2b9"

# export MB_ML_LIBC=musllinux
# export MB_ML_VER=_1_2
# export MB_ML_VER=2014
export INTERFACE64=1
export BUILD_PREFIX=/tmp/openblas
mkdir -p $BUILD_PREFIX

ROOT_DIR=$(dirname $(dirname $0))
${ROOT_DIR}/build-openblas.sh
