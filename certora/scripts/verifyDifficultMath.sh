#!/bin/bash

set -euxo pipefail

certoraRun \
    certora/harness/MorphoHarness.sol \
    src/mocks/OracleMock.sol \
    --verify MorphoHarness:certora/specs/DifficultMath.spec \
    --loop_iter 3 \
    --optimistic_loop \
    --msg "Morpho Difficult Math" \
    "$@"
