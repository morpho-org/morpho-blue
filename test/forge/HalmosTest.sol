// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../../lib/forge-std/src/Test.sol";
import {SymTest} from "../../lib/halmos-cheatcodes/src/SymTest.sol";

import {IMorpho} from "../../src/interfaces/IMorpho.sol";
import {IrmMock} from "../../src/mocks/IrmMock.sol";
import {ERC20Mock} from "../../src/mocks/ERC20Mock.sol";
import {OracleMock} from "../../src/mocks/OracleMock.sol";

import "../../src/Morpho.sol";
import "../../src/libraries/ConstantsLib.sol";
import {MorphoLib} from "../../src/libraries/periphery/MorphoLib.sol";

/// @custom:halmos --symbolic-storage --solver-timeout-assertion 0
contract HalmosTest is SymTest, Test {
    using MorphoLib for IMorpho;
    using MarketParamsLib for MarketParams;

    uint256 internal constant BLOCK_TIME = 1;
    uint256 internal constant DEFAULT_TEST_LLTV = 0.8 ether;

    address internal OWNER;
    address internal FEE_RECIPIENT;

    IMorpho internal morpho;
    ERC20Mock internal loanToken;
    ERC20Mock internal collateralToken;
    OracleMock internal oracle;
    IrmMock internal irm;

    MarketParams internal marketParams;
    Id internal id;

    function setUp() public virtual {
        OWNER = address(0x10);
        FEE_RECIPIENT = address(0x11);

        morpho = IMorpho(address(new Morpho(OWNER)));

        loanToken = new ERC20Mock();
        collateralToken = new ERC20Mock();
        oracle = new OracleMock();
        oracle.setPrice(ORACLE_PRICE_SCALE);
        irm = new IrmMock();

        vm.startPrank(OWNER);
        morpho.enableIrm(address(0));
        morpho.enableIrm(address(irm));
        morpho.enableLltv(0);
        morpho.setFeeRecipient(FEE_RECIPIENT);
        vm.stopPrank();

        _setLltv(DEFAULT_TEST_LLTV);
    }

    function _setLltv(uint256 lltv) internal {
        marketParams = MarketParams(address(loanToken), address(collateralToken), address(oracle), address(irm), lltv);
        id = marketParams.id();

        vm.startPrank(OWNER);
        if (!morpho.isLltvEnabled(lltv)) morpho.enableLltv(lltv);
        if (morpho.lastUpdate(id) == 0) morpho.createMarket(marketParams);
        vm.stopPrank();

        _forward(1);
    }

    /// @dev Rolls & warps the given number of blocks forward the blockchain.
    function _forward(uint256 blocks) internal {
        vm.roll(block.number + blocks);
        vm.warp(block.timestamp + blocks * BLOCK_TIME);
    }

    function check_fee(bytes4 selector, address caller) public {
        vm.assume(selector != morpho.extSloads.selector);
        vm.assume(selector != morpho.createMarket.selector);

        bytes memory emptyData = hex"";
        uint256 assets = svm.createUint256("assets");
        uint256 shares = svm.createUint256("shares");
        address onBehalf = svm.createAddress("onBehalf");
        address receiver = svm.createAddress("receiver");

        bytes memory args;

        if (selector == morpho.supply.selector) {
            args = abi.encode(marketParams, assets, shares, onBehalf, emptyData);
        } else if (selector == morpho.withdraw.selector) {
            args = abi.encode(marketParams, assets, shares, onBehalf, receiver);
        } else if (selector == morpho.borrow.selector) {
            args = abi.encode(marketParams, assets, shares, onBehalf, receiver);
        } else if (selector == morpho.repay.selector) {
            args = abi.encode(marketParams, assets, shares, onBehalf, emptyData);
        } else if (selector == morpho.supplyCollateral.selector) {
            args = abi.encode(marketParams, assets, onBehalf, emptyData);
        } else if (selector == morpho.withdrawCollateral.selector) {
            args = abi.encode(marketParams, assets, onBehalf, receiver);
        } else if (selector == morpho.liquidate.selector) {
            address borrower = svm.createAddress("borrower");
            args = abi.encode(marketParams, borrower, assets, shares, emptyData);
        } else if (selector == morpho.flashLoan.selector) {
            uint256 rand = svm.createUint256("rand");
            address token;
            if (rand == 0) {
                token = address(loanToken);
            } else if (rand == 1) {
                token = address(collateralToken);
            } else {
                ERC20Mock otherToken = new ERC20Mock();
                token = address(otherToken);
            }
            args = abi.encode(marketParams, token, assets, emptyData);
        } else if (selector == morpho.accrueInterest.selector) {
            args = abi.encode(marketParams);
        } else if (selector == morpho.setFee.selector) {
            args = abi.encode(marketParams, amount);
        } else {
            args = svm.createBytes(1024, "data");
        }

        vm.prank(caller);
        (bool success,) = address(morpho).call(abi.encodePacked(selector, args));
        vm.assume(success);

        assert(morpho.fee(id) <= MAX_FEE);
    }
}
