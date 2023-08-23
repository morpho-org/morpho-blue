#!/bin/bash

set -euxo pipefail

certoraRun \
    certora/harness/MorphoHarness.sol \
    --verify MorphoHarness:certora/specs/BlueExitLiquidity.spec \
    --solc_allow_path src \
    --msg "Morpho Blue Commutativity of accrueInterests" \
    "$@"
