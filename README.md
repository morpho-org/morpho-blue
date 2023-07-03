# Implementation design

## Singleton

- Unlocks gas savings when interacting with multiple markets in a single tx (MetaMorpho vaults have usecases for it)
- Enables flashloans right from the contract holding liquidity

## Flash Loans

I opted to enable flash loans following a modification of ERC3156: `ERC3156FlashBorrower.onFlashLoan` now returns bytes data which is passed as return data of `ERC3156FlashLender.flashLoan`, so that flash borrowers don't have to use storage to keep data.

Contango also suggested to have some way of defining which function the flash lender should call back from the flash borrower, but it opens up a vulnerability: anyone could be able to make the flash lender call any function from any contract, including `ERC20.transfer`. So there must be some way of whitelisting these: either use `msg.sender` as the flash borrower or require flash borrowers to permissionlessly register themselves upfront.

I find both solutions unappealing, because I don't think having the possibility to pass the callback as argument to `ERC3156FlashLender.flashLoan` has a lot of benefits: it would save a little gas compared to having a function dispatcher inside `ERC3156FlashBorrower.onFlashLoan`. If we anyway want this feature, I'd go for the permissionless upfront flash borrower registration.

## Oracles

A market is configured to have a single oracle, because I believe it is equivalent to having 2 oracles quoting debt & collateral in the same currency, modulo an oracle wrapper responsible for disabling borrows & collateral withdrawals based on whether the price feeds are considered valid or not.

I don't believe oracle wrappers is an overhead considering there's not yet a standard for oracles and that Blue is intended to be a primitive layer.

I provided examples of oracle wrappers in the [extensions](src/extensions/) directory.

I also believe there's no usecase for pausing liquidation but not collateral withdrawals, so I didn't add a specific flag for liquidations.

## Interest rates

