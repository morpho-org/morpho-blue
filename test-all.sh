#!/bin/bash

# Morpho Blue Custom Features Test Suite

set -e

echo "================================================"
echo "🚀 Running Morpho Blue Custom Feature Tests"
echo "================================================"
echo ""

# Color definitions
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

run_test() {
    local test_name=$1
    local test_contract=$2
    
    echo -e "${YELLOW}▶ Running test: ${test_name}${NC}"
    echo "================================================"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    if forge test --match-contract $test_contract -vv; then
        echo -e "${GREEN}✓ Test passed: ${test_name}${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}✗ Test failed: ${test_name}${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    
    echo ""
}

# 1. Whitelist Registry Tests
run_test "Whitelist Registry" "WhitelistRegistryIntegrationTest"

# 2. Tiered Liquidation Tests
run_test "Tiered Liquidation" "TieredLiquidationIntegrationTest"

# 3. Original Morpho Tests (ensure no regression)
echo -e "${YELLOW}▶ Running original Morpho test suite${NC}"
echo "================================================"
if forge test --match-path "test/forge/integration/*" -vv; then
    echo -e "${GREEN}✓ Original features test passed${NC}"
else
    echo -e "${RED}✗ Original features test failed${NC}"
fi
echo ""

# Output test summary
echo "================================================"
echo "📊 Test Summary"
echo "================================================"
echo -e "Total tests: ${TOTAL_TESTS}"
echo -e "${GREEN}Passed: ${PASSED_TESTS}${NC}"
echo -e "${RED}Failed: ${FAILED_TESTS}${NC}"
echo ""

if [ $FAILED_TESTS -eq 0 ]; then
    echo -e "${GREEN}🎉 All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}❌ Some tests failed, please check!${NC}"
    exit 1
fi

