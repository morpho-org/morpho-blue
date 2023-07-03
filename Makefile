-include .env
.EXPORT_ALL_VARIABLES:
MAKEFLAGS += --no-print-directory

NETWORK ?= ethereum-mainnet


install:
	yarn
	foundryup
	forge install

contracts:
	FOUNDRY_TEST=/dev/null FOUNDRY_SCRIPT=/dev/null forge build --via-ir --extra-output-files irOptimized --sizes --force


test:
	forge test -vvv --via-ir

test-invariant:
	@FOUNDRY_MATCH_CONTRACT=TestInvariant make test


test-%:
	@FOUNDRY_MATCH_TEST=$* make test

test-invariant-%:
	@FOUNDRY_MATCH_TEST=$* make test-invariant


test/%:
	@FOUNDRY_MATCH_CONTRACT=$* make test

test-invariant/%:
	@FOUNDRY_MATCH_CONTRACT=TestInvariant$* make test


.PHONY: contracts test coverage
