// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

import {IERC3156xFlashLiquidator} from "./IERC3156xFlashLiquidator.sol";

import {MarketKey, MarketState, MarketShares, Position} from "../libraries/Types.sol";

interface IMorpho {
    function stateAt(MarketKey calldata marketKey) external view returns (MarketState memory state);

    function positionOf(MarketKey calldata marketKey, address user) external view returns (Position memory position);

    function depositCollateral(MarketKey calldata marketKey, uint256 assets, address onBehalf) external;

    function withdrawCollateral(MarketKey calldata marketKey, uint256 assets, address onBehalf, address receiver)
        external;

    function deposit(MarketKey calldata marketKey, uint256 assets, address onBehalf) external returns (uint256);

    function withdraw(MarketKey calldata marketKey, uint256 assets, address onBehalf, address receiver)
        external
        returns (uint256);

    function borrow(MarketKey calldata marketKey, uint256 assets, address onBehalf, address receiver)
        external
        returns (uint256);

    function repay(MarketKey calldata marketKey, uint256 assets, address onBehalf) external returns (uint256);

    function liquidate(
        MarketKey calldata marketKey,
        address user,
        uint256 debt,
        uint256 collateral,
        address receiver,
        IERC3156xFlashLiquidator liquidator,
        bytes calldata data
    ) external returns (uint256 repaid, bytes memory returnData);
}
