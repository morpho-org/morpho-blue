#!/bin/bash

set -euxo pipefail

certoraRun \
    certora/harness/MorphoHarness.sol \
    src/mocks/OracleMock.sol \
    --verify MorphoHarness:certora/specs/Health.spec \
    --prover_args '-smt_hashingScheme plaininjectivity' \
    --msg "Morpho Blue Health Check" \
    "$@"
