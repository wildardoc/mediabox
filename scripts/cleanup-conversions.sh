#!/bin/bash
# Cleanup Conversions Wrapper Script
# This script runs the Python cleanup script using the proper virtual environment

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Virtual environment path
VENV_PATH="$SCRIPT_DIR/.venv"

# Check if virtual environment exists
if [[ ! -d "$VENV_PATH" ]]; then
    echo "❌ Virtual environment not found at: $VENV_PATH"
    echo "Please run the setup scripts first"
    exit 1
fi

# Use virtual environment Python
VENV_PYTHON="$VENV_PATH/bin/python"

if [[ ! -x "$VENV_PYTHON" ]]; then
    echo "❌ Python executable not found at: $VENV_PYTHON"
    exit 1
fi

echo "🔍 Running media conversion cleanup..."
echo "📍 Using Python: $VENV_PYTHON"

# Run the cleanup script with all provided arguments
exec "$VENV_PYTHON" "$SCRIPT_DIR/cleanup-conversions.py" "$@"
