// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.5.0;

import {IERC3156xFlashLiquidator} from "src/interfaces/IERC3156xFlashLiquidator.sol";

import {MarketKey, TrancheId, Tranche, TrancheShares} from "src/libraries/Types.sol";

interface IMorpho {
    function trancheAt(MarketKey calldata marketKey, TrancheId trancheId)
        external
        view
        returns (Tranche memory tranche);
    function sharesOf(MarketKey calldata marketKey, TrancheId trancheId, address user)
        external
        view
        returns (uint256 collateral, TrancheShares memory shares);

    function depositCollateral(MarketKey calldata marketKey, uint256 assets, address onBehalf) external;
    function withdrawCollateral(MarketKey calldata marketKey, uint256 assets, address onBehalf, address receiver)
        external;

    function deposit(MarketKey calldata marketKey, TrancheId trancheId, uint256 assets, address onBehalf)
        external
        returns (uint256);
    function withdraw(
        MarketKey calldata marketKey,
        TrancheId trancheId,
        uint256 assets,
        address onBehalf,
        address receiver
    ) external returns (uint256);

    function borrow(
        MarketKey calldata marketKey,
        TrancheId trancheId,
        uint256 assets,
        address onBehalf,
        address receiver
    ) external returns (uint256);
    function repay(MarketKey calldata marketKey, TrancheId trancheId, uint256 assets, address onBehalf)
        external
        returns (uint256);

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
