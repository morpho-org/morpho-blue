// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IIrm} from "src/interfaces/IIrm.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IOracle} from "src/interfaces/IOracle.sol";
import {SafeTransferLib} from "src/libraries/SafeTransferLib.sol";

type Id is bytes32;

struct Market {
    IERC20 borrowableAsset;
    IERC20 collateralAsset;
    IOracle borrowableOracle;
    IOracle collateralOracle;
    IIrm irm;
    uint256 lltv;
}

library MarketLib {
    function id(Market memory market) internal pure returns (Id) {
        return Id.wrap(keccak256(abi.encode(market)));
    }

    function isCollateralNative(Market memory market) internal pure returns (bool) {
        return address(market.collateralAsset) == address(0);
    }

    function isBorrowableNative(Market memory market) internal pure returns (bool) {
        return address(market.borrowableAsset) == address(0);
    }

    function safeTransferCollateral(Market memory market, address to, uint256 amount) internal {
        if (isCollateralNative(market)) {
            SafeTransferLib.safeTransferETH(to, amount);
        } else {
            SafeTransferLib.safeTransfer(market.collateralAsset, to, amount);
        }
    }

    function safeTransferBorrowable(Market memory market, address to, uint256 amount) internal {
        if (isBorrowableNative(market)) {
            SafeTransferLib.safeTransferETH(to, amount);
        } else {
            SafeTransferLib.safeTransfer(market.borrowableAsset, to, amount);
        }
    }
}
