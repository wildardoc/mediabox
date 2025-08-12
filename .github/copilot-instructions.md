# GitHub Copilot Instructions for Mediabox

## 📋 **Project Overview**

Mediabox is a security-hardened, Docker-based media aggregator stack with automated media processing capabilities. This project emphasizes **security-first architecture** with comprehensive credential management, robust error handling, and production-ready automation.

## 🔐 **Security-First Development Philosophy**

### **Core Security Principles**
- **Zero Embedded Credentials**: Never store passwords, API keys, or tokens in code or configuration files
- **Secure Environment Management**: All credentials sourced from `~/.mediabox/credentials.env` with 600 permissions
- **Input Validation**: Comprehensive validation of all user inputs, file paths, and configurations
- **Fail-Safe Defaults**: Scripts should fail safely and provide clear error messages
- **Audit Trail**: All operations logged with timestamps and context

### **Credential Security Patterns**
```bash
# ✅ CORRECT - Secure credential sourcing
CREDENTIALS_FILE="$HOME/.mediabox/credentials.env"
if [[ -f "$CREDENTIALS_FILE" ]]; then
    source "$CREDENTIALS_FILE"
else
    echo "❌ Credentials file not found. Run setup-secure-env.sh first."
    exit 1
fi

# ❌ NEVER DO - Embedded credentials
PIAUNAME="hardcoded_username"  # NEVER
API_KEY="abc123def456"         # NEVER
```

### **Configuration Validation Requirements**
```bash
# Always validate critical paths and configurations
validate_directories() {
    local dirs=("$DLDIR" "$MOVIEDIR" "$TVDIR" "$MUSICDIR")
    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            echo "❌ Directory not found: $dir"
            return 1
        fi
    done
    echo "✅ All directories validated"
}
```

## 🛠️ **Development Standards**

### **Bash Script Hardening**
All bash scripts must include defensive programming practices:
```bash
#!/bin/bash
set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Error handling function
error_exit() {
    echo "❌ ERROR: $1" >&2
    exit "${2:-1}"
}

# Trap for cleanup
cleanup() {
    echo "🧹 Cleaning up..."
    # Cleanup operations here
}
trap cleanup EXIT
```

### **Python Development Standards**
```python
#!/usr/bin/env python3
"""
Comprehensive docstring explaining the script's purpose,
parameters, and security considerations.
"""

import json
import logging
import sys
from pathlib import Path
from typing import Dict, List, Optional

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(f'media_update_{datetime.now().strftime("%Y%m%d")}.log'),
        logging.StreamHandler()
    ]
)

def validate_config(config_path: Path) -> Dict:
    """Validate configuration file with comprehensive error handling."""
    try:
        with open(config_path, 'r') as f:
            config = json.load(f)
        
        # Validate required keys
        required_keys = ['venv_path', 'download_dirs', 'library_dirs']
        for key in required_keys:
            if key not in config:
                raise ValueError(f"Missing required configuration key: {key}")
        
        return config
    except Exception as e:
        logging.error(f"Configuration validation failed: {e}")
        sys.exit(1)
```

### **Docker Configuration Best Practices**
```yaml
# Health checks for all services
services:
  service-name:
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:port/api/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
    
    # Security contexts
    user: "${PUID}:${PGID}"
    read_only: true
    security_opt:
      - no-new-privileges:true
```

## 📁 **Project Architecture**

### **Directory Structure**
```
mediabox/
├── .github/
│   └── copilot-instructions.md     # This file
├── scripts/
│   ├── media_update.py            # Core processing engine
│   ├── import.sh                  # Webhook handler
│   ├── rotate-logs.sh             # Log management
│   ├── setup-secure-env.sh        # Credential management
│   └── mediabox_config.json       # Configuration
├── docker-compose.yml             # Container orchestration
├── mediabox.sh                    # Main setup script
└── README.md                      # User documentation
```

### **Key Components**

#### **Core Processing Engine** (`scripts/media_update.py`)
- **Purpose**: Automated media conversion and processing
- **Security**: Validates all file paths, uses logging for audit trail
- **Features**: FFmpeg integration, format conversion, metadata handling

#### **Webhook System** (`scripts/import.sh`)
- **Purpose**: Integration with *arr applications for automated processing
- **Security**: Input sanitization, path validation, secure logging
- **Features**: Real-time processing triggers, error handling

#### **Credential Management** (`scripts/setup-secure-env.sh`)
- **Purpose**: Secure credential setup and management
- **Security**: 600 permissions, secure storage location, input validation
- **Features**: Interactive setup, credential testing, migration support

## 🚀 **Development Workflows**

