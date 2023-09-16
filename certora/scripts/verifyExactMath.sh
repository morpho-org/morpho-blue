#!/bin/bash

set -euxo pipefail

certoraRun \
    certora/harness/MorphoHarness.sol \
    --verify MorphoHarness:certora/specs/ExactMath.spec \
    --prover_args '-smt_hashingScheme plaininjectivity -mediumTimeout 12' \
    --msg "Morpho Blue Exact Math" \
    "$@"
