This folder defines the verification of the Morpho Blue protocol using CVL, Certora's verification language.

## High level description

The Morpho Blue protocol relies on a few different concepts that are described below. Those concepts have been verified using CVL, see the description of the specification files (or those files directly) for more details.

The Morpho Blue protocol allows to take collateralized loans on ERC20 tokens. Transfers of tokens are verified to behave as expected, notably for the most common implementations.\
Supplying on Morpho Blue entails to some interest, and this is implemented using the share mechanism. Notably, shares can increase in value when accruing interest. What is not borrowed stays on the contract.\
Borrowing on Morpho Blue requires to deposit collateral. This collateral stays idle, and participates to the liquidity of the contract.\
Markets on Morpho Blue depend on a pair of assets: the borrowable asset that is supplied and borrowed, and the collateral asset that is needed to be able to take a borrow position. Markets are sound, independent, and positions of users are also independent. In particular, loans cannot be impacted by loans from other markets.\
To ensure proper collateralization, a liquidation system is put in place. It is verified that no unhealthy position can be created in a given block.\
Morpho Blue also defines an authorization system that is sound: a user cannot modify the position of another user without the proper authorization (except when liquidating).\
Other safety properties are verified, notably about reentrancy attacks and about input validation and revert conditions.\
Other liveness properties are verified, notably it is always possible to exit a position, without concern for the external contracts such as the oracle.

## Folder and files structure

The [`certora/specs`](./specs) folder contains the following files:

- [`AccrueInterest.spec`](./specs/AccrueInterest.spec), checking that the main functions accrue interest at the start of the interaction. This is done by making sure that accruing interest before calling the function does not change the outcome. View functions do not necessarily respect this property (for example `totalSupplyShares`), and are filtered out.
- [`ConsistentState.spec`](./specs/ConsistentState.spec), checking that the state (storage) of the Morpho contract is consistent. This includes checking that the accounting of the total amount and shares is correct, that markets are independent from each other, that only enabled IRMs and LLTVs can be used, and that users cannot have their position made worse by an unauthorized account.
- [`ExactMath.spec`](./specs/ExactMath.spec), checking precise properties when taking into account the exact multiplication and division. Notably, this file specifies that doing using supply and withdraw in the same block cannot yield more funds than at the start.
- [`ExitLiquidity.spec`](./specs/ExitLiquidity.spec), checking that when exiting a position with witdraw, withdrawCollateral or repay, the user cannot get more than what was owed.
- [`Health.spec`](./specs/Health.spec), checking properties about the health of the positions. Notably, functions cannot render an account unhealthy, and debt positions at least have some collateral.
- [`LibSummary.spec`](./specs/LibSummary.spec), checking the summarization of the library functions that are used in other specification files.
- [`Liveness.spec`](./specs/Liveness.spec), checking that main functions change the owner of funds and the amount of shares as expected, and that it's always possible to exit a position.
- [`RatioMath.spec`](./specs/RatioMath.spec), checking that the ratio between shares and assets evolves predictably over time.
- [`Reentrancy.spec`](./specs/Reentrancy.spec), checking that the contract is immune to a particular class of reentrancy issues.
- [`Reverts.spec`](./specs/Reverts.spec), checking the condition for reverts and that inputs are correctly validated.
- [`Transfer.spec`](./specs/Transfer.spec), checking the summarization of the safe transfer library functions that are used in other specification files.

The [`certora/scripts`](./scripts/) folder contains a script for each corresponding specification file.

The [`certora/harness`](./harness/) folder contains contracts that enable the verification of Morpho Blue. Notably, this allows to handle the fact that library functions should be called from a contract to be verified independently, and it allows to define needed getters.

The [`certora/dispatch`](./dispatch/) folder contains different contracts similar to contracts that are expected to be called from Morpho Blue.

## Usage

Verify specification files by running the corresponding script in the [`certora/scripts`](./scripts/) folder. You can pass arguments to the script, which notable allows you to verify specific properties. For example, at the root of the repository:

```
./certora/scripts/verifyConsistentState.sh --rule borrowLessSupply
```
