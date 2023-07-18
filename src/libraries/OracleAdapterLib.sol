// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

library OracleAdapterLib {
    function price(address oracle, bytes4 selector) internal view returns (uint256) {
        (, bytes memory borrowOracleData) = oracle.staticcall(abi.encode(selector));

        return abi.decode(borrowOracleData, (uint256));
    }
}
