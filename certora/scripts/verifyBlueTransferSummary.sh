#!/bin/bash

set -euxo pipefail

certoraRun \
    certora/harness/TransferHarness.sol \
    certora/dispatch/ERC20Good.sol \
    certora/dispatch/ERC20USDT.sol \
    --verify TransferHarness:certora/specs/BlueTransferSummary.spec \
    --packages openzeppelin-contracts=lib/openzeppelin-contracts/contracts \
    --loop_iter 3 \
    --optimistic_loop \
    --msg "Morpho Transfer Summary" \
    "$@"
