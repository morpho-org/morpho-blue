#!/bin/bash

# Generate test coverage report for custom features

set -e

echo "================================================"
echo "Generating Test Coverage Report"
echo "================================================"
echo ""

# Run coverage for custom contracts
forge coverage \
    --match-path "src/extensions/**/*.sol" \
    --report lcov

echo ""
echo "Coverage report generated: lcov.info"
echo ""

# Optional: Generate HTML report if lcov is installed
if command -v genhtml &> /dev/null; then
    echo "Generating HTML coverage report..."
    genhtml lcov.info -o coverage-report
    echo "HTML report generated in: coverage-report/"
    echo "Open coverage-report/index.html to view"
else
    echo "Install lcov to generate HTML report: brew install lcov"
fi

echo ""
echo "================================================"
echo "✅ Coverage Report Complete"
echo "================================================"

