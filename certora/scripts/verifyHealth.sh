#!/bin/bash

set -euxo pipefail

certoraRun \
    certora/harness/MorphoHarness.sol \
    src/mocks/OracleMock.sol \
    --verify MorphoHarness:certora/specs/Health.spec \
    --loop_iter 3 \
    --optimistic_loop \
    --msg "Morpho Health Check" \
    "$@"
