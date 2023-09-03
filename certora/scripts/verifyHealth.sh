#!/bin/bash

set -euxo pipefail

make -C certora munged

certoraRun \
    certora/harness/MorphoHarness.sol \
    certora/munged/mocks/OracleMock.sol \
    --verify MorphoHarness:certora/specs/Health.spec \
    --prover_args '-smt_hashingScheme plaininjectivity' \
    --msg "Morpho Blue Health Check" \
    "$@"
