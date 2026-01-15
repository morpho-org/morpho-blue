// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.19 <0.9.0;

import {Id} from "../../interfaces/IMorpho.sol";
import {WAD} from "../../libraries/MathLib.sol";

/// @title LiquidationTierLib
/// @notice Library for managing tiered liquidation configurations
library LiquidationTierLib {
    /* STRUCTS */

    /// @notice Configuration for a single liquidation tier
    struct LiquidationTier {
        /// @notice Health factor threshold (scaled by WAD)
        /// @dev Tier is triggered when healthFactor < threshold
        /// @dev Example: 1.1e18 for 110%
        uint256 healthFactorThreshold;
        /// @notice Maximum liquidation ratio (scaled by WAD)
        /// @dev Example: 0.5e18 for 50% max liquidation
        uint256 maxLiquidationRatio;
        /// @notice Liquidation bonus ratio (scaled by WAD)
        /// @dev Example: 0.05e18 for 5% bonus
        uint256 liquidationBonus;
        /// @notice Protocol fee ratio (scaled by WAD)
        /// @dev Example: 0.01e18 for 1% protocol fee
        uint256 protocolFee;
        /// @notice Whether only whitelisted liquidators can execute
        bool whitelistOnly;
        /// @notice Minimum assets to seize (prevents dust attacks)
        uint256 minSeizedAssets;
        /// @notice Cooldown period between liquidations (in seconds)
        uint256 cooldownPeriod;
    }

    /// @notice Market liquidation configuration
    struct MarketLiquidationConfig {
        /// @notice Array of liquidation tiers, sorted by threshold (descending)
        LiquidationTier[] tiers;
        /// @notice Whether tiered liquidation is enabled for this market
        bool enabled;
        /// @notice Last liquidation timestamp for each borrower
        mapping(address => uint256) lastLiquidationTime;
    }

    /* ERRORS */

    error InvalidThreshold();
    error InvalidRatio();
    error InvalidBonus();
    error TiersNotSorted();
    error NoTiersConfigured();
    error CooldownNotElapsed();

    /* CONSTANTS */

    /// @notice Default tier 1 (Conservative liquidation): 0.95 < HF < 1.0
    /// Note: Morpho Blue only allows liquidation when HF < 1.0
    uint256 public constant DEFAULT_TIER1_THRESHOLD = 1.0e18;
    uint256 public constant DEFAULT_TIER1_MAX_RATIO = 0.5e18; // 50%
    uint256 public constant DEFAULT_TIER1_BONUS = 0.05e18; // 5%
    uint256 public constant DEFAULT_TIER1_PROTOCOL_FEE = 0.01e18; // 1%

    /// @notice Default tier 2 (Aggressive liquidation): HF < 0.95
    uint256 public constant DEFAULT_TIER2_THRESHOLD = 0.95e18;
    uint256 public constant DEFAULT_TIER2_MAX_RATIO = 1.0e18; // 100%
    uint256 public constant DEFAULT_TIER2_BONUS = 0.10e18; // 10%
    uint256 public constant DEFAULT_TIER2_PROTOCOL_FEE = 0.02e18; // 2%

    /* FUNCTIONS */

    /// @notice Validate a liquidation tier configuration
    /// @param tier The tier to validate
    function validateTier(LiquidationTier memory tier) internal pure {
        if (tier.healthFactorThreshold == 0 || tier.healthFactorThreshold > 2 * WAD) {
            revert InvalidThreshold();
        }
        if (tier.maxLiquidationRatio == 0 || tier.maxLiquidationRatio > WAD) {
            revert InvalidRatio();
        }
        if (tier.liquidationBonus > 0.5e18) {
            // Max 50% bonus
            revert InvalidBonus();
        }
    }

    /// @notice Get the applicable liquidation tier for a given health factor
    /// @param tiers Array of liquidation tiers (sorted descending by threshold)
    /// @param healthFactor Current health factor
    /// @return tier The applicable tier
    /// @return tierIndex The index of the tier
    function getTierForHealthFactor(LiquidationTier[] memory tiers, uint256 healthFactor)
        internal
        pure
        returns (LiquidationTier memory tier, uint256 tierIndex)
    {
        if (tiers.length == 0) revert NoTiersConfigured();

        // Tiers are sorted by threshold descending (e.g., tier[0]=1.1, tier[1]=1.0)
        // For HF=0.8: should use tier[1] (threshold=1.0, more aggressive)
        // For HF=1.05: should use tier[0] (threshold=1.1, less aggressive)
        // We want the LAST tier where HF < threshold (most specific/aggressive)
        
        uint256 selectedIndex = type(uint256).max;
        for (uint256 i = 0; i < tiers.length; i++) {
            if (healthFactor < tiers[i].healthFactorThreshold) {
                selectedIndex = i;
            }
        }

        // If a tier was found, return it
        if (selectedIndex != type(uint256).max) {
            return (tiers[selectedIndex], selectedIndex);
        }

        // If no tier matches, return the last tier (most aggressive)
        return (tiers[tiers.length - 1], tiers.length - 1);
    }

    /// @notice Create a default two-tier configuration
    /// @return tier1 The warning tier
    /// @return tier2 The force liquidation tier
    function createDefaultTiers()
        internal
        pure
        returns (LiquidationTier memory tier1, LiquidationTier memory tier2)
    {
        // Tier 1: Conservative liquidation (0.95 < HF < 1.0) - whitelist only
        tier1 = LiquidationTier({
            healthFactorThreshold: DEFAULT_TIER1_THRESHOLD, // 1.0
            maxLiquidationRatio: DEFAULT_TIER1_MAX_RATIO,
            liquidationBonus: DEFAULT_TIER1_BONUS,
            protocolFee: DEFAULT_TIER1_PROTOCOL_FEE,
            whitelistOnly: true,
            minSeizedAssets: 0.01e18, // 0.01 token minimum
            cooldownPeriod: 1 hours
        });

        // Tier 2: Aggressive liquidation (HF < 0.95) - public access
        tier2 = LiquidationTier({
            healthFactorThreshold: DEFAULT_TIER2_THRESHOLD, // 0.95
            maxLiquidationRatio: DEFAULT_TIER2_MAX_RATIO,
            liquidationBonus: DEFAULT_TIER2_BONUS,
            protocolFee: DEFAULT_TIER2_PROTOCOL_FEE,
            whitelistOnly: false, // Public liquidation allowed
            minSeizedAssets: 0, // No minimum
            cooldownPeriod: 0 // No cooldown
        });
    }

    /// @notice Validate that tiers are properly sorted (descending thresholds)
    /// @param tiers Array of liquidation tiers
    function validateTierOrder(LiquidationTier[] memory tiers) internal pure {
        if (tiers.length < 2) return;

        for (uint256 i = 0; i < tiers.length - 1; i++) {
            // Each tier should have a higher threshold than the next
            if (tiers[i].healthFactorThreshold <= tiers[i + 1].healthFactorThreshold) {
                revert TiersNotSorted();
            }
        }
    }
}

