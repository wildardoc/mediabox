# Plex Integration Setup Guide

This guide covers the Plex integration features in Mediabox, including automatic token retrieval and library update notifications.

## 🎯 Overview

Mediabox includes comprehensive Plex integration that automatically:
- Retrieves authentication tokens using your MyPlex account
- Configures library update notifications after media processing  
- Stores credentials securely with no manual token management
- Updates only the specific library sections that changed

## 🚀 Automatic Setup (Recommended)

### During Initial Installation

When running `./mediabox.sh`, you'll see:

```
🎬 Configure Plex Integration
==================================
To enable automatic library updates after media processing,
enter your Plex/MyPlex account details (optional - skip with Enter):

MyPlex Username (email): your_email@example.com
MyPlex Password: [hidden]
```

**What happens next:**
1. Credentials stored securely in `~/.mediabox/credentials.env` 
2. System waits for Plex container to be ready
3. Automatically retrieves authentication token
4. Configures `.env` file with `PLEX_TOKEN` and `PLEX_URL`
5. Enables automatic library notifications

### Benefits
- ✅ **Zero Manual Configuration** - No token retrieval needed
- ✅ **Secure Storage** - Credentials never stored in code
- ✅ **Special Character Safe** - Handles complex passwords correctly
- ✅ **Automatic Updates** - Libraries refresh after processing

## 🛠️ Manual Setup Options

### Option 1: Interactive Token Retrieval

```bash
cd scripts
python3 get-plex-token.py --interactive
```

**Process:**
1. Enter MyPlex username and password
2. Script connects to MyPlex account
3. Retrieves authentication token
4. Validates token against your Plex server
5. Updates `.env` file automatically

### Option 2: Update Existing Credentials

```bash
cd scripts  
./setup-secure-env.sh
```

**Features:**
- Preserves existing credentials (press Enter to keep)
- Add/update/remove Plex credentials
- Secure file permissions (600 - user-only access)
- Validates credential format

## 🔐 Security Features

### Credential Storage
- **Location**: `~/.mediabox/credentials.env`
- **Permissions**: 600 (user-only read/write)
- **Format**: Simple KEY=value pairs
- **Backup**: Automatic backup before changes

### Special Character Handling
The integration uses **file-based credential reading** instead of environment variables, which:
- ✅ Handles passwords with `&`, `!`, `$`, and other special characters
- ✅ Prevents shell escaping issues
- ✅ Maintains security through file permissions
- ✅ Ensures reliable token retrieval

## 📋 Configuration Files

### `.env` File Structure
After successful setup, your `.env` file will include:
```bash
PLEX_URL=http://localhost:32400
PLEX_TOKEN=your_retrieved_token_here
```

### Credential File Format
The secure credential file contains:
```bash
# Mediabox Secure Credentials
PIAUNAME=your_pia_username
PIAPASS=your_pia_password
CPDAEMONUN=your_daemon_username
CPDAEMONPASS=your_daemon_password
PLEX_USERNAME=your_plex_username
PLEX_PASSWORD=your_plex_password
```

## ⚙️ How Library Updates Work

### Automatic Process
1. **Media Download** - Sonarr/Radarr downloads content
2. **Webhook Trigger** - *arr app calls `scripts/import.sh`
3. **Media Processing** - `scripts/media_update.py` transcodes/processes
4. **Library Detection** - Script identifies appropriate Plex library section
5. **Targeted Update** - Only refreshes the specific section (TV/Movies/Music)

### Configuration in *arr Apps
Webhooks are configured in each *arr application:
- **Path**: `/scripts/import.sh`
- **Triggers**: ☑ On Import, ☑ On Upgrade  
- **Arguments**: (leave blank - uses environment variables)

## 🔧 Troubleshooting

### Token Retrieval Issues

**Problem**: Automatic token retrieval fails during setup
```bash
❌ Failed to retrieve Plex token automatically

📋 To configure Plex later, run:
   cd /path/to/mediabox/scripts
   python3 get-plex-token.py --interactive
```

**Solutions:**
1. Check MyPlex credentials are correct
2. Ensure Plex server is running and accessible
3. Verify network connectivity to plex.tv
4. Run manual setup with `--interactive` mode

### Authentication Problems

**Problem**: Token exists but library updates fail
```bash
# Test token validity
curl "http://localhost:32400/identity?X-Plex-Token=YOUR_TOKEN"
```

**Expected Response**: XML with server information
**Fix**: Re-run token retrieval if invalid

### Credential Updates

**Problem**: Need to change MyPlex password or username
```bash
cd scripts
./setup-secure-env.sh
```

**Process:**
- Shows existing values: `MyPlex username (current: user@example.com):`
- Press Enter to keep existing, or type new value
- Type `REMOVE` to delete Plex credentials completely

## 📊 Validation Commands

### Check Integration Status
```bash
# Verify containers running  
docker-compose ps plex

# Test Plex connectivity
curl -s "http://localhost:32400/identity?X-Plex-Token=$(grep PLEX_TOKEN .env | cut -d= -f2)"

# Check library sections
curl -s "http://localhost:32400/library/sections?X-Plex-Token=$(grep PLEX_TOKEN .env | cut -d= -f2)"
```

### Log Monitoring
```bash
# Webhook activity
tail -f scripts/import_$(date +%Y%m%d).log

# Media processing  
tail -f scripts/media_update_$(date +%Y%m%d).log

# Plex container logs
docker-compose logs plex
```

## 🎉 Success Indicators

When everything is working correctly:
- ✅ `.env` contains valid `PLEX_TOKEN` and `PLEX_URL`
- ✅ Credential file has proper permissions (600)
- ✅ Token validates against Plex server
- ✅ Library sections are accessible
- ✅ Media processing triggers library updates
- ✅ Plex shows "Recently Added" items after processing

## 📞 Support

If you encounter issues:
1. Check the troubleshooting section above
2. Review log files for error messages
3. Validate all configuration files exist and have correct permissions
4. Test token and connectivity manually using curl commands
5. Consider re-running the setup process with fresh credentials

---

*This integration makes Plex library management completely automated - no manual refreshing needed after media downloads!*
