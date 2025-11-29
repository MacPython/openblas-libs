#!/bin/bash
# Depends on:
#   PLAT
#   INTERFACE64 (could be missing or empty)
#   NIGHTLY (could be missing or empty)
set -e

# Change into root directory of repo
if [[ ! -e tools/build_steps.sh ]];then
    cd /io
fi
source tools/build_steps.sh
do_build_lib "$PLAT" "$INTERFACE64" "$NIGHTLY"
