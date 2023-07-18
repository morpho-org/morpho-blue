// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

struct Oracle {
    address contractAddress;
    bytes4 priceSelector;
}

library OracleLib {
    function price(Oracle memory oracle) internal view returns (uint256) {
        (, bytes memory oracleData) = oracle.contractAddress.staticcall(abi.encode(oracle.priceSelector));

        return abi.decode(oracleData, (uint256));
    }
}
