#!/bin/bash

set -euxo pipefail

make -C certora munged

certoraRun \
    certora/harness/MorphoHarness.sol \
    --verify MorphoHarness:certora/specs/BlueAccrueInterests.spec \
    --solc_allow_path src \
    --msg "Morpho Blue Commutativity of accrueInterests" \
    "$@"
