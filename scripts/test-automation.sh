#!/bin/bash
set -euo pipefail  # Exit on error, undefined variables, pipe failures

# Debug mode - uncomment for troubleshooting
# set -x

# Mediabox Integration Test Suite
# ===============================
# Automated testing for core mediabox functionality to catch configuration 
# issues early and verify system integrity after changes.
#
# Tests include:
# - Configuration file validation
# - Script executability checks
# - Python environment validation
# - Dependencies availability
# - Core functionality smoke tests

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/mediabox_config.json"
IMPORT_SCRIPT="$SCRIPT_DIR/import.sh"
MEDIA_UPDATE_SCRIPT="$SCRIPT_DIR/media_update.py"
REQUIREMENTS_FILE="$SCRIPT_DIR/requirements.txt"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Enhanced logging with colors and timestamps
log_test() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "PASS")
            echo -e "[$timestamp] ${GREEN}✅ PASS${NC}: $message"
            TESTS_PASSED=$((TESTS_PASSED + 1))
            ;;
        "FAIL")
            echo -e "[$timestamp] ${RED}❌ FAIL${NC}: $message"
            TESTS_FAILED=$((TESTS_FAILED + 1))
            ;;
        "INFO")
            echo -e "[$timestamp] ${BLUE}ℹ️  INFO${NC}: $message"
            ;;
        "WARN")
            echo -e "[$timestamp] ${YELLOW}⚠️  WARN${NC}: $message"
            ;;
        "SKIP")
            echo -e "[$timestamp] ${YELLOW}⏭️  SKIP${NC}: $message"
            ;;
    esac
    if [[ "$level" == "PASS" || "$level" == "FAIL" ]]; then
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
    fi
}

# Test function wrapper
run_test() {
    local test_name="$1"
    local test_function="$2"
    
    log_test "INFO" "Running test: $test_name"
    
    if $test_function; then
        log_test "PASS" "$test_name"
        return 0
    else
        log_test "FAIL" "$test_name"
        return 1
    fi
}

# Test 1: Configuration file validation
test_config_loading() {
    # Check if config file exists
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_test "WARN" "Configuration file not found: $CONFIG_FILE"
        log_test "INFO" "Creating minimal test configuration..."
        
        # Create a minimal test configuration
        cat > "$CONFIG_FILE" <<EOF
{
  "venv_path": "/tmp/test_venv",
  "download_dirs": ["/tmp/downloads/completed", "/tmp/downloads/incomplete"],
  "library_dirs": {
    "tv": "/tmp/media/tv",
    "movies": "/tmp/media/movies",
    "music": "/tmp/media/music",
    "misc": "/tmp/media/misc"
  }
}
EOF
        log_test "INFO" "Test configuration created"
    fi
    
    # Validate JSON syntax
    if ! python3 -c "
import json
import sys
try:
    with open('$CONFIG_FILE') as f:
        config = json.load(f)
    print('JSON syntax valid')
except json.JSONDecodeError as e:
    print(f'Invalid JSON: {e}')
    sys.exit(1)
except Exception as e:
    print(f'Error reading file: {e}')
    sys.exit(1)
" >/dev/null 2>&1; then
        return 1
    fi
    
    # Validate required configuration keys
    python3 -c "
import json
import sys

required_keys = ['venv_path', 'download_dirs', 'library_dirs']
try:
    with open('$CONFIG_FILE') as f:
        config = json.load(f)
    
    for key in required_keys:
        if key not in config:
            print(f'Missing required key: {key}')
            sys.exit(1)
    
    # Validate library_dirs structure
    if not isinstance(config.get('library_dirs'), dict):
        print('library_dirs must be a dictionary')
        sys.exit(1)
        
    # Check for expected library directories
    expected_libs = ['tv', 'movies', 'music']
    for lib in expected_libs:
        if lib not in config['library_dirs']:
            print(f'Missing library directory: {lib}')
            sys.exit(1)
    
    print('✅ Configuration validation passed')
except Exception as e:
    print(f'Configuration validation failed: {e}')
    sys.exit(1)
" >/dev/null 2>&1
}

# Test 2: Script executability checks
test_script_executability() {
    # Test import.sh script
    if [[ ! -f "$IMPORT_SCRIPT" ]]; then
        log_test "FAIL" "Import script not found: $IMPORT_SCRIPT"
        return 1
    fi
    
    if [[ ! -x "$IMPORT_SCRIPT" ]]; then
        log_test "FAIL" "Import script not executable: $IMPORT_SCRIPT"
        return 1
    fi
    
    # Test help functionality (should not crash)
    if ! timeout 10s "$IMPORT_SCRIPT" test >/dev/null 2>&1; then
        # Try a different approach - check if script runs without crashing
        if ! bash -n "$IMPORT_SCRIPT"; then
            log_test "FAIL" "Import script has syntax errors"
            return 1
        fi
    fi
    
    # Test media_update.py script
    if [[ ! -f "$MEDIA_UPDATE_SCRIPT" ]]; then
        log_test "FAIL" "Media update script not found: $MEDIA_UPDATE_SCRIPT"
        return 1
    fi
    
    # Test Python script syntax
    if ! python3 -m py_compile "$MEDIA_UPDATE_SCRIPT" 2>/dev/null; then
        log_test "FAIL" "Media update script has Python syntax errors"
        return 1
    fi
    
    # Test help functionality
    if ! timeout 10s python3 "$MEDIA_UPDATE_SCRIPT" --help >/dev/null 2>&1; then
        log_test "WARN" "Media update script --help may have issues (not critical)"
    fi
    
    return 0
}

