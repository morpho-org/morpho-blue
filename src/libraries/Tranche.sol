// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {WadRayMath} from "@morpho-utils/math/WadRayMath.sol";
import {SignedMath} from "./SignedMath.sol";
import {Indexes} from "./Indexes.sol";

library Tranche {
    using WadRayMath for uint256;
    using SignedMath for uint256;
    using SignedMath for int256;
    using Indexes for uint256;
    using Tranche for Self;

    struct Self {
        uint256 actualBalance;
        uint256 scaledSupply;
        uint256 scaledBorrow;
        uint256 supplyIndex;
        uint256 borrowIndex;
        uint256 lastUpdate;
    }

    function initialize(Self storage self) internal {
        self.supplyIndex = WadRayMath.WAD;
        self.borrowIndex = WadRayMath.WAD;
        self.lastUpdate = block.timestamp;
    }

    function initialized(Self memory self) internal pure returns (bool) {
        return self.supplyIndex > 0;
    }

    function cache(Self storage self) internal returns (Self memory cached) {
        uint256 lastUpdate = self.lastUpdate;

        require(block.timestamp >= lastUpdate, "non reentrant");
        self.lastUpdate = type(uint256).max;
        cached.lastUpdate = lastUpdate;

        cached.actualBalance = self.actualBalance;
        cached.scaledSupply = self.scaledSupply;
        cached.scaledBorrow = self.scaledBorrow;
        cached.supplyIndex = self.supplyIndex;
        cached.borrowIndex = self.borrowIndex;

        require(cached.initialized(), "tranche not initialized");
    }

    function commit(Self storage self, Self memory cached) internal {
        self.actualBalance = cached.actualBalance;
        self.scaledSupply = cached.scaledSupply;
        self.scaledBorrow = cached.scaledBorrow;
        self.supplyIndex = cached.supplyIndex;
        self.borrowIndex = cached.borrowIndex;
        self.lastUpdate = cached.lastUpdate;
    }

    function utilization(Self memory self) internal pure returns (uint256) {
        return self.scaledBorrow.wadDiv(self.scaledSupply);
    }

    function updateSupplyFromScaled(Self memory self, int256 scaledDelta)
        internal
        pure
        returns (int256 normalizedDelta)
    {
        normalizedDelta = scaledDelta.wadMulDown(self.supplyIndex);

        self.scaledSupply = self.scaledSupply.sadd(scaledDelta);
        self.actualBalance = self.actualBalance.sadd(normalizedDelta);
    }

    function updateSupplyFromNormalized(Self memory self, int256 normalizedDelta)
        internal
        pure
        returns (int256 scaledDelta)
    {
        scaledDelta = normalizedDelta.wadDivDown(self.supplyIndex);

        self.scaledSupply = self.scaledSupply.sadd(scaledDelta);
        self.actualBalance = self.actualBalance.sadd(normalizedDelta);
    }

    function updateBorrowFromScaled(Self memory self, int256 scaledDelta)
        internal
        pure
        returns (int256 normalizedDelta)
    {
        normalizedDelta = scaledDelta.wadMulDown(self.borrowIndex);

        self.scaledBorrow = self.scaledBorrow.sadd(scaledDelta);
        self.actualBalance = self.actualBalance.ssub(normalizedDelta);
    }

    function updateBorrowFromNormalized(Self memory self, int256 normalizedDelta)
        internal
        pure
        returns (int256 scaledDelta)
    {
        scaledDelta = normalizedDelta.wadDivDown(self.borrowIndex);

        self.scaledBorrow = self.scaledBorrow.sadd(scaledDelta);
        self.actualBalance = self.actualBalance.ssub(normalizedDelta);
    }
}
