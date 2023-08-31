#!/bin/bash

set -euxo pipefail

make -C certora munged

certoraRun \
    certora/harness/MorphoHarness.sol \
    --verify MorphoHarness:certora/specs/ConsistentState.spec \
    --solc_allow_path src \
    --loop_iter 3 \
    --optimistic_loop \
    --msg "Morpho Blue Consistent State" \
    "$@"
