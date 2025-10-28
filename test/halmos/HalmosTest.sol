// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../../lib/forge-std/src/Test.sol";
import {SymTest} from "../../lib/halmos-cheatcodes/src/SymTest.sol";

import {IMorpho} from "../../src/interfaces/IMorpho.sol";
import {IrmMock} from "../../src/mocks/IrmMock.sol";
import {ERC20Mock} from "../../src/mocks/ERC20Mock.sol";
import {OracleMock} from "../../src/mocks/OracleMock.sol";
import {FlashBorrowerMock} from "../../src/mocks/FlashBorrowerMock.sol";

import "../../src/Morpho.sol";
import "../../src/libraries/ConstantsLib.sol";
import {MorphoLib} from "../../src/libraries/periphery/MorphoLib.sol";

/// @custom:halmos --solver-timeout-assertion 0
contract HalmosTest is SymTest, Test {
    using MorphoLib for IMorpho;
    using MarketParamsLib for MarketParams;

    address internal owner;

    IMorpho internal morpho;
    ERC20Mock internal loanToken;
    ERC20Mock internal collateralToken;
    OracleMock internal oracle;
    IrmMock internal irm;
    uint256 internal lltv;

    MarketParams internal marketParams;

    ERC20Mock internal otherToken;
    FlashBorrowerMock internal flashBorrower;

    function setUp() public virtual {
        owner = svm.createAddress("owner");
        morpho = IMorpho(address(new Morpho(owner)));

        loanToken = new ERC20Mock();
        collateralToken = new ERC20Mock();
        oracle = new OracleMock();
        oracle.setPrice(ORACLE_PRICE_SCALE);
        irm = new IrmMock();
        lltv = svm.createUint256("lltv");

        marketParams = MarketParams({
            loanToken: address(loanToken),
            collateralToken: address(collateralToken),
            oracle: address(oracle),
            irm: address(irm),
            lltv: lltv
        });
        vm.startPrank(owner);
        morpho.enableIrm(address(irm));
        morpho.enableLltv(lltv);
        morpho.createMarket(marketParams);
        vm.stopPrank();

        // for flashLoan
        otherToken = new ERC20Mock();
        flashBorrower = new FlashBorrowerMock(morpho);

        // Enable symbolic storage
        svm.enableSymbolicStorage(address(this));
        svm.enableSymbolicStorage(address(morpho));
        svm.enableSymbolicStorage(address(loanToken));
        svm.enableSymbolicStorage(address(collateralToken));
        svm.enableSymbolicStorage(address(oracle));
        svm.enableSymbolicStorage(address(irm));
        svm.enableSymbolicStorage(address(otherToken));
        svm.enableSymbolicStorage(address(flashBorrower));

        // Set symbolic block number and timestamp
        vm.roll(svm.createUint(64, "block.number"));
        vm.warp(svm.createUint(64, "block.timestamp"));
    }

    // Call Morpho, assuming interacting with only the defined market for performance reasons.
    function _callMorpho(bytes4 selector, address caller) internal {
        vm.assume(selector != morpho.extSloads.selector);
        vm.assume(selector != morpho.createMarket.selector);

        bytes memory emptyData = hex"";
        uint256 assets = svm.createUint256("assets");
        uint256 shares = svm.createUint256("shares");
        address onBehalf = svm.createAddress("onBehalf");
        address receiver = svm.createAddress("receiver");

        bytes memory args;

        if (selector == morpho.supply.selector || selector == morpho.repay.selector) {
            args = abi.encode(marketParams, assets, shares, onBehalf, emptyData);
        } else if (selector == morpho.withdraw.selector || selector == morpho.borrow.selector) {
            args = abi.encode(marketParams, assets, shares, onBehalf, receiver);
        } else if (selector == morpho.supplyCollateral.selector) {
            args = abi.encode(marketParams, assets, onBehalf, emptyData);
        } else if (selector == morpho.withdrawCollateral.selector) {
            args = abi.encode(marketParams, assets, onBehalf, receiver);
        } else if (selector == morpho.liquidate.selector) {
            address borrower = svm.createAddress("borrower");
            args = abi.encode(marketParams, borrower, assets, shares, emptyData);
        } else if (selector == morpho.flashLoan.selector) {
            address token = svm.createAddress("token");
            bytes memory _data = svm.createBytes(1024, "_data");
            args = abi.encode(token, assets, _data);
        } else if (selector == morpho.accrueInterest.selector) {
            args = abi.encode(marketParams);
        } else if (selector == morpho.setFee.selector) {
            uint256 newFee = svm.createUint256("newFee");
            args = abi.encode(marketParams, newFee);
        } else {
            args = svm.createBytes(1024, "data");
        }

        vm.prank(caller);
        (bool success,) = address(morpho).call(abi.encodePacked(selector, args));
        vm.assume(success);
    }

    // Check that the fee is always smaller than the max fee.
    function check_feeInRange(bytes4 selector, address caller, Id id) public {
        vm.assume(morpho.fee(id) <= MAX_FEE);

        _callMorpho(selector, caller);

        assert(morpho.fee(id) <= MAX_FEE);
    }

    // Check that there is always less borrow than supply on the market.
    function check_borrowLessThanSupply(bytes4 selector, address caller, Id id) public {
        vm.assume(morpho.totalBorrowAssets(id) <= morpho.totalSupplyAssets(id));

        _callMorpho(selector, caller);

        assert(morpho.totalBorrowAssets(id) <= morpho.totalSupplyAssets(id));
    }

    // Check that the market cannot be "destroyed".
    function check_lastUpdateNonZero(bytes4 selector, address caller, Id id) public {
        vm.assume(morpho.lastUpdate(id) != 0);

        _callMorpho(selector, caller);

        assert(morpho.lastUpdate(id) != 0);
    }

    // Check that the lastUpdate can only increase.
    function check_lastUpdateCannotDecrease(bytes4 selector, address caller, Id id) public {
        uint256 lastUpdateBefore = morpho.lastUpdate(id);

        _callMorpho(selector, caller);

        uint256 lastUpdateAfter = morpho.lastUpdate(id);
        assert(lastUpdateAfter >= lastUpdateBefore);
    }

    // Check that enabled LLTVs are necessarily less than 1.
    function check_lltvSmallerThanWad(bytes4 selector, address caller, uint256 _lltv) public {
        vm.assume(!morpho.isLltvEnabled(_lltv) || _lltv < 1e18);

        _callMorpho(selector, caller);

        assert(!morpho.isLltvEnabled(_lltv) || _lltv < 1e18);
    }

    // Check that LLTVs can't be disabled.
    function check_lltvCannotBeDisabled(bytes4 selector, address caller) public {
        _callMorpho(selector, caller);

        assert(morpho.isLltvEnabled(lltv));
    }

    // Check that IRMs can't be disabled.
    // Note: IRM is not symbolic, that is not ideal.
    function check_irmCannotBeDisabled(bytes4 selector, address caller) public {
        _callMorpho(selector, caller);

        assert(morpho.isIrmEnabled(address(irm)));
    }

    // Check that the nonce of users cannot decrease.
    function check_nonceCannotDecrease(bytes4 selector, address caller, address user) public {
        uint256 nonceBefore = morpho.nonce(user);

        _callMorpho(selector, caller);

        uint256 nonceAfter = morpho.nonce(user);
        assert(nonceAfter == nonceBefore || nonceAfter == nonceBefore + 1);
    }

    // Check that idToMarketParams cannot change.
    // Note: ok because createMarket is never called by _callMorpho.
    function check_idToMarketParamsForCreatedMarketCannotChange(bytes4 selector, address caller, Id id) public {
        MarketParams memory itmpBefore = morpho.idToMarketParams(id);

        _callMorpho(selector, caller);

        MarketParams memory itmpAfter = morpho.idToMarketParams(id);
        assert(Id.unwrap(itmpBefore.id()) == Id.unwrap(itmpAfter.id()));
    }
}
