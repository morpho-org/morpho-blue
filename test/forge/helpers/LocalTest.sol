// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {ERC20Mock} from "src/mocks/ERC20Mock.sol";
import {OracleMock} from "src/mocks/OracleMock.sol";
import {RateModelMock} from "src/mocks/RateModelMock.sol";

import "test/helpers/BaseTest.sol";

contract LocalTest is BaseTest {
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using SafeTransferLib for ERC20;

    ERC20Mock weth;
    ERC20Mock usdc;

    OracleMock oracle;
    RateModelMock rateModel;

    Morpho morpho;

    MarketKey marketKey;

    function setUp() public virtual {
        morpho = new Morpho(address(this));

        weth = new ERC20Mock("Wrapped Ether", "WETH", 18);
        usdc = new ERC20Mock("Circle USD", "USDC", 6);

        oracle = new OracleMock();
        rateModel = new RateModelMock();

        marketKey = MarketKey({collateral: weth, asset: usdc, oracle: oracle, rateModel: rateModel});

        oracle.setPrice(1 ether);
        rateModel.setBorrowRate(0.000_000_001 ether); // 3% APR

        morpho.setIsWhitelisted(address(rateModel), true);
    }
}