# Test 3: Python environment validation
test_python_environment() {
    # Check Python 3 availability
    if ! command -v python3 >/dev/null 2>&1; then
        log_test "FAIL" "python3 not found in PATH"
        return 1
    fi
    
    local python_version
    python_version=$(python3 --version 2>&1)
    log_test "INFO" "Python version: $python_version"
    
    # Test ffmpeg-python import
    if ! python3 -c "import ffmpeg; print('ffmpeg-python version:', ffmpeg.__version__ if hasattr(ffmpeg, '__version__') else 'unknown')" 2>/dev/null; then
        log_test "WARN" "ffmpeg-python not available - may need installation"
        log_test "INFO" "Run: pip3 install -r $REQUIREMENTS_FILE"
        
        # Check if requirements.txt exists
        if [[ -f "$REQUIREMENTS_FILE" ]]; then
            log_test "INFO" "Requirements file found: $REQUIREMENTS_FILE"
            log_test "INFO" "Contents: $(cat "$REQUIREMENTS_FILE" | tr '\n' ' ')"
        else
            log_test "WARN" "Requirements file not found: $REQUIREMENTS_FILE"
        fi
        
        return 1
    fi
    
    # Test other required Python modules
    local modules=("json" "os" "sys" "logging" "pathlib")
    for module in "${modules[@]}"; do
        if ! python3 -c "import $module" 2>/dev/null; then
            log_test "FAIL" "Required Python module '$module' not available"
            return 1
        fi
    done
    
    return 0
}

# Test 4: Directory structure validation
test_directory_structure() {
    local required_scripts=("import.sh" "media_update.py" "requirements.txt")
    
    for script in "${required_scripts[@]}"; do
        if [[ ! -f "$SCRIPT_DIR/$script" ]]; then
            log_test "FAIL" "Required script missing: $script"
            return 1
        fi
    done
    
    # Check if we can write to the scripts directory (for logs)
    local test_file="$SCRIPT_DIR/.test_write_$$"
    if ! touch "$test_file" 2>/dev/null; then
        log_test "WARN" "Cannot write to scripts directory - log rotation may fail"
        return 1
    fi
    rm -f "$test_file" 2>/dev/null || true
    
    return 0
}

# Test 5: Basic functionality smoke test
test_basic_functionality() {
    # Test configuration loading in Python context
    if ! python3 -c "
import json
import os
import sys

config_path = '$CONFIG_FILE'
if not os.path.exists(config_path):
    print('Configuration file not found')
    sys.exit(1)

try:
    with open(config_path, 'r') as f:
        config = json.load(f)
    
    # Test basic configuration access
    venv_path = config.get('venv_path')
    download_dirs = config.get('download_dirs', [])
    library_dirs = config.get('library_dirs', {})
    
    print(f'Config loaded successfully: {len(library_dirs)} library dirs, {len(download_dirs)} download dirs')
    
except Exception as e:
    print(f'Configuration loading failed: {e}')
    sys.exit(1)
" 2>/dev/null; then
        return 1
    fi
    
    return 0
}

# Main test execution
main() {
    echo "=========================================="
    echo "🚀 Mediabox Integration Test Suite"
    echo "=========================================="
    echo
    
    log_test "INFO" "Starting automated tests..."
    log_test "INFO" "Script directory: $SCRIPT_DIR"
    log_test "INFO" "Test configuration: $CONFIG_FILE"
    
    echo
    
    # Run all tests
    run_test "Configuration Loading" test_config_loading
    run_test "Script Executability" test_script_executability  
    run_test "Python Environment" test_python_environment
    run_test "Directory Structure" test_directory_structure
    run_test "Basic Functionality" test_basic_functionality
    
    echo
    echo "=========================================="
    echo "📊 Test Results Summary"
    echo "=========================================="
    echo -e "Tests Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Tests Failed: ${RED}$TESTS_FAILED${NC}"
    echo -e "Tests Total:  ${BLUE}$TESTS_TOTAL${NC}"
    echo
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}🎉 All tests passed! System appears healthy.${NC}"
        echo
        log_test "INFO" "Mediabox core functionality validation completed successfully"
        return 0
    else
        echo -e "${RED}💥 $TESTS_FAILED test(s) failed. Please review the issues above.${NC}"
        echo
        log_test "INFO" "Some tests failed - please address the issues before deployment"
        return 1
    fi
}

# Execute main function
main "$@"