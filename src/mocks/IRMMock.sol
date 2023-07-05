// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "src/interfaces/IIRM.sol";

contract IRMMock is IIRM {
	function rate(uint utilization) external pure returns (uint) {
		// Divide by the number of seconds in a year.
		// This is a very simple model (to refine later) where x% utilization corresponds to x% APR.
		return utilization / 365 days;
	}
}
