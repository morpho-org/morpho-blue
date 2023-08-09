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

/// @notice Contains the `v`, `r` and `s` parameters of an ECDSA signature.
struct Signature {
    uint8 v;
    bytes32 r;
    bytes32 s;
}

interface IBlue is IFlashLender {
    event SupplyCollateral(Id indexed id, address indexed caller, address indexed onBehalf, uint256 amount);
    event WithdrawCollateral(
        Id indexed id, address caller, address indexed onBehalf, address indexed receiver, uint256 amount
    );

    event Supply(Id indexed id, address indexed caller, address indexed onBehalf, uint256 amount, uint256 shares);
    event Withdraw(
        Id indexed id,
        address caller,
        address indexed onBehalf,
        address indexed receiver,
        uint256 amount,
        uint256 shares
    );

    event Borrow(
        Id indexed id,
        address caller,
        address indexed onBehalf,
        address indexed receiver,
        uint256 amount,
        uint256 shares
    );
    event Repay(Id indexed id, address indexed caller, address indexed onBehalf, uint256 amount, uint256 shares);

    event Liquidate(
        Id indexed id,
        address indexed caller,
        address indexed borrower,
        uint256 repaid,
        uint256 repaidShares,
        uint256 seized,
        uint256 badDebtShares
    );

    event FlashLoan(address indexed caller, address indexed token, uint256 amount);

    event SetOwner(address indexed newOwner);

    event SetFee(Id indexed id, uint256 fee);

    event SetFeeRecipient(address indexed feeRecipient);

    event CreateMarket(Id indexed id, Market market);

    event SetAuthorization(
        address indexed caller, address indexed authorizer, address indexed authorized, bool isAuthorized
    );

    event IncrementNonce(address indexed caller, address indexed signatory, uint256 usedNonce);

    event EnableIrm(address indexed irm);

    event EnableLltv(uint256 lltv);

    event AccrueInterests(Id indexed id, uint256 borrowRate, uint256 accruedInterests, uint256 feeShares);

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

    function supply(Market memory market, uint256 amount, address onBehalf, bytes memory data) external;
    function withdraw(Market memory market, uint256 amount, address onBehalf, address receiver) external;
    function borrow(Market memory market, uint256 amount, address onBehalf, address receiver) external;
    function repay(Market memory market, uint256 amount, address onBehalf, bytes memory data) external;
    function supplyCollateral(Market memory market, uint256 amount, address onBehalf, bytes memory data) external;
    function withdrawCollateral(Market memory market, uint256 amount, address onBehalf, address receiver) external;
    function liquidate(Market memory market, address borrower, uint256 seized, bytes memory data) external;
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
