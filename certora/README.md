This folder contains the verification of the Morpho Blue protocol using CVL, Certora's Verification Language.

## High-Level Description

The Morpho Blue protocol relies on several different concepts, which are described below.
These concepts have been verified using CVL. See the specification files (or those files directly) for more details.

The Morpho Blue protocol allows users to take out collateralized loans on ERC20 tokens.
Token transfers are verified to behave as expected for the most common implementations, in particular the transferred amount is the amount passed as input.\
Markets on Morpho Blue depend on a pair of assets: the borrowable asset that is supplied and borrowed, and the collateral asset.
Markets are independent: loans cannot be impacted by loans from other markets.
Positions of users are also independent: loans cannot be impacted by loans from other users.
The accounting of the markets has been verified (such as the total amounts), as well as the fact that only market with enabled parameters are created.\
When supplying on Morpho Blue, interest is earned over time, and implemented through a share mechanism.
Shares increase in value as interest is accrued.\
To borrow on Morpho Blue, collateral must be deposited.
Collateral tokens remain idle, as well as any borrowable token that has not been borrowed.\
To ensure proper collateralization, a liquidation system is put in place.
It is verified that no unhealthy position can be created in a given block.\
Morpho Blue also defines a sound authorization system: users cannot modify positions of other users without proper authorization (except when liquidating).\
Other safety properties are verified, particularly regarding reentrancy attacks and about input validation and revert conditions.\
Other liveness properties are verified as well, in particular it is always possible to exit a position without concern for the oracle.

## Folder and File Structure

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

## Usage

To verify specification files, run the corresponding script in the [`certora/scripts`](./scripts) folder.
It requires having set the `CERTORAKEY` environment variable to a valid Certora key.
You can pass arguments to the script, which allows you to verify specific properties. For example, at the root of the repository:

```
./certora/scripts/verifyConsistentState.sh --rule borrowLessSupply
```
