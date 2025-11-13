# GitHub Copilot Instructions for Mediabox

## 📋 **Project Overview**

Mediabox is a security-hardened, Docker-based media aggregator stack with automated media processing capabilities. This project emphasizes **security-first architecture** with comprehensive credential management, robust error handling, and production-ready automation.

**Always reference these instructions first and fallback to search or bash commands only when you encounter unexpected information that does not match the info here.**

## 🚀 **Bootstrap and Deploy the System**

### **Prerequisites Installation**
- Install system updates: `sudo apt update && sudo apt full-upgrade`
- Install dependencies: `sudo apt install curl git bridge-utils`
- Install Docker CE: `curl -fsSL https://get.docker.com -o get-docker.sh && sudo sh get-docker.sh`
- Configure Docker: `sudo usermod -aG docker $USER`
- Load kernel module: `sudo /sbin/modprobe iptable_mangle && sudo bash -c "echo iptable_mangle >> /etc/modules"`
- **REBOOT REQUIRED**: `sudo reboot`

### **Mediabox Deployment**
- Clone repository: `git clone https://github.com/wildardoc/mediabox.git && cd mediabox/`
- **NEVER CANCEL**: Run setup: `./mediabox.sh` -- takes 5-15 minutes depending on setup complexity. Set timeout to 30+ minutes.
- **Docker image pull**: `docker compose pull` -- takes ~1 minute
- **Container startup**: `docker compose up -d` -- takes ~10 seconds
- **Container shutdown**: `docker compose down` -- takes ~7 seconds

### **System Requirements**
- **Operating System**: Ubuntu 18.04 LTS / 20.04 LTS / 22.04 LTS / 24.04 LTS (Server or Desktop)
- **VPN**: Private Internet Access (PIA) account required for torrent functionality
- **Dependencies**: Docker CE (includes Compose V2), Python3, FFmpeg (auto-installed)
- **Disk Space**: Plan for significant media storage requirements

## ✅ **CRITICAL System Validation**

After any changes, ALWAYS run these validation steps:

### **1. Container Health Check**
```bash
docker compose ps
# All containers should show "Up" status
```

### **2. Web Interface Testing**
- **Homer Dashboard**: `curl -s -o /dev/null -w "%{http_code}" http://localhost:80` (expect 200)
- **Sonarr**: `curl -s -I http://localhost:8989 | head -1` (expect 401 Unauthorized - auth required)
- **Radarr**: `curl -s -I http://localhost:7878 | head -1` (expect 401 Unauthorized - auth required)
- **Lidarr**: `curl -s -I http://localhost:8686 | head -1` (expect 401 Unauthorized - auth required)

### **3. Media Processing Validation**
```bash
cd scripts && python3 media_update.py --help
   # Should show help without errors
   ```

4. **Webhook Integration Test**:
   ```bash
   cd scripts && ./import.sh test
   # Should process without crashing (may show path errors - this is expected)
   ```

### End-to-End Validation Scenarios:
- **Setup Test**: Run `./mediabox.sh` with test credentials to validate complete deployment
- **Container Test**: Start all containers and verify web interfaces respond
- **Media Test**: Place sample media in downloads directory and test conversion scripts
- **ALWAYS verify Docker containers are accessible**: Use `docker compose logs [service]` to debug issues

## Docker Services (12 Containers)

**Core *arr Stack (Media Management)**:
- **Sonarr** (Port 8989): TV Show automation and management
- **Radarr** (Port 7878): Movie automation and management  
- **Lidarr** (Port 8686): Music automation and management
- **Prowlarr** (Port 9696): Indexer management and proxy

**Download Infrastructure**:
- **DelugeVPN**: VPN-protected BitTorrent client (requires PIA credentials)
- **NZBGet** (Port 6790): Usenet downloader

**Media & System Management**:
- **Overseerr** (Port 5055): Media request management interface
- **Maintainerr** (Port 6246): Plex library cleanup automation
- **Tautulli** (Port 8181): Plex usage statistics and monitoring
- **Homer** (Port 80): System dashboard and homepage
- **Portainer** (Ports 8000/9443): Docker container management interface
- **Plex** (Port 32400): Media server (optional Docker deployment)

