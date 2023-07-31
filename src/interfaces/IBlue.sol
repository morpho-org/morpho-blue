// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;

import {IIrm} from "./IIrm.sol";
import {IFlashLender} from "src/interfaces/IFlashLender.sol";

import {Id, Market} from "../libraries/MarketLib.sol";

interface IBlue is IFlashLender {
    function owner() external view returns (address);
    function setOwner(address newOwner) external;

    function enableIrm(IIrm irm) external;
    function enableLltv(uint256 lltv) external;
    function setFee(Market memory market, uint256 newFee) external;
    function setFeeRecipient(address recipient) external;

    function totalSupply(Id) external view returns (uint256);
    function totalBorrow(Id) external view returns (uint256);
    function totalSupplyShares(Id) external view returns (uint256);
    function totalBorrowShares(Id) external view returns (uint256);
    function lastUpdate(Id) external view returns (uint256);

    function fee(Id) external view returns (uint256);
    function supplyShare(Id, address) external view returns (uint256);
    function borrowShare(Id, address) external view returns (uint256);
    function collateral(Id, address) external view returns (uint256);
    function isApproved(address, address) external view returns (bool);

    function isIrmEnabled(IIrm) external view returns (bool);
    function isLltvEnabled(uint256) external view returns (bool);
    function feeRecipient() external view returns (address);

    function createMarket(Market memory market) external;
    function setApproval(address manager, bool isAllowed) external;

    function supply(Market memory market, uint256 amount, address onBehalf, bytes memory data) external;
    function withdraw(Market memory market, uint256 amount, address onBehalf) external;
    function borrow(Market memory market, uint256 amount, address onBehalf) external;
    function repay(Market memory market, uint256 amount, address onBehalf, bytes memory data) external;

    function supplyCollateral(Market memory market, uint256 amount, address onBehalf, bytes memory data) external;
    function withdrawCollateral(Market memory market, uint256 amount, address onBehalf) external;

    function liquidate(Market memory market, address borrower, uint256 seized, bytes memory data) external;

    function extsload(bytes32[] memory slots) external view returns (bytes32[] memory res);
}
