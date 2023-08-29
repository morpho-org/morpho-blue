#!/bin/bash

set -euxo pipefail

certoraRun \
    certora/harness/MorphoHarness.sol \
    src/mocks/OracleMock.sol \
    --verify MorphoHarness:certora/specs/Health.spec \
    --loop_iter 3 \
    --optimistic_loop \
    --prover_args '-smt_hashingScheme plaininjectivity' \
    --msg "Morpho Health Check" \
    "$@"
