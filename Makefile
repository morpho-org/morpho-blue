-include .env
.EXPORT_ALL_VARIABLES:
MAKEFLAGS += --no-print-directory


install:
	foundryup
	forge install

contracts:
	FOUNDRY_TEST=/dev/null FOUNDRY_SCRIPT=/dev/null forge build --extra-output-files irOptimized --sizes --force


test-invariant:
	@FOUNDRY_MATCH_CONTRACT=InvariantTest make test

test:
	FOUNDRY_VIA_IR=false forge test -vvv


test-%:
	@FOUNDRY_MATCH_TEST=$* make test


test/%:
	@FOUNDRY_MATCH_CONTRACT=$* make test


.PHONY: contracts test
