// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {IOracle} from "src/interfaces/IOracle.sol";
import {Constants} from "./Constants.sol";
import {EnumerableSet} from "lib/openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";

/// @title Types
/// @author Morpho Labs
/// @custom:contact security@morpho.xyz
/// @notice Library exposing all Types used in Morpho.
library Types {
    /* STRUCTS */

    struct Tranche {
        uint256 totalSupply;
        uint256 totalBorrow;
        uint256 supplyIndex;
        uint256 borrowIndex;
        uint256 lastUpdateTimestamp;
    }

    struct Market {
        address collateral;
        address token;
        //Borrow
        mapping(address => uint256) collateralBalance;
        mapping(address => mapping(uint256 => uint256)) borrowBalance;
        mapping(address => EnumerableSet.UintSet) borrowerLltvMapSet;
        //Supply
        mapping(address => mapping(uint256 => uint256)) supplyBalance;
        mapping(address => EnumerableSet.UintSet) supplierLltvMapSet;
        //Random stuff
        Tranche[] tranches;
        IOracle oracle;
        uint256 reserveFactor;
    }
}
