# Certora verification

This folder defines the verification of the Morpho Blue protocol using CVL, Certora's specification language.

## High level description



## Folder and files structure

The [`certora/specs`](./specs) folder contains the following files:
- [AccrueInterest.spec](./specs/AccrueInterest.spec), checking that the main functions accrue interest at the start of the interaction. This is done by making sure that accruing interest before calling the function does not change the outcome. View functions do not necessarily respect this property (for example `totalSupplyShares`), and are filtered out.
- [ConsistentState.spec](./specs/ConsistentState.spec), checking that the state (storage) of the Morpho contract is consistent. This includes checking that the accounting of the total amount and shares is correct, that markets are independent from each other, that only enabled IRMs and LLTVs can be used, and that users cannot have their position made worse by an unauthorized account.
- [ExactMath.spec](./specs/ExactMath.spec), checking properties about
