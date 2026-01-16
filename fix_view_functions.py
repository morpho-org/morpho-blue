with open('src/extensions/TieredLiquidationMorpho.sol', 'r') as f:
    lines = f.readlines()

# Find and remove old VIEW FUNCTIONS
new_lines = []
skip = False
in_view_section = False

for i, line in enumerate(lines):
    if '/* VIEW FUNCTIONS */' in line:
        in_view_section = True
        new_lines.append(line)
        # Add new simple view functions
        new_lines.append('    \n')
        new_lines.append('    /// @notice Get health factor for a borrower\n')
        new_lines.append('    function getHealthFactor(MarketParams memory marketParams, address borrower)\n')
        new_lines.append('        external\n')
        new_lines.append('        view\n')
        new_lines.append('        returns (uint256)\n')
        new_lines.append('    {\n')
        new_lines.append('        Id marketId = marketParams.id();\n')
        new_lines.append('        Market memory marketData = morpho.market(marketId);\n')
        new_lines.append('        Position memory pos = morpho.position(marketId, borrower);\n')
        new_lines.append('        uint256 collateralPrice = IOracle(marketParams.oracle).price();\n')
        new_lines.append('        uint256 borrowed = uint256(pos.borrowShares).toAssetsUp(\n')
        new_lines.append('            marketData.totalBorrowAssets,\n')
        new_lines.append('            marketData.totalBorrowShares\n')
        new_lines.append('        );\n')
        new_lines.append('        return HealthFactorLib.calculateHealthFactor(\n')
        new_lines.append('            pos.collateral,\n')
        new_lines.append('            collateralPrice,\n')
        new_lines.append('            borrowed,\n')
        new_lines.append('            marketParams.lltv\n')
        new_lines.append('        );\n')
        new_lines.append('    }\n')
        skip = True
        continue
    
    if in_view_section and '/* INTERNAL FUNCTIONS */' in line:
        skip = False
        in_view_section = False
        
    if not skip:
        new_lines.append(line)

with open('src/extensions/TieredLiquidationMorpho.sol', 'w') as f:
    f.writelines(new_lines)

print("✅ VIEW functions fixed")