## Media Processing Automation

### Smart Bulk Converter (Primary System)
**Intelligent bulk media processing with GPU acceleration and resource management:**

```bash
# Start smart converter for movies and TV (recommended)
cd scripts && ./smart-bulk-convert.sh /Storage/media/movies /Storage/media/tv

# Monitor in screen session
screen -r mediabox-converter

# View real-time logs
tail -f scripts/smart_bulk_convert_*.log
```

**Key Features:**
- **Resource-Aware**: Dynamically scales 1-5 concurrent jobs based on CPU/memory/load
- **GPU Accelerated**: Automatic VAAPI detection with software fallback
- **Multi-Directory**: Processes both movies and TV shows simultaneously
- **Power Outage Recovery**: Auto-starts on boot with cleanup
- **Orphan Detection**: Adopts existing conversion processes
- **ZFS Optimized**: Memory-aware calculations for ZFS ARC

**Configuration:** `scripts/smart_convert_config.json`
```json
{
    "max_cpu_percent": 98,
    "max_parallel_jobs": 5,
    "max_load_average": 30.0,
    "plex_priority": true,
    "download_priority": false
}
```

### Webhook Configuration (Legacy):
Configure webhooks in each *arr application (Settings → Connect → Add → Custom Script):
- **Path**: `/scripts/import.sh`
- **Triggers**: ☑ On Import, ☑ On Upgrade
- **Arguments**: (leave blank - uses environment variables)

### Processing Types:
- **TV Shows** (Sonarr): `--type video` - H.264/H.265 conversion with subtitle preservation
- **Movies** (Radarr): `--type both` - Complete audio/video/subtitle processing  
- **Music** (Lidarr): `--type audio` - FLAC/WAV/etc → MP3 320kbps conversion

### Manual Media Processing:
```bash
cd scripts
# Process directory
python3 media_update.py --dir "/path/to/media" --type video

# Process single file
python3 media_update.py --file "/path/to/file.mkv" --type both

# Audio-only conversion
python3 media_update.py --dir "/path/to/music" --type audio
```

### Boot Recovery System:
**Automatic cleanup and restart after power outages:**
```bash
# Cron jobs (auto-installed):
@reboot sleep 60 && /Storage/docker/mediabox/scripts/cleanup-on-boot.sh
@reboot sleep 120 && /Storage/docker/mediabox/scripts/start-smart-converter.sh
```

## Configuration & Maintenance

### Key Configuration Files:
- **docker-compose.yml**: Container orchestration and service definitions
- **.env**: Environment variables and system configuration (auto-generated by mediabox.sh)
- **scripts/mediabox_config.json**: Media processing configuration (auto-generated)
- **scripts/requirements.txt**: Python dependencies (ffmpeg-python==0.2.0, future==1.0.0)

### Automated Maintenance:
- **Log Rotation**: Weekly on Sundays at 2 AM (95% space savings)
- **Media Cleanup**: Weekly on Mondays at 3 AM (removes duplicates/old files)
- **Dependency Installation**: Auto-installs Python packages in containers

### Manual Maintenance Commands:
```bash
cd scripts
# Log rotation
./rotate-logs.sh

# Media cleanup (dry run first)
python3 remove_files.py --dry-run
python3 remove_files.py

# View logs  
cat import_$(date +%Y%m%d).log
cat media_update_*.log
zcat media_update_*.log.gz | less
```

## Troubleshooting

### Common Issues:
- **Container fails to start**: Check `docker compose logs [service]` for specific errors
- **Web interface not accessible**: Verify container is "Up" with `docker compose ps`
- **Media processing errors**: Check `scripts/media_update_*.log` for FFmpeg errors
- **Webhook failures**: Check `scripts/import_*.log` for integration issues
- **VPN connection issues**: Verify PIA credentials in secure environment file

