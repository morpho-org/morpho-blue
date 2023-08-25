#!/bin/sh

certoraRun \
    certora/harness/MorphoHarness.sol \
    --verify MorphoHarness:certora/specs/BlueLibSummary.spec \
    --msg "Morpho Ratio Math Summary" \
    "$@"
