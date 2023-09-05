This folder defines the verification of the Morpho Blue protocol using CVL, Certora's specification language.

## High level description

## Folder and files structure

The [`certora/specs`](./specs) folder contains the following files:

- [AccrueInterest.spec](./specs/AccrueInterest.spec), checking that the main functions accrue interest at the start of the interaction. This is done by making sure that accruing interest before calling the function does not change the outcome. View functions do not necessarily respect this property (for example `totalSupplyShares`), and are filtered out.
- [ConsistentState.spec](./specs/ConsistentState.spec), checking that the state (storage) of the Morpho contract is consistent. This includes checking that the accounting of the total amount and shares is correct, that markets are independent from each other, that only enabled IRMs and LLTVs can be used, and that users cannot have their position made worse by an unauthorized account.
- [ExactMath.spec](./specs/ExactMath.spec), checking precise properties when taking into account the exact multiplication and division. Notably, this file specifies that doing using supply and withdraw in the same block cannot yield more funds than at the start.
- [ExitLiquidity.spec](./specs/ExitLiquidity.spec), checking that when exiting a position with witdraw, withdrawCollateral or repay, the user cannot get more than what was owed.
- [Health.spec](./specs/Health.spec), checking properties about the health of the positions. Notably, functions cannot render an account unhealthy, and debt positions at least have some collateral.
- [LibSummary.spec](./specs/LibSummary.spec), checking the summarization of the library functions that are used in other specification files.
- [Liveness.spec](./specs/Liveness.spec), checking that main functions change the owner of funds and the amount of shares as expected, and that it's always possible to exit a position.
- [RatioMath.spec](./specs/RatioMath.spec), checking that the ratio between shares and assets evolves predictably over time.
- [Reentrancy.spec](./specs/Reentrancy.spec), checking that the contract is immune to a particular class of reentrancy issues.
- [Reverts.spec](./specs/Reverts.spec), checking the condition for reverts and that inputs are correctly validated.
- [Transfer.spec](./specs/Transfer.spec), checking the summarization of the safe transfer library functions that are used in other specification files.