### Debugging Commands:
```bash
# Container status
docker compose ps

# Service logs
docker compose logs sonarr
docker compose logs radarr

# Restart specific service
docker compose restart sonarr

# Complete system restart
docker compose down && docker compose up -d
```

## Performance & Timing Expectations

### CRITICAL - NEVER CANCEL Operations:
- **Initial Setup**: `./mediabox.sh` takes 5-15 minutes - NEVER CANCEL, set timeout to 30+ minutes
- **Docker Image Pull**: `docker compose pull` takes ~1 minute - Set timeout to 5+ minutes  
- **Container Startup**: `docker compose up -d` takes ~10 seconds - Set timeout to 2+ minutes
- **Container Shutdown**: `docker compose down` takes ~7 seconds - Set timeout to 1+ minute
- **Media Processing**: Variable based on file size - Large files may take 30+ minutes

### Expected Response Times:
- **Web Interfaces**: Should respond within 1-2 seconds after container initialization
- **Container Health**: Allow 10-30 seconds for services to fully initialize
- **Media Conversion**: 1-5x real-time depending on source format and system performance
- **Smart Converter Queue Building**: 3-5 minutes for 700+ movie directories
- **GPU Detection**: Hardware acceleration test takes 10-15 seconds

## Security & Credentials

### Credential Management:
- **Location**: Credentials stored in `~/.mediabox/credentials.env` (user-only access)
- **Setup**: Run `./scripts/setup-secure-env.sh` for credential configuration
- **Required**: PIA VPN username/password, daemon passwords for services

### Important Security Notes:
- **Never commit credentials**: Project uses secure external credential sourcing
- **File permissions**: Credential file automatically set to 600 (user-only)
- **VPN requirement**: Torrent functionality requires active PIA VPN connection

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

## Common Tasks Reference

### Repository Structure:
```
mediabox/
├── .github/
│   └── copilot-instructions.md     # This file
├── mediabox.sh                 # Main setup script (ENTRY POINT)
├── docker-compose.yml         # Container definitions (12 services)
├── .env                       # Environment configuration (auto-generated)
├── scripts/                   # Automation directory
│   ├── import.sh             # Webhook handler for *arr integration
│   ├── media_update.py       # Core media processing engine
│   ├── remove_files.py       # Media cleanup automation
│   ├── rotate-logs.sh        # Log management system
│   ├── setup-secure-env.sh        # Credential management
│   ├── requirements.txt      # Python dependencies
│   └── mediabox_config.json  # Processing configuration
└── content/                  # Media storage directories
    ├── tv/                   # TV show library
    ├── movies/               # Movie library  
    ├── music/                # Music library
    └── misc/                 # Miscellaneous media
```

### Quick Status Commands:
```bash
# System overview
docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"

# Service health
curl -s -o /dev/null -w "Homer: %{http_code}\n" http://localhost:80

# Log overview
ls -la scripts/*.log scripts/*.log.gz | tail -10

# Disk usage
du -sh content/*/ scripts/
```

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

## 🧪 **AI-Assisted Development Best Practices**

This project is built almost entirely using AI assistance. These guidelines ensure quality and maintainability:

### **1. Preserve Fixes with Triple Documentation**

When fixing bugs or implementing critical features, ALWAYS create three layers of protection:

```bash
# Layer 1: Inline Code Comments (explains "why" at the exact line)
if 'channel_layout' in stream:  # IMPORTANT: Check key existence, not value
    # Missing field (None) is different from "unknown" string

# Layer 2: Git Commit with Detailed Message
git commit -m "Fix: Audio processing for 6-channel files with missing channel_layout

Root Cause:
- Files from streaming services often lack channel_layout field entirely
- Detection only checked for 'unknown' value, missed None/missing cases
- FFmpeg filter outputs consumed before being mapped

Solution:
- Check key existence with 'in' operator instead of .get()
- Use asplit to branch channelmap output for dual use
- Updated syntax from :5.1 to :channel_layout=5.1

Affected Files: Disney+, Apple TV+, Amazon Prime downloads
Testing: Verified with Luca (2021) WEBDL-2160p.mp4"

# Layer 3: Reference Documentation (project-level explanation)
# Create FEATURE_NAME_FIX.md or ISSUE_XX_RESOLUTION.md
```

