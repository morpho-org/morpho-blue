#!/bin/bash

set -euxo pipefail

certoraRun \
    certora/harness/MorphoHarness.sol \
    --verify MorphoHarness:certora/specs/AccrueInterest.spec \
    --msg "Morpho Blue Accrue Interest" \
    "$@"
