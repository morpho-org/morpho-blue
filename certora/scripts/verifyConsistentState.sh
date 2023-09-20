#!/bin/bash

set -euxo pipefail

certoraRun \
    certora/harness/MorphoHarness.sol \
    --verify MorphoHarness:certora/specs/ConsistentState.spec \
    --msg "Morpho Blue Consistent State" \
    "$@"