Only the borrow rate of a given tranche is controlled by the interest rates model. The supply rate of a tranche is calculated as the borrow rate, times the utilization of the tranche (if it's fully utilized, all interests accrued from borrowers go to lenders). No reserve fee is taken as of now.

The [IRateModel](src/interfaces/IRateModel.sol) interface describes how an interest rate model is being queried: a single function `dBorrowRate` is responsible for controlling the derivative of the borrow rate with respect to time. This enables the free market to reach its equilibrium at all times, without being capped by a standard rate curve (as seen on Compound or Aave).

The derivative of the rate wrt time must be defined in RAY units, because it is expected to have at least 15 decimals. For precision, it implies rates must be defined in RAY units too.

## Liquidations

I added the possibility to opt in for flash liquidations (which I believe will be the standard way of liquidating borrowers): collateral is transferred first, and debt must be repaid right after a liquidation hook.

However, because the liquidation process is heavy and we don't want to read twice from storage, we need liquidators to optimistically provide correct values for debt repaid and collateral seized, execute the flash liquidation and check that the liquidator didn't ask for too much collateral in exchange for the debt actually repaid. If they ask for too much, just revert (like in Uniswap).

The liquidation process is thus very similar to a Uniswap swap, at a discount price compared to market.

## Account Management

I don't believe this feature is critical to Morpho Blue, but I also find @makcandrov idea of replacing `address` by `bytes32` very cost-effective, gas-wise as well as development-wise, which makes me re-consider it as a very low trade-off. As always, I lean more towards "why not provide a near zero-cost additional feature?" rather than "only provide features for which we figured out usecases!".

Steps to convert this PoC to this account management are described in [Types](src/libraries/Types.sol), near the `Market` struct.

# Software design

## Constants, types, errors & events

[Constants](./src/libraries/Constants.sol), [types](./src/libraries/Types.sol) & [errors](./src/libraries/Errors.sol) are all stored in the global context. I only did so for purity.

Unfortunately, [events](./src/libraries/Events.sol) need to be at least defined in a library.

## Error parameters

I added parameters to errors so it's easier to debug the code's behavior. I did so as often as I judged a parameter as giving additional context on the reason the error was thrown.

The most illustrative example is:

```solidity
error UnhealthyHealthFactor(uint256 healthFactor);
```

If this error is thrown without parameters, the only thing known is that the health factor is below the unit threshold.
Thanks to the `healthFactor` parameter, we exactly know the health factor's value.

It is handy to debug the contract's behavior, so it'll be handy for us during testing as well as for any integrator.

## `private` vs `internal`

Because the contract is not designed to be ugpradeable, security practices no longer require the storage to be isolated into a single layer of code. This in turn enables a more secure software pattern: layers of code each having their very-own [single responsibility](https://en.wikipedia.org/wiki/Single-responsibility_principle) and enforcing a defined way of accessing and updating storage variables.

I decided to split it this way:

- `MarketBase`: responsible for the storage of markets
- `AllowanceBase`: responsible for the storage of allowances
- and other EIP-related conventions each isolated

The most illustrative concept is the choice to go for `private` storage variables over `internal`: it forces developers to use `internal` or `public`-defined getters & setters to access and modify storage. This unlocks the ability for the software to protect the developer from making mistakes such as:

- forget to emit events (e.g. when updating allowance)
- forget to perform checks when accessing a value (e.g. is the IRM whitelisted?)
- writes an incorrect value (e.g. incorrect bitmask operation)

## Library-oriented programming (LOP?)

Isolating read & write logic into getters & setters enables higher development quality and security for the reasons mentioned in the point above. So I also isolated layers of code into separate libraries, each one having a single responsibility: handling safe accesses modifications of the underlying storage.

- [MarketLib](src/libraries/MarketLib.sol): responsible for the `Market` struct
- [TrancheLib](src/libraries/TrancheLib.sol): responsible for the `Tranche` struct
- [PositionLib](src/libraries/PositionLib.sol): responsible for the `Position` struct
- [MarketKeyLib](src/libraries/MarketKeyLib.sol): responsible for the `MarketKey` struct
- [TrancheIdLib](src/libraries/TrancheIdLib.sol): responsible for the `TrancheId` struct

This approach as limits with regard to some gas optimizations: following this good practice, we'd want to include the `isBorrowing` getter into the `PositionLib`, but it'd require reading `Position.tranchesMask` multiple times from storage in each loop.

Note that the same could be achieved with internal contract getters. I only chose library because I believe it is the most intuitive and appropriate way to approximate Object-oriented programming in Solidity.

## Name shadowing

Prepending storage variables with `_` is not enough to prevent name shadowing, because you can have clashes between a local variable and a getter (e.g. `market`), especially in libraries.

So I opted for the convention of prepending getters with `get` or `is` and setters with `set` (just like in OOP) in libraries. It solves all name shadowing.

## Getters

I wanted to only expose the necessary getters from the contract. I went for `sharesOf` and `trancheAt` which, together, enables any integrator (including us during testing) to access updated values of a tranche and thus deduct updated health factor, liquidity, rates (via utilization), balances.

## ERC4626-like naming

I replaced all `amount` naming for the ERC4626 naming because I actually think it's more specific:

- `amount` can represent an amount of shares as well as an amount of assets. Conversely, `assets` makes it clear we are talking about assets and `shares` that we're talking about shares.

On the same note: I had the idea to conform to most of ERC4626 codestyle, including redeeming shares instead of withdrawing assets (for more precise inputs). It requires some refactoring.

# Next steps

There are numerous TODOs placed in the code on topics where I suggest altenative implementations that I believe are worth discussing. Search for TODOs in the code.

# Gas cost

Here is the gas cost associated to each function, simulated in [Morpho.spec](test/hardhat/Morpho.spec.ts), where 50 suppliers each deposit to the N tranches with lowest liquidation LTV, while 50 borrowers borrow up to the liquidation LTV from the same tranches. On the left, N = 1, on the right, N = 16. The total number of tranches is 64. It is particularly interesting to note that the gas cost of liquidating a borrower or calculating the health factor of a borrower borrowing from multiple tranches grows high (seen in max gas cost of `borrow`, `withdrawCollateral`, `liquidate`). In this simulation, liquidations always left 100% bad debt (worst-case scenario). Each simulation is available in details under [test/hardhat/simulations](test/hardhat/simulations/).
