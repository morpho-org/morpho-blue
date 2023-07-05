// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {IERC20} from "src/interfaces/IERC20.sol";
import {IOracle} from "src/interfaces/IOracle.sol";

import {MathLib} from "src/libraries/MathLib.sol";

import "src/Blue.sol";

contract IRMMock is IIRM {
	using MathLib for uint;

	Blue public blue;
	Id public marketId;

	constructor (Blue blueInstance) {
		blue = Blue(blueInstance);
	}

	function setId(Id id) external {
		marketId = id;
	}

	function rate() external view returns (uint) {
		uint utilization = blue.totalBorrow(marketId).wDiv(blue.totalSupply(marketId));

		// Divide by the number of seconds in a year.
		// This is a very simple model (to refine later) where x% utilization corresponds to x% APR.
		return utilization / 365 days;
	}
}
