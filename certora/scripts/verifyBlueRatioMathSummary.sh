#!/bin/sh

certoraRun \
    certora/harness/MorphoHarness.sol \
    --verify MorphoHarness:certora/specs/BlueRatioMathSummary.spec \
    --msg "Morpho Ratio Math Summary" \
    "$@"
