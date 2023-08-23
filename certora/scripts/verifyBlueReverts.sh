#!/bin/bash

set -euxo pipefail

certoraRun \
    certora/harness/MorphoHarness.sol \
    --solc_via_ir \
    --verify MorphoHarness:certora/specs/BlueReverts.spec \
    --loop_iter 3 \
    --optimistic_loop \
    --msg "Morpho Reverts" \
    "$@"
