#!/bin/bash

# Test script for Tiered Liquidation feature only

set -e

echo "================================================"
echo "Testing Tiered Liquidation Feature"
echo "================================================"

# Run tiered liquidation tests with verbose output
forge test --match-contract TieredLiquidationIntegrationTest -vvv

echo ""
echo "================================================"
echo "✅ Tiered Liquidation Tests Complete"
echo "================================================"

