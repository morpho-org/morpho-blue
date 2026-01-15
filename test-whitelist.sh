#!/bin/bash

# Test script for Whitelist Registry feature only

set -e

echo "================================================"
echo "Testing Whitelist Registry Feature"
echo "================================================"

# Run whitelist registry tests with verbose output
forge test --match-contract WhitelistRegistryIntegrationTest -vvv

echo ""
echo "================================================"
echo "✅ Whitelist Registry Tests Complete"
echo "================================================"

