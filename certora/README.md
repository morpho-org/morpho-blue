This folder contains the verification of the Morpho Blue protocol using CVL, Certora's Verification Language.

The core concepts of the the Morpho Blue protocol are described in the [Whitepaper](../morpho-blue-whitepaper.pdf).
These concepts have been verified using CVL.
We first give a [high-level description](#high-level-description) of the verification and then describe the [folder and file structure](#folder-and-file-structure) of the specification files.

# High-level description

The Morpho Blue protocol allows users to take out collateralized loans on ERC20 tokens.

## ERC20 tokens and transfers

For a given market, Morpho Blue relies on the fact that the tokens involved respect the ERC20 standard.
In particular, in case of a transfer, it is assumed that the balance of Morpho Blue increases or decreases (depending if its the recipient or the sender) of the amount transferred.

The file [Transfer.spec](./specs/Transfer.spec) defines a summary of the transfer functions.
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

- [ERC20Standard](./dispatch/ERC20Standard.sol) which respects the standard and reverts in case of insufficient funds or in case of insufficient allowance.
- [ERC20NoRevert](./dispatch/ERC20NoRevert.sol) which respects the standard but does not revert (and returns false instead).
- [ERC20USDT](./dispatch/ERC20USDT.sol) which does not strictly respects the standard because it omits the return value of the `transfer` and `transferFrom` functions.

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
The share mechanism is implemented symetrically for the borrow side: a share of borrow increasing in value over time represents additional owed interest.
The rule `accrueInterestIncreasesSupplyRatio` checks this property for the supply side with the following statement.

```soldidity
    // Check that the ratio increases: assetsBefore/sharesBefore <= assetsAfter/sharesAfter.
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

## Health

To ensure proper collateralization, a liquidation system is put in place, where unhealthy positions can be liquidated.
A position is said to be healthy if the ratio of the borrowed value over collateral value is smaller than the LLTV of that market.
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

More generally, this means that the result of liquidating a position multiple times eventually lead to a healthy position (possibly empty).

## Safety

### Authorization

Morpho Blue also defines a sound authorization system where users cannot modify positions of other users without proper authorization (except when liquidating).

Positions of users are also independent, so loans cannot be impacted by loans from other users.

### Others

Other safety properties are verified, particularly regarding reentrancy attacks and about input validation and revert conditions.

as well as the fact that only market with enabled parameters are created

## Liveness

Other liveness properties are verified as well, in particular it is always possible to exit a position without concern for the oracle.

# Folder and file structure

The [`certora/specs`](./specs) folder contains the following files:

- [`AccrueInterest.spec`](./specs/AccrueInterest.spec) checks that the main functions accrue interest at the start of the interaction.
  This is done by ensuring that accruing interest before calling the function does not change the outcome compared to just calling the function.
  View functions do not necessarily respect this property (for example, `totalSupplyShares`), and are filtered out.
- [`ConsistentState.spec`](./specs/ConsistentState.spec) checks that the state (storage) of the Morpho contract is consistent.
  This includes checking that the accounting of the total amount and shares is correct, that markets are independent from each other, that only enabled IRMs and LLTVs can be used, and that users cannot have their position made worse by an unauthorized account.
- [`ExactMath.spec`](./specs/ExactMath.spec) checks precise properties when taking into account exact multiplication and division.
  Notably, this file specifies that using supply and withdraw in the same block cannot yield more funds than at the start.
- [`ExitLiquidity.spec`](./specs/ExitLiquidity.spec) checks that when exiting a position with withdraw, withdrawCollateral, or repay, the user cannot get more than what was owed.
- [`Health.spec`](./specs/Health.spec) checks properties about the health of the positions.
  Notably, functions cannot render an account unhealthy, and debt positions always have some collateral (thanks to the bad debt realization mechanism).
- [`LibSummary.spec`](./specs/LibSummary.spec) checks the summarization of the library functions that are used in other specification files.
- [`Liveness.spec`](./specs/Liveness.spec) checks that main functions change the owner of funds and the amount of shares as expected, and that it's always possible to exit a position.
- [`RatioMath.spec`](./specs/RatioMath.spec) checks that the ratio between shares and assets evolves predictably over time.
- [`Reentrancy.spec`](./specs/Reentrancy.spec) checks that the contract is immune to a particular class of reentrancy issues.
- [`Reverts.spec`](./specs/Reverts.spec) checks the condition for reverts and that inputs are correctly validated.
- [`Transfer.spec`](./specs/Transfer.spec) checks the summarization of the safe transfer library functions that are used in other specification files.

The [`certora/scripts`](./scripts) folder contains a script for each corresponding specification file.

The [`certora/harness`](./harness) folder contains contracts that enable the verification of Morpho Blue.
Notably, this allows handling the fact that library functions should be called from a contract to be verified independently, and it allows defining needed getters.

The [`certora/dispatch`](./dispatch) folder contains different contracts similar to the ones that are expected to be called from Morpho Blue.

# Getting started

To verify specification files, run the corresponding script in the [`certora/scripts`](./scripts) folder.
It requires having set the `CERTORAKEY` environment variable to a valid Certora key.
You can pass arguments to the script, which allows you to verify specific properties. For example, at the root of the repository:

```
./certora/scripts/verifyConsistentState.sh --rule borrowLessSupply
```
