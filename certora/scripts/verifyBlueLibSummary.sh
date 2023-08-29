#!/bin/bash

set -euxo pipefail

make -C certora munged

certoraRun \
    certora/harness/MorphoHarness.sol \
    --verify MorphoHarness:certora/specs/BlueLibSummary.spec \
    --msg "Morpho Ratio Math Summary" \
    "$@"
