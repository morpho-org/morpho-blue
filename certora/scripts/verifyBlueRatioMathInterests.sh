#!/bin/sh

certoraRun \
    certora/harness/MorphoHarness.sol \
    --verify MorphoHarness:certora/specs/BlueRatioMathInterests.spec \
    --msg "Morpho accrueInterests properties" \
    "$@"
