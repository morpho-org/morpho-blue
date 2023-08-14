#!/bin/sh

certoraRun \
    certora/harness/MorphoHarness.sol \
    --verify MorphoHarness:certora/specs/BlueRatioMath.spec \
    --solc_allow_path src \
    --msg "Morpho Ratio Math" \
    --send_only \
    "$@"
