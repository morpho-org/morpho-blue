#!/bin/bash

set -euxo pipefail

make -C certora munged

certoraRun \
    certora/harness/MorphoHarness.sol \
    --verify MorphoHarness:certora/specs/ExitLiquidity.spec \
    --solc_allow_path src \
    --msg "Morpho Blue Exit Liquidity" \
    "$@"
