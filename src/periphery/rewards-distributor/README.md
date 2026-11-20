# Rewards Distributor

A singleton distributor for new rewards campaigns. Each campaign has one token, an updater, an immutable timelock and isolated funded accounting. There is no owner, withdrawal function or root-update bypass.

Anyone can create and fund campaigns, accept matured roots, and claim on behalf of recipients. Updaters submit or revoke specific roots and can immediately pause a campaign. Several roots may be pending at once; any matured root can be accepted, including an older root after a newer one. Updaters should revoke roots they no longer want. Resubmitting a root restarts only that root's timelock. Claims are cumulative and use the URD double-hashed account/token/amount leaf format.

Pausing sets the active root to zero and records `pausedAt`. Every root submitted at or before that timestamp is invalidated, even if its timelock has already elapsed. Pending timestamps remain stored until explicitly revoked or overwritten. Resuming requires submitting a root in a later block and accepting it after its timelock; submissions in the same block as a pause are also invalidated.

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

The contracts use Solidity 0.8.27 and Morpho Blue's safe transfer library, which checks token code and transfer results. Merkle proofs use sorted pairs and double-hashed leaves, matching URD tooling. Pending roots use a nonzero `validAt` timestamp as their presence indicator; chain timestamps are assumed to be nonzero.
