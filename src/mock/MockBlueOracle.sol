// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {IBlueOracle} from "src/interfaces/IBlueOracle.sol";
import {Types} from "src/libraries/Types.sol";

contract MockBlueOracle is IBlueOracle {
    mapping(address collateral => mapping(address debt => Types.OracleData)) internal _data;

    function getMarketData(address collateral, address debt) external view override returns (Types.OracleData memory) {
        return _data[collateral][debt];
    }

    function setPrice(address collateral, address debt, uint256 price) external {
        _data[collateral][debt].price = price;
    }

    function setLiquidationPaused(address collateral, address debt, bool liquidationPaused) external {
        _data[collateral][debt].liquidationPaused = liquidationPaused;
    }

    function setBorrowPaused(address collateral, address debt, bool borrowPaused) external {
        _data[collateral][debt].borrowPaused = borrowPaused;
    }
}
