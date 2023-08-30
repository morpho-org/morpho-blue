#!/bin/bash

set -euxo pipefail

make -C certora munged

certoraRun \
    certora/harness/TransferHarness.sol \
    certora/dispatch/ERC20Standard.sol \
    certora/dispatch/ERC20USDT.sol \
    certora/dispatch/ERC20NoRevert.sol \
    --verify TransferHarness:certora/specs/BlueTransfer.spec \
    --packages openzeppelin-contracts=lib/openzeppelin-contracts/contracts \
    --loop_iter 3 \
    --optimistic_loop \
    --msg "Morpho Transfer Summary" \
    "$@"
