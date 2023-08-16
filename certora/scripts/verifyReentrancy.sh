#!/bin/bash

set -euxo pipefail

certoraRun \
    certora/harness/MorphoHarness.sol \
    --verify MorphoHarness:certora/specs/Reentrancy.spec \
    --prover_args '-enableStorageSplitting false' \
    --loop_iter 3 \
    --optimistic_loop \
    --msg "Check Reentrancy" \
    "$@"
