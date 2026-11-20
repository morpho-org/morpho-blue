# Rewards Distributor

A singleton distributor for new rewards campaigns. Each campaign has one token, an updater, an optional sentinel, an immutable timelock and isolated funded accounting. There is no owner, withdrawal function or root-update bypass.

Anyone can create and fund campaigns, accept matured roots, and claim on behalf of recipients. Updaters submit or revoke specific roots and can immediately pause a campaign. Several roots may be pending at once; any matured root can be accepted, including an older root after a newer one. Updaters should revoke roots they no longer want. Resubmitting a root restarts only that root's timelock. Claims are cumulative and use the URD double-hashed account/token/amount leaf format.

The updater can set or clear the campaign's sentinel with `setSentinel`; the sentinel starts at zero and is not part of the campaign parameters or ID. Both the updater and sentinel can revoke pending roots and pause, including in a multicall. The sentinel cannot submit roots or change either role. Setting the sentinel allows no-ops and emits `SetSentinel`.

Pausing only sets the active root to zero. Pending roots are unaffected and can still be accepted once their timelock has elapsed, including immediately after a pause if already matured. The updater or sentinel should revoke any pending roots it does not want accepted. With no pending roots, resuming requires a normal submission and acceptance after the timelock.

Only amounts supplied through `fund` are credited. Direct transfers are unallocated and cannot be recovered. Funding credits the specified amount without measuring token balance changes. Fee-on-transfer and rebasing tokens are not supported.

Campaign IDs are `keccak256(abi.encode(params))`, where `CampaignParams` contains `token`, `timelock`, `initialUpdater` and `salt` in that order. Only the mutable updater, sentinel, balance and root are stored. Creation emits the full parameters; callers supply them to `fund`, `submitRoot` and `claim`. Other campaign operations take the ID. Including the initial updater prevents a front-runner from changing the intended role, while salts allow independent campaigns with the same token and timelock.

A campaign is considered created while its updater is nonzero. Duplicate creation reverts in that state. Setting the updater to zero disables funding and updater-only actions, but allows anyone to recreate the identical parameters and restore the initial updater without clearing balances, roots, pending roots or claims. A zero initial updater leaves a campaign uncreated under this convention.

Zero roots may be submitted and accepted, but do not enable claims. A zero timelock still requires an explicit acceptance. Existing URD proofs can be reused; leaves do not bind campaign IDs, so updaters must choose campaign roots carefully.

This draft is unaudited.

No-ops are allowed: setting the current updater or revoking a non-pending root still emits the corresponding event. A valid claim equal to the amount already claimed transfers zero and emits `Claim`; a lower cumulative amount still reverts. Access control, Merkle proof verification and funding safety checks still apply. Accepting a root always requires a pending submission.
