#!/bin/sh

certoraRun \
    certora/harness/MorphoHarness.sol \
    --verify MorphoHarness:certora/specs/Blue.spec \
    --solc_allow_path src \
    --loop_iter 3 \
    --optimistic_loop \
    --msg "Morpho Blue" \
    --send_only \
    "$@"
