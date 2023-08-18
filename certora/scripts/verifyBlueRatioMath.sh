#!/bin/sh

certoraRun \
    certora/harness/MorphoHarness.sol \
    --verify MorphoHarness:certora/specs/BlueRatioMath.spec \
    --msg "Morpho Ratio Math" \
    --prover_args '-smt_hashingScheme plaininjectivity' \
    "$@"
