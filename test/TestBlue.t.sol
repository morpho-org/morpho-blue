// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {Test} from "forge-std/Test.sol";
import {Blue} from "../src/Blue.sol";
import {Account as BlueAccount} from "../src/libraries/Account.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";
import {BlueOracleMock} from "./mocks/BlueOracleMock.sol";
import {IrmMock} from "./mocks/IrmMock.sol";

contract TestBlue is Test {
    Blue internal blue;
    ERC20Mock internal collateralAsset;
    ERC20Mock internal borrowableAsset;
    BlueOracleMock internal oracle;
    IrmMock internal irm;

    address userA = address(0xaaaa);
    address userB = address(0xbbbb);

    function setUp() public {
        collateralAsset = new ERC20Mock("collateral", "C", 18);
        borrowableAsset = new ERC20Mock("borrowable", "B", 18);
        oracle = new BlueOracleMock();
        irm = new IrmMock();

        uint256[] memory lltvs = new uint256[](5);
        lltvs[0] = 1e17;
        lltvs[1] = 3e17;
        lltvs[2] = 5e17;
        lltvs[3] = 7e17;
        lltvs[4] = 9e17;

        blue = new Blue(address(collateralAsset), address(borrowableAsset), address(oracle), address(irm), lltvs);

        oracle.set(1, 0);

        vm.startPrank(userA);
        borrowableAsset.approve(address(blue), type(uint256).max);
        collateralAsset.approve(address(blue), type(uint256).max);

        vm.startPrank(userB);
        borrowableAsset.approve(address(blue), type(uint256).max);
        collateralAsset.approve(address(blue), type(uint256).max);
    }

    function test() public {
        borrowableAsset.setBalance(userA, 1e18);
        collateralAsset.setBalance(userB, 10e18);
        borrowableAsset.setBalance(userB, 1e18);

        vm.startPrank(userA);
        blue.lend(BlueAccount.account(userA, 50, 1111111), 1e18);

        vm.roll(1);
        vm.warp(block.timestamp + 1 days);

        vm.startPrank(userB);
        blue.borrow(BlueAccount.account(userB, 50, 0), 2e18, 1e18, hex"");

        vm.roll(1);
        vm.warp(block.timestamp + 1 days);

        blue.borrow(BlueAccount.account(userB, 50, 0), 0, type(int256).min, hex"");
    }
}
