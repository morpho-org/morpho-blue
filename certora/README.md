This folder contains the verification of the Morpho Blue protocol using CVL, Certora's Verification Language.

The core concepts of the Morpho Blue protocol are described in the [Whitepaper](../morpho-blue-whitepaper.pdf).
These concepts have been verified using CVL.
We first give a [high-level description](#high-level-description) of the verification and then describe the [folder and file structure](#folder-and-file-structure) of the specification files.

# High-level description

The Morpho Blue protocol allows users to take out collateralized loans on ERC20 tokens.

## ERC20 tokens and transfers

For a given market, Morpho Blue relies on the fact that the tokens involved respect the ERC20 standard.
In particular, in case of a transfer, it is assumed that the balance of Morpho Blue increases or decreases (depending if it's the recipient or the sender) of the amount transferred.

The file [Transfer.spec](specs/Transfer.spec) defines a summary of the transfer functions.
This summary is taken as the reference implementation to check that the balance of the Morpho Blue contract changes as expected.

```solidity
function summarySafeTransferFrom(address token, address from, address to, uint256 amount) {
    if (from == currentContract) {
        balance[token] = require_uint256(balance[token] - amount);
    }
    if (to == currentContract) {
        balance[token] = require_uint256(balance[token] + amount);
    }
}
```

where `balance` is the ERC20 balance of the Morpho Blue contract.

The verification is done for the most common implementations of the ERC20 standard, for which we distinguish three different implementations:

- [ERC20Standard](dispatch/ERC20Standard.sol) which respects the standard and reverts in case of insufficient funds or in case of insufficient allowance.
- [ERC20NoRevert](dispatch/ERC20NoRevert.sol) which respects the standard but does not revert (and returns false instead).
- [ERC20USDT](dispatch/ERC20USDT.sol) which does not strictly respect the standard because it omits the return value of the `transfer` and `transferFrom` functions.

Additionally, Morpho Blue always goes through a custom transfer library to handle ERC20 tokens, notably in all the above cases.
This library reverts when the transfer is not successful, and this is checked for the case of insufficient funds or insufficient allowance.
The use of the library can make it difficult for the provers, so the summary is sometimes used in other specification files to ease the verification of rules that rely on the transfer of tokens.

## Markets

The Morpho Blue contract is a singleton contract that defines different markets.
Markets on Morpho Blue depend on a pair of assets, the loan token that is supplied and borrowed, and the collateral token.
Taking out a loan requires to deposit some collateral, which stays idle in the contract.
Additionally, every loan token that is not borrowed also stays idle in the contract.
This is verified by the following property:

```solidity
invariant idleAmountLessThanBalance(address token)
    idleAmount[token] <= balance[token]
```

where `idleAmount` is the sum over all the markets of: the collateral amounts plus the supplied amounts minus the borrowed amounts.
In effect, this means that funds can only leave the contract through borrows and withdrawals.

Additionally, it is checked that on a given market the borrowed amounts cannot exceed the supplied amounts.

```solidity
invariant borrowLessThanSupply(MorphoHarness.Id id)
    totalBorrowAssets(id) <= totalSupplyAssets(id);
```

This property, along with the previous one ensures that other markets can only impact the balance positively.
Said otherwise, markets are independent: tokens from a given market cannot be impacted by operations done in another market.

## Shares

When supplying on Morpho Blue, interest is earned over time, and the distribution is implemented through a shares mechanism.
Shares increase in value as interest is accrued.
The share mechanism is implemented symmetrically for the borrow side: a share of borrow increasing in value over time represents additional owed interest.
The rule `accrueInterestIncreasesSupplyExchangeRate` checks this property for the supply side with the following statement.

```solidity
    // Check that the exchange rate increases: assetsBefore/sharesBefore <= assetsAfter/sharesAfter
    assert assetsBefore * sharesAfter <= assetsAfter * sharesBefore;
```

where `assetsBefore` and `sharesBefore` represents respectively the supplied assets and the supplied shares before accruing the interest. Similarly, `assetsAfter` and `sharesAfter` represent the supplied assets and shares after an interest accrual.

The accounting of the shares mechanism relies on another variable to store the total number of shares, in order to compute what is the relative part of each user.
This variable needs to be kept up to date at each corresponding interaction, and it is checked that this accounting is done properly.
For example, for the supply side, this is done by the following invariant.

```solidity
invariant sumSupplySharesCorrect(MorphoHarness.Id id)
    to_mathint(totalSupplyShares(id)) == sumSupplyShares[id];
```

where `sumSupplyShares` only exists in the specification, and is defined to be automatically updated whenever any of the shares of the users are modified.

## Positions health and liquidations

To ensure proper collateralization, a liquidation system is put in place, where unhealthy positions can be liquidated.
A position is said to be healthy if the ratio of the borrowed value over collateral value is smaller than the liquidation loan-to-value (LLTV) of that market.
This leaves a safety buffer before the position can be insolvent, where the aforementioned ratio is above 1.
To ensure that liquidators have the time to interact with unhealthy positions, it is formally verified that this buffer is respected.
Notably, it is verified that in the absence of accrued interest, which is the case when creating a new position or when interacting multiple times in the same block, a position cannot be made unhealthy.

Let's define bad debt of a position as the amount borrowed when it is backed by no collateral.
Morpho Blue automatically realizes the bad debt when liquidating a position, by transferring it to the lenders.
In effect, this means that there is no bad debt on Morpho Blue, which is verified by the following invariant.

```solidity
invariant alwaysCollateralized(MorphoHarness.Id id, address borrower)
    borrowShares(id, borrower) != 0 => collateral(id, borrower) != 0;
```

More generally, this means that the result of liquidating a position multiple times eventually leads to a healthy position (possibly empty).

## Authorization

Morpho Blue also defines primitive authorization system, where users can authorize an account to fully manage their position.
This allows to rebuild more granular control of the position on top by authorizing an immutable contract with limited capabilities.
The authorization is verified to be sound in the sense that no user can modify the position of another user without proper authorization (except when liquidating).

Let's detail the rule that makes sure that the supply side stays consistent.

```solidity
rule userCannotLoseSupplyShares(env e, method f, calldataarg data)
filtered { f -> !f.isView }
{
    MorphoHarness.Id id;
    address user;

    // Assume that the e.msg.sender is not authorized.
    require !isAuthorized(user, e.msg.sender);
    require user != e.msg.sender;

    mathint sharesBefore = supplyShares(id, user);

    f(e, data);

    mathint sharesAfter = supplyShares(id, user);

    assert sharesAfter >= sharesBefore;
}
```

In the previous rule, an arbitrary function of Morpho Blue `f` is called with arbitrary `data`.
Shares of `user` on the market identified by `id` are recorded before and after this call.
In this way, it is checked that the supply shares are increasing when the caller of the function is neither the owner of those shares (`user != e.msg.sender`) nor authorized (`!isAuthorized(user, e.msg.sender)`).

## Other safety properties

### Enabled LLTV and IRM

Creating a market is permissionless on Morpho Blue, but some parameters should fall into the range of admitted values.
Notably, the LLTV value should be enabled beforehand.
The following rule checks that no market can ever exist with a LLTV that had not been previously approved.

```solidity
invariant onlyEnabledLltv(MorphoHarness.MarketParams marketParams)
    isCreated(libId(marketParams)) => isLltvEnabled(marketParams.lltv);
```

Similarly, the interest rate model (IRM) used for the market must have been previously whitelisted.

### Range of the fee

The governance can choose to set a fee to a given market.
Fees are guaranteed to never exceed 25% of the interest accrued, and this is verified by the following rule.

```solidity
invariant feeInRange(MorphoHarness.Id id)
    fee(id) <= maxFee();
```

### Sanity checks and input validation

The formal verification is also taking care of other sanity checks, some of which are needed properties to verify other rules.
For example, the following rule checks that the variable storing the last update time is no more than the current time.
This is a sanity check, but it is also useful to ensure that there will be no underflow when computing the time elapsed since the last update.

```solidity
rule noTimeTravel(method f, env e, calldataarg args)
filtered { f -> !f.isView }
{
    MorphoHarness.Id id;
    // Assume the property before the interaction.
    require lastUpdate(id) <= e.block.timestamp;
    f(e, args);
    assert lastUpdate(id) <= e.block.timestamp;
}
```

Additional rules are verified to ensure that the sanitization of inputs is done correctly.

```solidity
rule supplyInputValidation(env e, MorphoHarness.MarketParams marketParams, uint256 assets, uint256 shares, address onBehalf, bytes data) {
    supply@withrevert(e, marketParams, assets, shares, onBehalf, data);
    assert !exactlyOneZero(assets, shares) || onBehalf == 0 => lastReverted;
}
```

The previous rule checks that the `supply` function reverts whenever the `onBehalf` parameter is the address zero, or when either both `assets` and `shares` are zero or both are non-zero.

## Liveness properties

On top of verifying that the protocol is secured, the verification also proves that it is usable.
Such properties are called liveness properties, and it is notably checked that the accounting is done when an interaction goes through.
As an example, the `withdrawChangesTokensAndShares` rule checks that calling the `withdraw` function successfully will decrease the shares of the concerned account and increase the balance of the receiver.

Other liveness properties are verified as well.
Notably, it's also verified that it is always possible to exit a position without concern for the oracle.
This is done through the verification of two rules: the `canRepayAll` rule and the `canWithdrawCollateralAll` rule.
The `canRepayAll` rule ensures that it is always possible to repay the full debt of a position, leaving the account without any outstanding debt.
The `canWithdrawCollateralAll` rule ensures that in the case where the account has no outstanding debt, then it is possible to withdraw the full collateral.

## Protection against common attack vectors

Other common and known attack vectors are verified to not be possible on the Morpho Blue protocol.

### Reentrancy

Reentrancy is a common attack vector that happens when a call to a contract allows, when in a temporary state, to call the same contract again.
The state of the contract usually refers to the storage variables, which can typically hold values that are meant to be used only after the full execution of the current function.
The Morpho Blue contract is verified to not be vulnerable to this kind of reentrancy attack thanks to the rule `reentrancySafe`.

### Extraction of value

The Morpho Blue protocol uses a conservative approach to handle arithmetic operations.
Rounding is done such that potential (small) errors are in favor of the protocol, which ensures that it is not possible to extract value from other users.

The rule `supplyWithdraw` handles the simple scenario of a supply followed by a withdraw, and has the following check.

```solidity
assert withdrawnAssets <= suppliedAssets;
```

The rule `withdrawAssetsAccounting` is more general and defines `ownedAssets` as the assets that the user owns, rounding in favor of the protocol.
This rule has the following check to ensure that no more than the owned assets can be withdrawn.

```solidity
assert withdrawnAssets <= ownedAssets;
```

# Folder and file structure

The [`certora/specs`](specs) folder contains the following files:

- [`AccrueInterest.spec`](specs/AccrueInterest.spec) checks that the main functions accrue interest at the start of the interaction.
  This is done by ensuring that accruing interest before calling the function does not change the outcome compared to just calling the function.
  View functions do not necessarily respect this property (for example, `totalSupplyShares`), and are filtered out.
- [`AssetsAccounting.spec`](specs/AssetsAccounting.spec) checks that when exiting a position the user cannot get more than what was owed.
  Similarly, when entering a position, the assets owned as a result are no greater than what was given.
- [`ConsistentState.spec`](specs/ConsistentState.spec) checks that the state (storage) of the Morpho contract is consistent.
  This includes checking that the accounting of the total amount and shares is correct, that markets are independent from each other, that only enabled IRMs and LLTVs can be used, and that users cannot have their position made worse by an unauthorized account.
- [`ExactMath.spec`](specs/ExactMath.spec) checks precise properties when taking into account exact multiplication and division.
  Notably, this file specifies that using supply and withdraw in the same block cannot yield more funds than at the start.
- [`Health.spec`](specs/Health.spec) checks properties about the health of the positions.
  Notably, debt positions always have some collateral thanks to the bad debt realization mechanism.
- [`LibSummary.spec`](specs/LibSummary.spec) checks the summarization of the library functions that are used in other specification files.
- [`Liveness.spec`](specs/Liveness.spec) checks that main functions change the owner of funds and the amount of shares as expected, and that it's always possible to exit a position.
- [`ExchangeRate.spec`](specs/ExchangeRate.spec) checks that the exchange rate between shares and assets evolves predictably over time.
- [`Reentrancy.spec`](specs/Reentrancy.spec) checks that the contract is immune to a particular class of reentrancy issues.
- [`Reverts.spec`](specs/Reverts.spec) checks the condition for reverts and that inputs are correctly validated.
- [`StayHealthy.spec`](specs/Health.spec) checks that functions cannot render an account unhealthy.
- [`Transfer.spec`](specs/Transfer.spec) checks the summarization of the safe transfer library functions that are used in other specification files.

The [`certora/confs`](confs) folder contains a configuration file for each corresponding specification file.

The [`certora/harness`](harness) folder contains contracts that enable the verification of Morpho Blue.
Notably, this allows handling the fact that library functions should be called from a contract to be verified independently, and it allows defining needed getters.

The [`certora/dispatch`](dispatch) folder contains different contracts similar to the ones that are expected to be called from Morpho Blue.

# Getting started

Install `certora-cli` package with `pip install certora-cli`.
To verify specification files, pass to `certoraRun` the corresponding configuration file in the [`certora/confs`](confs) folder.
It requires having set the `CERTORAKEY` environment variable to a valid Certora key.
You can also pass additional arguments, notably to verify a specific rule.
For example, at the root of the repository:

```
certoraRun certora/confs/ConsistentState.conf --rule borrowLessThanSupply
```

The `certora-cli` package also includes a `certoraMutate` binary.
The file [`gambit.conf`](gambit.conf) provides a default configuration of the mutations.
You can test to mutate the code and check it against a particular specification.
For example, at the root of the repository:

```
certoraMutate --prover_conf certora/confs/ConsistentState.conf --mutation_conf certora/gambit.conf
```
