// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IPreLiquidation, PreLiquidationParams} from "./interfaces/IPreLiquidation.sol";
import {IPreLiquidationFactory} from "./interfaces/IPreLiquidationFactory.sol";
import {IMorpho, Id} from "../../interfaces/IMorpho.sol";

import {ErrorsLib} from "./libraries/ErrorsLib.sol";
import {EventsLib} from "./libraries/EventsLib.sol";

import {PreLiquidation} from "./PreLiquidation.sol";

/// @title PreLiquidationFactory
/// @author Morpho Labs
/// @custom:contact security@morpho.org
/// @notice A linear LIF and linear LCF pre-liquidation factory contract for Morpho.
contract PreLiquidationFactory is IPreLiquidationFactory {
    /* IMMUTABLE */

    /// @notice The address of the Morpho contract.
    IMorpho public immutable MORPHO;

    /* STORAGE */

    /// @notice Mapping which returns true if the address is a PreLiquidation contract created by this factory.
    mapping(address => bool) public isPreLiquidation;

    /* CONSTRUCTOR */

    /// @param morpho The address of the Morpho contract.
    constructor(address morpho) {
        require(morpho != address(0), ErrorsLib.ZeroAddress());

        MORPHO = IMorpho(morpho);
    }

    /* EXTERNAL */

    /// @notice Creates a PreLiquidation contract.
    /// @param id The Morpho market for PreLiquidations.
    /// @param preLiquidationParams The PreLiquidation params for the PreLiquidation contract.
    /// @dev Warning: This function will revert without data if the pre-liquidation already exists.
    function createPreLiquidation(Id id, PreLiquidationParams calldata preLiquidationParams)
        external
        returns (IPreLiquidation)
    {
        IPreLiquidation preLiquidation =
            IPreLiquidation(address(new PreLiquidation{salt: 0}(address(MORPHO), id, preLiquidationParams)));

        emit EventsLib.CreatePreLiquidation(address(preLiquidation), id, preLiquidationParams);

        isPreLiquidation[address(preLiquidation)] = true;

        return preLiquidation;
    }
}
