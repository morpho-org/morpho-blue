#!/bin/sh

certoraRun \
    src/Blue.sol \
    --verify Blue:certora/specs/Blue.spec \
    --solc_allow_path src \
    --solc solc \
    --loop_iter 3 \
    --optimistic_loop \
    --msg "Blue" \
    --send_only \
    "$@"
