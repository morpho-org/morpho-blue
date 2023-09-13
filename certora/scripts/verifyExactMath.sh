#!/bin/bash

set -euxo pipefail

make -C certora munged

certoraRun \
    certora/harness/MorphoHarness.sol \
    src/mocks/OracleMock.sol \
    --verify MorphoHarness:certora/specs/ExactMath.spec \
    --prover_args '-smt_hashingScheme plaininjectivity -mediumTimeout 12' \
    --msg "Morpho Blue Exact Math" \
    "$@"
