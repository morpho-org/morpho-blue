#!/bin/bash

set -euxo pipefail

make -C certora munged

certoraRun \
    certora/harness/MorphoInternalAccess.sol \
    --verify MorphoInternalAccess:certora/specs/BlueLiveness.spec \
    --solc_allow_path src \
    --loop_iter 3 \
    --optimistic_loop \
    --msg "Morpho Blue" \
    "$@"
