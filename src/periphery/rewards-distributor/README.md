# Rewards Distributor

A singleton distributor for new rewards campaigns. Each campaign has one token, an updater, an immutable timelock and isolated funded accounting. There is no owner, withdrawal function or root-update bypass.

Anyone can create and fund campaigns, accept matured roots, and claim on behalf of recipients. Updaters submit or revoke roots and can immediately pause a campaign; resuming always requires submission and acceptance through its timelock. Claims are cumulative and use the URD double-hashed account/token/amount leaf format.

Only amounts supplied through `fund` are credited. Direct transfers are unallocated and cannot be recovered. Funding credits the specified amount without measuring token balance changes. Fee-on-transfer and rebasing tokens are not supported.

Campaign IDs start at 1. Zero roots may be submitted and accepted, but do not enable claims. A zero timelock still requires an explicit acceptance. Existing URD proofs can be reused; leaves do not bind campaign IDs, so updaters must choose campaign roots carefully.

This draft is unaudited.

## Development

From the repository root, run:

```sh
forge fmt --check
forge build --locked
forge test --match-path 'test/periphery/rewards-distributor/*'
```

The contracts use Solidity 0.8.27 and the repository's pinned Solmate dependency. Merkle proofs use sorted pairs and double-hashed leaves, matching URD tooling. Pending roots use a nonzero `validAt` timestamp as their presence indicator; chain timestamps are assumed to be nonzero.
