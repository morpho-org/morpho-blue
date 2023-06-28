// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20Mock} from "./ERC20Mock.sol";
import {Market} from "src/Market.sol";

contract LiquidatorMock {
    function approveBorrowable(Market market) public {
        ERC20Mock(market.borrowableAsset()).approve(address(market), type(uint).max);
    }

    function nativeBatchLiquidate(Market market, Market.Liquidation[] memory liquidationData)
        external
        returns (int sumCollat, int sumBorrow)
    {
        return market.batchLiquidate(liquidationData);
    }

    function manualBatchLiquidate(Market market, Market.Liquidation[] memory liquidationData)
        external
        returns (int sumCollat, int sumBorrow)
    {
        for (uint i; i < liquidationData.length; i++) {
            Market.Liquidation memory liq = liquidationData[i];
            (int collat, int borrow) = market.singleLiquidate(liq.bucket, liq.borrower, liq.maxCollat);
            sumCollat += collat;
            sumBorrow += borrow;
        }
    }
}