**Why Triple Documentation?**
- **Inline comments**: Future AI sees context when editing nearby code
- **Git history**: Explains "what changed and why" for debugging regressions
- **Reference docs**: Provides searchable context for similar issues

### **2. Test FFmpeg Commands Manually First**

Before implementing complex FFmpeg filter chains, validate them manually:

```bash
# ❌ DON'T: Implement untested filter chain directly in script
video_filters.append('channelmap=...,pan=...')  # Hope it works

# ✅ DO: Test command manually with actual problematic file
ffmpeg -i "Luca (2021).mp4" \
  -filter_complex "[0:a:0]channelmap=0-FL|1-FR|2-FC|3-LFE|4-BL|5-BR:channel_layout=5.1,asplit=2[fixed][stereo]; \
                   [stereo]pan=stereo|c0=...|c1=...[out]" \
  -map "[fixed]" -map "[out]" test_output.mp4

# If successful, THEN implement in script
```

**Benefits:**
- Identifies syntax errors immediately
- Tests with actual problematic files
- Validates filter output before committing code

### **3. Handle Missing vs Empty vs Unknown Values**

Python dictionaries and ffprobe JSON require careful distinction:

```python
# ❌ INCORRECT - Misses truly missing fields
channel_layout = stream.get('channel_layout', 'unknown')
if channel_layout == 'unknown':  # Misses None/missing cases

# ✅ CORRECT - Handles all three cases
has_layout = 'channel_layout' in stream
channel_layout = stream.get('channel_layout', '') if has_layout else None

if channel_layout is None:      # Field completely missing
    needs_fix = True
elif channel_layout == 'unknown':  # Field present but unknown value
    needs_fix = True
elif channel_layout == '':      # Field present but empty string
    needs_fix = True
```

**Real-World Example:**
- **Disney+ downloads**: `channel_layout` key missing entirely → `None`
- **Old rips**: `channel_layout: "unknown"` → string value
- **Corrupted metadata**: `channel_layout: ""` → empty string

### **4. FFmpeg Filter Graph Rules**

Critical rules when chaining filters (learned from audio processing bugs):

```bash
# RULE 1: Filter outputs are consumed when used
[input]filter1[output1]; [output1]filter2[final]  # output1 consumed, unavailable

# RULE 2: Use asplit for dual usage
[input]filter1,asplit=2[branch1][branch2]; [branch1]...; [branch2]...

# RULE 3: Always specify full filter parameters
channelmap=:5.1                           # ❌ Incomplete syntax
channelmap=0-FL|1-FR|...:channel_layout=5.1  # ✅ Explicit and complete

# RULE 4: Use audio-relative stream specifiers
[0:1]  # ❌ Absolute index (breaks with subtitle streams)
[0:a:0]  # ✅ First audio stream (works regardless of stream order)
```

### **5. Debugging Workflow for AI Sessions**

When AI encounters failures, follow this systematic approach:

```bash
# Step 1: Get exact error message (not truncated)
python3 media_update.py --file "problem.mp4" 2>&1 | tee full_error.log

# Step 2: Identify the failing FFmpeg command
grep "ffmpeg -i" full_error.log

# Step 3: Extract and test manually
# Copy the exact command and run it directly

# Step 4: Simplify progressively
# Remove filters one-by-one until it works, then add back

# Step 5: Compare working vs failing
diff <(echo "$working_command") <(echo "$failing_command")
```

**AI Guidance:**
- Show full error output (not "similar errors")
- Test hypotheses with actual commands before code changes
- Validate fixes work before committing

### **6. Preserve AI Context Between Sessions**

Create reference documents that survive conversation resets:

