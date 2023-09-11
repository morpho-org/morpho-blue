#!/bin/bash

set -euxo pipefail

make -C certora munged

certoraRun \
    certora/harness/MorphoHarness.sol \
    --verify MorphoHarness:certora/specs/ExitLiquidity.spec \
    --msg "Morpho Blue Exit Liquidity" \
    "$@"