### **Adding New Features**
1. **Security Assessment**: Identify any credential, input, or configuration requirements
2. **Error Handling**: Implement comprehensive error handling and logging
3. **Validation**: Add input validation and configuration checks
4. **Testing**: Test all error paths and edge cases
5. **Documentation**: Update README and inline documentation

### **Modifying Existing Components**
- **Preserve Security**: Maintain existing security patterns
- **Backward Compatibility**: Ensure existing configurations continue working
- **Logging**: Add logging for new functionality
- **Error Handling**: Enhance error messages and recovery

### **Docker Service Updates**
- **Health Checks**: Add or update health check configurations
- **Security**: Review user permissions and security contexts
- **Dependencies**: Update container dependencies and volume mounts
- **Testing**: Test container startup, health, and shutdown

## 🔧 **Common Implementation Patterns**

### **File Processing with Security**
```python
def process_media_file(file_path: str, output_dir: str) -> bool:
    """Process media file with comprehensive security validation."""
    # Validate input paths
    if not Path(file_path).exists():
        logging.error(f"Input file not found: {file_path}")
        return False
    
    if not Path(output_dir).is_dir():
        logging.error(f"Output directory invalid: {output_dir}")
        return False
    
    # Process with error handling
    try:
        # Processing logic here
        logging.info(f"Successfully processed: {file_path}")
        return True
    except Exception as e:
        logging.error(f"Processing failed for {file_path}: {e}")
        return False
```

### **Configuration Management**
```bash
# Standard configuration loading pattern
load_config() {
    local config_file="${1:-mediabox_config.json}"
    
    if [[ ! -f "$config_file" ]]; then
        error_exit "Configuration file not found: $config_file"
    fi
    
    # Validate JSON syntax
    if ! python3 -m json.tool "$config_file" >/dev/null 2>&1; then
        error_exit "Invalid JSON in configuration file: $config_file"
    fi
    
    echo "✅ Configuration loaded from: $config_file"
}
```

### **Docker Health Check Implementation**
```yaml
# Template for adding health checks to services
healthcheck:
  test: |
    if [ -f /app/health-check.sh ]; then
      /app/health-check.sh
    else
      curl -f http://localhost:$$SERVICE_PORT/api/health || exit 1
    fi
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 40s
```

## 📝 **Code Review Guidelines**

### **Security Checklist**
- [ ] No hardcoded credentials or API keys
- [ ] Input validation for all user-provided data
- [ ] Proper error handling and logging
- [ ] File permissions set appropriately (600 for credentials)
- [ ] Path traversal protection
- [ ] Environment variable usage documented

### **Code Quality Checklist**
- [ ] Comprehensive error handling
- [ ] Meaningful log messages with context
- [ ] Consistent code formatting
- [ ] Documentation updated
- [ ] Backward compatibility maintained
- [ ] Test edge cases and error conditions

## 🎯 **Integration Points**

### **Arr Stack Integration**
- **Sonarr/Radarr/Lidarr**: Webhook integration via `import.sh`
- **Prowlarr**: Indexer management and API integration
- **Configuration**: Secure API key management

### **Media Processing Pipeline**
- **Input**: Downloads from VPN-protected clients
- **Processing**: Format conversion, metadata enhancement
- **Output**: Organized library structure with proper permissions
- **Monitoring**: Health checks and error reporting

### **Container Orchestration**
- **Dependencies**: Proper service dependency management
- **Health Monitoring**: Comprehensive health check implementation
- **Resource Management**: CPU, memory, and disk usage optimization
- **Security**: Container security contexts and isolation

## 📚 **Key Documentation References**

- **Main README.md**: User-facing documentation and setup instructions
- **DEVELOPMENT_NOTES.md**: Technical implementation details and session notes
- **scripts/LOG_MANAGEMENT.md**: Logging strategy and log rotation details
- **Security guides**: Credential management and security implementation

---

## ⚡ **Quick Reference for Common Tasks**

### **Adding a New Service**
1. Add service definition to `docker-compose.yml` with health check
2. Update `mediabox.sh` setup script for configuration
3. Add service to Homer dashboard configuration
4. Update documentation and port mappings

### **Implementing Security Features**
1. Use credential sourcing pattern from `setup-secure-env.sh`
2. Add input validation using established patterns
3. Implement comprehensive logging
4. Add error handling with meaningful messages

### **Debugging Issues**
1. Check service logs: `docker-compose logs [service-name]`
2. Verify health checks: `docker inspect [container] | grep -A 10 Health`
3. Review processing logs in `scripts/` directory
4. Validate configuration with `python3 -m json.tool mediabox_config.json`

---

*This document should be updated as the project evolves to reflect new security patterns, architectural decisions, and development standards.*
