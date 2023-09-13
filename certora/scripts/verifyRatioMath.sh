#!/bin/bash

set -euxo pipefail

make -C certora munged

certoraRun \
    certora/harness/MorphoHarness.sol \
    --verify MorphoHarness:certora/specs/RatioMath.spec \
    --prover_args '-smt_hashingScheme plaininjectivity' \
    --msg "Morpho Blue Ratio Math" \
    "$@"
