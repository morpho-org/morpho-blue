#!/bin/bash

set -euxo pipefail

certoraRun \
    certora/harness/MorphoInternalAccess.sol \
    --verify MorphoInternalAccess:certora/specs/Liveness.spec \
    --msg "Morpho Blue Liveness" \
    "$@"
