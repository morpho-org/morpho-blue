# Morpho Blue Extensions — Changelog

## Refactor & Security Hardening (Post-Audit v1)

**Date:** February 16, 2026
**Scope:** TieredLiquidationMorpho, WhitelistRegistry, HealthFactorLib, PriceOracleLib
**LOC:** 1,478 → 651 (−56%)

---

### Files Removed

- **`libraries/PriceOracleLib.sol`** (158 lines deleted) — Entire library was dead code; no function was referenced by any in-scope contract.

---

### HealthFactorLib.sol (163 → 41 lines, −75%)

**Removed:**

- `isHealthy()` — redundant wrapper around `calculateHealthFactor() >= WAD`
- `calculateMaxBorrow()` — unused, not called by any contract
- `calculateMinCollateral()` — unused, not called by any contract
- `isLiquidatable()` — duplicate inverse of `isHealthy()`
- `getCollateralValue()` — trivial one-liner, inlined at call sites

**Retained (unchanged):**

- `calculateHealthFactor()` — core health check used by both liquidation paths
- `calculateLiquidationLimits()` — max-seizable / max-repayable computation

---

### WhitelistRegistry.sol (338 → 145 lines, −57%)

**Removed:**

- Deposit / withdraw / slash staking mechanics (`deposit()`, `withdraw()`, `slashLiquidator()`, `stakeAmount` mapping, `minStake` config) — staking was out of scope for the current design; ETH deposits live in TieredLiquidationMorpho instead.
- Timelocked admin transfer (`proposeMarketAdmin()`, `acceptMarketAdmin()`, `pendingMarketAdmin` mapping, `ADMIN_TRANSFER_DELAY`) — simplified to single-step `transferMarketAdmin()`.
- Batch operations (`addLiquidatorsBatch()`) — removed to cut surface area; single-add is sufficient.
- Detailed view helpers (`getLiquidatorDetails()`, `getMarketInfo()`) — replaced by existing simpler getters.

**Security fixes applied:**

- **V-01 (Critical):** `recordLiquidation()` now restricted to `authorizedCaller` (was previously callable by anyone, allowing fake liquidation counts).
- **V-02 (High):** `initializeMarket()` restricted to `onlyOwner` (was previously open, allowing front-running of market admin assignment).

**Other changes:**

- Constructor now validates `_owner != address(0)`.
- `removeLiquidator()` prevents removing the last liquidator when whitelist mode is active (`MinLiquidatorsRequired` guard).

---

### TieredLiquidationMorpho.sol (819 → 465 lines, −43%)

**Extracted shared helpers (deduplication):**

- `_loadAndValidatePosition()` — consolidates market data fetch, borrow conversion, health factor check, and cooldown enforcement. Previously duplicated across `liquidate()`, `requestLiquidation()`, and `executeLiquidation()`.
- `_enforceNoActiveLock()` — checks for and auto-cancels expired two-step locks. Previously duplicated in `liquidate()` and `requestLiquidation()`.
- `_executeMorphoLiquidation()` — wraps the loan-token pull, Morpho approval, `MORPHO.liquidate()` call, and excess refund. Previously duplicated in `liquidate()` and `executeLiquidation()`.
- `_deductProtocolFee()` — computes and accumulates protocol fee from seized collateral. Previously inline in two places.

**Security fixes applied:**

- **V-03 (High):** `_deductProtocolFee()` now uses checked arithmetic with `require(feeAmount <= seizedAssets)` to prevent underflow when the bonus-based fee exceeds seized assets.
- **V-05 (High):** `withdrawProtocolFees()` now validates `marketParams.id() == marketId` to prevent parameter spoofing that could drain fees via a mismatched collateral token.
- **V-07 (Medium):** `executeLiquidation()` re-checks `WHITELIST_REGISTRY.canLiquidate()` at execution time, not just at request time. Prevents removed liquidators from completing locked requests.
- **V-08 / V-13 (Low/Info):** Added comprehensive events for all state-changing operations: `LiquidationExecuted`, `LiquidationRequested`, `LiquidationCompleted`, `LiquidationRequestCancelled`, `MarketConfigured`, `OwnershipTransferred`, `FeeRecipientSet`, `RefundFailed`, `RefundClaimed`.

**Other changes:**

- `configureMarket()` now enforces: `liquidationBonus ≤ 20%`, `maxLiquidationRatio ≤ 100%`, `protocolFee ≤ 100%`, at least one liquidation mode enabled, and `lockDuration > 0` when two-step is enabled.
- `_safeTransferETH()` records failed refunds to `failedRefunds` mapping with a `claimFailedRefund()` pull pattern (replacing silent ETH loss).
- `receive() external payable` added for ETH handling.

---

### Summary of Audit Fixes Incorporated

| ID | Severity | Description | Status |
|----|----------|-------------|--------|
| V-01 | Critical | `recordLiquidation` open to anyone | **Fixed** — restricted to `authorizedCaller` |
| V-02 | High | `initializeMarket` open to anyone | **Fixed** — restricted to `onlyOwner` |
| V-03 | High | Unchecked fee subtraction underflow | **Fixed** — added `require(feeAmount <= seizedAssets)` |
| V-05 | High | `withdrawProtocolFees` param spoofing | **Fixed** — `marketParams.id()` validated against `marketId` |
| V-07 | Medium | Whitelist not re-checked at execution | **Fixed** — `canLiquidate()` called in `executeLiquidation()` |
| V-08 | Low | Missing events on state changes | **Fixed** — full event coverage added |
| V-13 | Info | No event on liquidation execution | **Fixed** — `LiquidationExecuted` event added |
| V-04 | High | Retroactive `lockDuration` traps ETH | Not fixed (architectural) |
| V-06 | Medium | Infinite ERC20 approval to Morpho | Not fixed (design trade-off) |

---

### Remaining Known Issues (from Post-Refactor Audit v2)

These were identified in the second audit pass and are documented in the full v2 report:

- **SF-01 (High):** Retroactive `lockDuration` change can trap ETH deposits past original expiry.
- **SF-02 (High):** Morpho callback `data` parameter silently broken (contract doesn't implement `IMorphoLiquidateCallback`).
- **AC-01 (High):** `canLiquidate()` returns `true` for all addresses on un-initialized markets (whitelist disabled by default).
- **BC-01 (High):** `requestDeposit = 0` removes all anti-griefing protection, allowing costless request spam.
- **BC-04 (Medium):** Borrower can front-run `executeLiquidation()` by repaying debt to make position healthy.
- **BC-05 (Medium):** `minSeizedAssets` checked before fee deduction — liquidator receives less than guaranteed minimum.

See `Morpho_Blue_PostRefactor_Audit_v2.docx` for the full 13-finding report.
