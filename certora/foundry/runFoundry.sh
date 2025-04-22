#!/bin/bash

# Script to find and run certoraRun on all .conf files

# Get the directory where the script is located
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

# Set error handling
set -e

echo "Searching for .conf files..."

# Find all .conf files in the certora/foundry directory and subdirectories
conf_files=$(find "$SCRIPT_DIR" -type f -name "*.conf")

# Check if any conf files were found
if [ -z "$conf_files" ]; then
    echo "Error: No .conf files found in the certora/foundry directory or subdirectories."
    exit 1
fi

# Count files found
file_count=$(echo "$conf_files" | wc -l)
echo "Found $file_count .conf files"

# Counter for successful runs
success_count=0
failed_files=()

# Loop through each .conf file
for conf_file in $conf_files; do
    echo "Running certoraRun on $conf_file..."
    if certoraRun "$conf_file" --server production --prover_version master; then
        echo "Successfully processed $conf_file"
        ((success_count++))
    else
        echo "Error: Failed to process $conf_file"
        failed_files+=("$conf_file")
    fi
done

# Print summary
echo "------------------------"
echo "Summary:"
echo "Total files: $file_count"
echo "Successful: $success_count"
echo "Failed: ${#failed_files[@]}"

# Print failed files if any
if [ ${#failed_files[@]} -gt 0 ]; then
    echo "Failed files:"
    for file in "${failed_files[@]}"; do
        echo "  - $file"
    done
    exit 1
fi

echo "All .conf files processed successfully."
exit 0

