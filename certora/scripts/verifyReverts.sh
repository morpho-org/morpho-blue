#!/bin/bash

set -euxo pipefail

make -C certora munged

certoraRun \
    certora/harness/MorphoHarness.sol \
    --verify MorphoHarness:certora/specs/Reverts.spec \
    --loop_iter 3 \
    --optimistic_loop \
    --msg "Morpho Blue Reverts" \
    "$@"
