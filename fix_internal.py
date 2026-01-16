with open('src/extensions/TieredLiquidationMorpho.sol', 'r') as f:
    content = f.read()

# Remove everything from /* INTERNAL FUNCTIONS */ to end, then add proper closing
import re
content = re.sub(r'/\* INTERNAL FUNCTIONS \*/.*', '    /* INTERNAL FUNCTIONS */\n\n    /// @notice Get validated price with oracle protection\n    function _getValidatedPrice(Id marketId, MarketParams memory marketParams)\n        internal\n        view\n        returns (uint256)\n    {\n        return PriceOracleLib.getValidatedPrice(\n            priceConfigs[marketId],\n            twapData[marketId],\n            marketParams.oracle\n        );\n    }\n}\n', content, flags=re.DOTALL)

with open('src/extensions/TieredLiquidationMorpho.sol', 'w') as f:
    f.write(content)

print("✅ Internal functions fixed")