```markdown
# AUDIO_CHANNELMAP_FIX.md

## Problem
Files with 6-channel audio but missing `channel_layout` field fail...

## Solution  
[Exact code snippets and FFmpeg commands]

## Testing
[Command to identify affected files]

## DO NOT REVERT
[Explain why this fix is critical]
```

**Benefits:**
- Future AI sessions can read these docs
- Prevents re-implementing the same bugs
- Provides searchable project knowledge base

### **7. Log Everything for Post-Mortem Analysis**

```python
# Add context-rich logging at decision points
logging.info(f"Channel layout detection: has_key={has_layout}, "
             f"value={channel_layout}, channels={channels}")

if needs_channelmap_fix:
    logging.info(f"Applying channelmap fix: missing channel_layout "
                 f"on {channels}-channel stream")
```

**Why:**
- Logs reveal what AI's code actually detected
- Helps diagnose false positives/negatives
- Provides data for improving detection logic

### **8. Version Control Best Practices for AI Projects**

```bash
# Commit frequently with descriptive messages
git commit -m "WIP: Testing channelmap with asplit approach"

# Tag working states
git tag -a v1.5-audio-fix -m "Working fix for missing channel_layout"

# Use branches for experiments
git checkout -b experiment/alternative-audio-fix

# Document failed approaches
git commit --allow-empty -m "Attempted: pan without asplit (fails with 'output not found')"
```

**Rationale:**
- AI can't remember previous attempts across sessions
- Git history becomes the "project memory"
- Easy rollback when AI suggests breaking changes

## 🎓 **Lessons from Real Bugs**

### **Case Study: Missing channel_layout Audio Processing**

**Issue**: Luca (2021) and other streaming downloads failed with "Output with label 'fixed_surround' does not exist"

**Root Causes Discovered:**
1. **Assumption failure**: Assumed ffprobe always includes `channel_layout` field
2. **Detection logic**: Only checked for `'unknown'` value, missed `None` (missing key)
3. **Filter consumption**: FFmpeg pan filter consumed `[fixed_surround]` output, making it unavailable for mapping
4. **Syntax error**: Used `:5.1` instead of proper `:channel_layout=5.1`

**AI Development Challenges:**
- Initial fixes addressed symptoms, not root cause
- Required 3 iterations to identify all issues
- Manual FFmpeg testing revealed the asplit requirement

**Final Solution:**
```python
# Detection: Check if key exists
has_layout = 'channel_layout' in stream
needs_fix = not has_layout or channel_layout in ['unknown', '']

# Branching: Use asplit for dual usage
channelmap_filter = f'channelmap=...:channel_layout=5.1,asplit=2[fixed][stereo]'

# Routing: Use different branches
# [fixed] → direct output mapping
# [stereo] → input to pan filter
```

**Documentation Created:**
- Inline comments at Lines 1416, 1433, 1479 (code context)
- Git commit 9dfa54d (change history)
- AUDIO_CHANNELMAP_FIX.md (reference guide)

**Key Takeaway**: One comprehensive fix with triple documentation prevents future AI from reintroducing the bug.

### **When to Update AI Instructions**

Update `.github/copilot-instructions.md` when:
- [ ] Critical bug pattern discovered (like missing vs unknown values)
- [ ] New security vulnerability found and fixed
- [ ] Complex debugging required multiple AI iterations
- [ ] Solution contradicts previous assumptions
- [ ] Common mistake that could happen again

**Update Process:**
1. Document the issue thoroughly
2. Add to AI instructions with code examples
3. Commit with clear explanation
4. Reference in related code comments

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
1. Check service logs: `docker compose logs [service-name]`
2. Verify health checks: `docker inspect [container] | grep -A 10 Health`
3. Review processing logs in `scripts/` directory
4. Validate configuration with `python3 -m json.tool mediabox_config.json`

This system provides enterprise-grade automated media processing with comprehensive error handling, logging, and maintenance automation. Always test changes in a non-production environment first.

---

*This document should be updated as the project evolves to reflect new security patterns, architectural decisions, and development standards.*
