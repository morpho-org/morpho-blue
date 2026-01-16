import re

# Read backup
with open('src/extensions/TieredLiquidationMorpho.sol.backup', 'r') as f:
    content = f.read()

# Remove LiquidationTierLib import
content = re.sub(r'import \{LiquidationTierLib\}.*?\n', '', content)
content = re.sub(r'using LiquidationTierLib.*?;\n', '', content)

# Read new liquidate functions
with open('src/extensions/TieredLiquidation_new_liquidate.txt', 'r') as f:
    new_liquidate = f.read()

# Find and replace liquidate functions section
# From "/* LIQUIDATION FUNCTIONS */" to before "/* VIEW FUNCTIONS */"
pattern = r'/\* LIQUIDATION FUNCTIONS \*/.*?(?=/\* VIEW FUNCTIONS \*/)'
content = re.sub(pattern, new_liquidate + '\n    ', content, flags=re.DOTALL)

# Write output
with open('src/extensions/TieredLiquidationMorpho.sol', 'w') as f:
    f.write(content)

print("✅ Contract rebuilt successfully")
