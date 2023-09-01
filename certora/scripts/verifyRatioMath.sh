#!/bin/bash

set -euxo pipefail

make -C certora munged

certoraRun \
    certora/harness/MorphoHarness.sol \
    --verify MorphoHarness:certora/specs/RatioMath.spec \
    --solc_allow_path src \
    --prover_args '-smt_hashingScheme plaininjectivity' \
    --msg "Morpho Blue Ratio Math" \
    "$@"
