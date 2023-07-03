// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

error AmountIsZero();

error NotEnoughLiquidity(uint256 liquidity);

error InvalidTranche();

error HealthyHealthFactor(uint256 healthFactor);

error UnhealthyHealthFactor(uint256 healthFactor);

error AuthorizedLtv(uint256 ltv, uint256 lLtv);

error CannotBorrow();

error CannotWithdrawCollateral();

error InsufficientAllowance(uint256 currentAllowance);

error UnauthorizedIrm();

error TooMuchSeized(uint256 maxSeized);
