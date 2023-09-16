#!/bin/bash

set -euxo pipefail

certoraRun \
    certora/harness/MorphoHarness.sol \
    --verify MorphoHarness:certora/specs/Reentrancy.spec \
    --prover_args '-enableStorageSplitting false' \
    --msg "Morpho Blue Reentrancy" \
    "$@"
