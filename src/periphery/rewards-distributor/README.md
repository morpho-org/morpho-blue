# Rewards Distributor

A singleton distributor for new rewards campaigns. Each campaign has one token, an updater, an immutable timelock and isolated funded accounting. There is no owner, withdrawal function or root-update bypass.

Anyone can create and fund campaigns, accept matured roots, and claim on behalf of recipients. Updaters submit or revoke specific roots and can immediately pause a campaign. Several roots may be pending at once; any matured root can be accepted, including an older root after a newer one. Updaters should revoke roots they no longer want. Resubmitting a root restarts only that root's timelock. Claims are cumulative and use the URD double-hashed account/token/amount leaf format.

Pausing only sets the active root to zero. Pending roots are unaffected and can still be accepted once their timelock has elapsed, including immediately after a pause if already matured. The updater should revoke any pending roots it does not want accepted. With no pending roots, resuming requires a normal submission and acceptance after the timelock.

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
