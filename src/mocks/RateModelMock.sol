// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {IRateModel} from "../interfaces/IRateModel.sol";

contract RateModelMock is IRateModel {
    uint256 internal _dBorrowRate;

    function dBorrowRate(uint256) external view returns (uint256) {
        return _dBorrowRate;
    }

    function setDBorrowRate(uint256 newDBorrowRate) external {
        _dBorrowRate = newDBorrowRate;
    }
}
