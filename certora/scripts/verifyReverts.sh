#!/bin/bash

set -euxo pipefail

certoraRun \
    certora/harness/MorphoHarness.sol \
    --verify MorphoHarness:certora/specs/Reverts.spec \
    --msg "Morpho Blue Reverts" \
    "$@"
