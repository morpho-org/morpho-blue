#!/bin/bash

set -euxo pipefail

certoraRun \
    certora/harness/TransferHarness.sol \
    certora/dispatch/ERC20Standard.sol \
    certora/dispatch/ERC20USDT.sol \
    certora/dispatch/ERC20NoRevert.sol \
    --verify TransferHarness:certora/specs/Transfer.spec \
    --msg "Morpho Blue Transfer" \
    "$@"