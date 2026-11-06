// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

import {IIrm} from "../../../interfaces/IIrm.sol";
import {Id} from "../../../interfaces/IMorpho.sol";

/// @title IAdaptiveCurveIrm
/// @author Morpho Labs
/// @custom:contact security@morpho.org
/// @notice Interface exposed by the AdaptiveCurveIrm.
interface IAdaptiveCurveIrm is IIrm {
    /// @notice Address of Morpho.
    function MORPHO() external view returns (address);

    /// @notice Rate at target utilization.
    /// @dev Tells the height of the curve.
    function rateAtTarget(Id id) external view returns (int256);
}
