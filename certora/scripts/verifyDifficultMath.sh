#!/bin/bash

set -euxo pipefail

make -C certora munged

certoraRun \
    certora/harness/MorphoHarness.sol \
    src/mocks/OracleMock.sol \
    --verify MorphoHarness:certora/specs/DifficultMath.spec \
    --loop_iter 3 \
    --optimistic_loop \
    --prover_args '-smt_hashingScheme plaininjectivity' \
    --msg "Morpho Difficult Math" \
    "$@"
