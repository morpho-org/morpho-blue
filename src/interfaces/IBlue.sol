// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;

import {IFlashLender} from "./IFlashLender.sol";
import {Market, Id} from "../libraries/MarketLib.sol";

type Id is bytes32;

struct MarketParams {
    address borrowableAsset;
    address collateralAsset;
    address oracle;
    address irm;
    uint256 lltv;
}

/// @notice Contains the `v`, `r` and `s` parameters of an ECDSA signature.
struct Signature {
    uint8 v;
    bytes32 r;
    bytes32 s;
}

interface IBlue is IFlashLender {
    function DOMAIN_SEPARATOR() external view returns (bytes32);

    function owner() external view returns (address);
    function feeRecipient() external view returns (address);

    function supplyShares(Id, address) external view returns (uint256);
    function borrowShares(Id, address) external view returns (uint256);
    function collateral(Id, address) external view returns (uint256);
    function totalSupply(Id) external view returns (uint256);
    function totalSupplyShares(Id) external view returns (uint256);
    function totalBorrow(Id) external view returns (uint256);
    function totalBorrowShares(Id) external view returns (uint256);
    function lastUpdate(Id) external view returns (uint256);
    function fee(Id) external view returns (uint256);

    function isIrmEnabled(address) external view returns (bool);
    function isLltvEnabled(uint256) external view returns (bool);
    function isAuthorized(address, address) external view returns (bool);
    function nonce(address) external view returns (uint256);

    function setOwner(address newOwner) external;
    function enableIrm(address irm) external;
    function enableLltv(uint256 lltv) external;
    function setFee(MarketParams memory marketParams, uint256 newFee) external;
    function setFeeRecipient(address recipient) external;
    function createMarket(MarketParams memory market) external;

    function supply(MarketParams memory marketParams, uint256 amount, uint256 shares, address onBehalf, bytes memory data)
        external;
    function withdraw(MarketParams memory marketParams, uint256 amount, uint256 shares, address onBehalf, address receiver)
        external;
    function borrow(MarketParams memory marketParams, uint256 amount, uint256 shares, address onBehalf, address receiver)
        external;
    function repay(MarketParams memory marketParams, uint256 amount, uint256 shares, address onBehalf, bytes memory data)
        external;
    function supplyCollateral(MarketParams memory marketParams, uint256 amount, address onBehalf, bytes memory data) external;
    function withdrawCollateral(MarketParams memory marketParams, uint256 amount, address onBehalf, address receiver) external;
    function liquidate(MarketParams memory marketParams, address borrower, uint256 seized, bytes memory data) external;
    function flashLoan(address token, uint256 amount, bytes calldata data) external;

    function setAuthorization(address authorized, bool newIsAuthorized) external;
    function setAuthorizationWithSig(
        address authorizer,
        address authorized,
        bool newIsAuthorized,
        uint256 deadline,
        Signature calldata signature
    ) external;

    function extsload(bytes32[] memory slots) external view returns (bytes32[] memory res);
}
