#! /bin/bash

set -xeo pipefail
source tools/build_steps.sh
echo "------ BEFORE BUILD ---------"
before_build

echo "------ CLEAN CODE --------"
clean_code $OPENBLAS_COMMIT
echo "------ BUILD LIB --------"
build_lib "$PLAT" "$INTERFACE64"
