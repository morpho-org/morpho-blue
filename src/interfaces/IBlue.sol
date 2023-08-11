// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;

import {IFlashLender} from "./IFlashLender.sol";

type Id is bytes32;

struct Market {
    address borrowableAsset;
    address collateralAsset;
    address oracle;
    address irm;
    uint256 lltv;
}

struct Authorization {
    address authorizer;
    address authorized;
    bool isAuthorized;
    uint256 nonce;
    uint256 deadline;
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
    function setFee(Market memory market, uint256 newFee) external;
    function setFeeRecipient(address recipient) external;
    function createMarket(Market memory market) external;

    function supply(Market memory market, uint256 amount, uint256 shares, address onBehalf, bytes memory data)
        external;
    function withdraw(Market memory market, uint256 amount, uint256 shares, address onBehalf, address receiver)
        external;
    function borrow(Market memory market, uint256 amount, uint256 shares, address onBehalf, address receiver)
        external;
    function repay(Market memory market, uint256 amount, uint256 shares, address onBehalf, bytes memory data)
        external;
    function supplyCollateral(Market memory market, uint256 amount, address onBehalf, bytes memory data) external;
    function withdrawCollateral(Market memory market, uint256 amount, address onBehalf, address receiver) external;
    function liquidate(Market memory market, address borrower, uint256 seized, bytes memory data) external;
    function flashLoan(address token, uint256 amount, bytes calldata data) external;

    function setAuthorization(address authorized, bool newIsAuthorized) external;
    function setAuthorizationWithSig(Authorization calldata authorization, Signature calldata signature) external;

    function extsload(bytes32[] memory slots) external view returns (bytes32[] memory res);
}
