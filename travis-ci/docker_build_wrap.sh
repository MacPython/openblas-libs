#!/bin/bash
# Depends on:
#   BUILD_PREFIX
#   PLAT
set -e

# Change into root directory of repo
cd /io
source travis-ci/build_steps.sh
do_build_lib "$PLAT" "" "$INTERFACE64"
