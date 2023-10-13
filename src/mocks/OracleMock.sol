// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IOracle} from "../interfaces/IOracle.sol";
import {SharesMathLib} from "../libraries/SharesMathLib.sol";
import {MathLib} from "../libraries/MathLib.sol";
import "../libraries/ConstantsLib.sol";

contract OracleMock is IOracle {
    using SharesMathLib for uint256;
    using MathLib for uint256;

    address public loanToken;
    address public collateralToken;
    uint256 public price;

    function setPrice(address newLoanToken, address newCollateralToken, uint256 newPrice) external {
        loanToken = newLoanToken;
        collateralToken = newCollateralToken;
        price = newPrice;
    }

    // In _isHealthy, we value collateral tokens in loan token terms, so collateral is base and loan is quote.
    function value(address baseToken, address quoteToken, uint256 baseAmount) public view override returns (uint256 quoteAmount) {
        if (baseToken == loanToken && quoteToken == collateralToken) quoteAmount = price.mulDivDown(ORACLE_PRICE_SCALE, baseAmount);
        if (baseToken == collateralToken && quoteToken == loanToken) quoteAmount = baseAmount.mulDivDown(price, ORACLE_PRICE_SCALE);
    }
}
