// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import "src/Morpho.sol";
import {
    IMorphoLiquidateCallback,
    IMorphoRepayCallback,
    IMorphoSupplyCallback,
    IMorphoSupplyCollateralCallback
} from "src/interfaces/IMorphoCallbacks.sol";
import {ERC20Mock as ERC20} from "src/mocks/ERC20Mock.sol";
import {OracleMock as Oracle} from "src/mocks/OracleMock.sol";
import {IrmMock as Irm} from "src/mocks/IrmMock.sol";

contract SupplierWithMarket {
    IMorpho private morpho;
    address private borrowableAsset;
    uint256 constant AMOUNT = 1000;

    constructor(address newMorpho, address newBorrowableAsset) {
        morpho = IMorpho(newMorpho);
        borrowableAsset = newBorrowableAsset;
        ERC20(borrowableAsset).approve(address(morpho), type(uint256).max);
    }

    function supplyOnBehalfWithMarket(Market calldata market) external {
        ERC20(borrowableAsset).transferFrom(msg.sender, address(this), AMOUNT);
        morpho.supply(market, AMOUNT, 0, msg.sender, hex"");
    }
}

contract SupplierWithId {
    IMorpho private morpho;
    address private borrowableAsset;
    uint256 constant AMOUNT = 1000;

    constructor(address newMorpho, address newBorrowableAsset) {
        morpho = IMorpho(newMorpho);
        borrowableAsset = newBorrowableAsset;
        ERC20(borrowableAsset).approve(address(morpho), type(uint256).max);
    }

    function supplyOnBehalfWithId(Id id) external {
        ERC20(borrowableAsset).transferFrom(msg.sender, address(this), AMOUNT);
        Market memory market;
        (market.borrowableAsset, market.collateralAsset, market.oracle, market.irm, market.lltv) = morpho.idToMarket(id);
        morpho.supply(market, AMOUNT, 0, msg.sender, hex"");
    }
}

contract Gas is Script {
    using MarketLib for Market;

    uint256 private constant LLTV = 0.8 ether;

    IMorpho private morpho;
    ERC20 private borrowableAsset;
    ERC20 private collateralAsset;
    Oracle private oracle;
    Irm private irm;
    Market private market;
    Id private id;

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(privateKey);
        address owner = vm.addr(privateKey);

        // Create Morpho.
        morpho = new Morpho(owner);

        // List a market.
        borrowableAsset = new ERC20("borrowable", "B", 18);
        collateralAsset = new ERC20("collateral", "C", 18);
        oracle = new Oracle();

        irm = new Irm(morpho);
        market = Market(address(borrowableAsset), address(collateralAsset), address(oracle), address(irm), LLTV);
        id = market.id();
        ERC20(borrowableAsset).setBalance(owner, type(uint256).max);

        morpho.enableIrm(address(irm));
        morpho.enableLltv(LLTV);
        morpho.createMarket(market);

        // useSupplierWithMarket();
        // ⠄ [00:01:26] [################################################################################################################################] 12/12 txes (0.0s)
        // ⠉ [00:00:06] [##############################################################################################################################] 1/1 receipts (0.0s)
        // ##### optimism-goerli
        // ✅  [Success]Hash: 0xd142b5d846bd8e912d3e31f645576e9534656a33a50d637ce6a5079be2b41410
        // Block: 13267185
        // Paid: 0.00045633900760565 ETH (152113 gas * 3.00000005 gwei)

        useSupplierWithId();
        // ⠄ [00:01:28] [################################################################################################################################] 12/12 txes (0.0s)
        // ⠉ [00:00:06] [##############################################################################################################################] 1/1 receipts (0.0s)
        // ##### optimism-goerli
        // ✅  [Success]Hash: 0x0cc477c8dac3c7d76c4ef0c5ca809f3856d41df4579bbd30ab48a1a86cd113f1
        // Block: 13287021
        // Paid: 0.00048914100815235 ETH (163047 gas * 3.00000005 gwei)

        vm.stopBroadcast();
    }

    function useSupplierWithMarket() public {
        SupplierWithMarket supplier = new SupplierWithMarket(address(morpho), address(borrowableAsset));
        borrowableAsset.approve(address(supplier), type(uint256).max);
        supplier.supplyOnBehalfWithMarket(market);
    }

    function useSupplierWithId() public {
        SupplierWithId supplier = new SupplierWithId(address(morpho), address(borrowableAsset));
        borrowableAsset.approve(address(supplier), type(uint256).max);
        supplier.supplyOnBehalfWithId(id);
    }
}
