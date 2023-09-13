#!/bin/bash

set -euxo pipefail

make -C certora munged

certoraRun \
    certora/harness/MorphoHarness.sol \
    --verify MorphoHarness:certora/specs/AccrueInterest.spec \
    --msg "Morpho Blue Accrue Interest" \
    "$@"
