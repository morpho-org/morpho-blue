// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;

interface IIRM {
	function rate(uint utilization) external pure returns (uint);
}
