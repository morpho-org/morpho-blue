#!/bin/bash

set -euxo pipefail

make -C certora munged

certoraRun \
    certora/harness/MorphoHarness.sol \
    --verify MorphoHarness:certora/specs/LibSummary.spec \
    --msg "Morpho Blue Lib Summary" \
    "$@"
