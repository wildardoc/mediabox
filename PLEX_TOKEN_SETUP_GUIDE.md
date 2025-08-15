# Plex Token Setup Guide

## Overview

This guide explains how to set up Plex authentication tokens for the Mediabox media processing workflow optimization. The optimization ensures that Plex only processes final transcoded files instead of original downloads.

## ✅ Current Status (Your Setup)

Your system is **already configured and working**:
- **Plex Server**: Schaefer Media (v1.42.1.10060)
- **Token**: K22ZgfFgyK... (configured in `.env`)
- **Libraries**: Movies, TV Shows, Music, Photos
- **PlexAPI**: Installed and functional

## 🎯 Workflow Optimization

### Before Optimization:
```
Download → *arr notifies Plex immediately → Transcode runs → Duplicates/Conflicts
```

### After Optimization:
```
Download → Transcode completes → media_update.py notifies Plex → Clean library
```

## 🔧 Token Retrieval Methods

### Method 1: Interactive Setup (New Installations - RECOMMENDED)
For fresh Mediabox installations, use the fully interactive setup:

```bash
# Interactive mode - prompts for everything
python3 scripts/get-plex-token.py --interactive

# Example session:
# 🎬 Plex Token Retrieval
# ==============================
# 1. Testing connection to: http://localhost:32400
# ❌ Connection failed: Authentication required or invalid token
# ℹ️  Server requires authentication - you'll need MyPlex credentials
# 
# 2. MyPlex Account Setup
# =========================
# To retrieve a Plex token, you need your MyPlex account credentials.
# These are the same credentials you use to sign in at plex.tv
# 
# MyPlex username (email): your-email@example.com
# MyPlex password for your-email@example.com: [hidden]
# 
# 3. Retrieving authentication token...
# 🔐 Authenticating with MyPlex account: your-email@example.com
# ✅ MyPlex authentication successful
# 🔑 Retrieved authentication token: K22ZgfFgyK...
# 🔗 Testing token with local Plex server...
# ✅ Token retrieved successfully!
#    Method: Retrieved via MyPlex account (Your Plex Server)
# 
# 4. Validating token...
# ✅ Token validation successful
# 
# 🎯 Configuration for your .env file:
# ==================================================
# PLEX_URL=http://localhost:32400
# PLEX_TOKEN=K22ZgfFgyKVyxgtXY_6u
# ==================================================
# 
# 💡 Copy the lines above to your .env file
```

### Method 2: Command Line Setup
For automated or scripted installations:

```bash
# With username (will prompt for password)
python3 scripts/get-plex-token.py --interactive --username your-email@example.com

# Test connection first
python3 scripts/get-plex-token.py --test-only --url http://your-server:32400
```

### Method 3: Use Existing Token (Your Current Setup)
If you already have a working Plex setup (like you do), verify it works:

```bash
# Verify existing configuration
./scripts/setup-plex-notifications.sh
```

**Your current configuration**:
- `PLEX_URL=http://localhost:32400` 
- `PLEX_TOKEN=K22ZgfFgyKVyxgtXY_6u` ✅ Working

### Method 4: Manual Token Retrieval (Fallback)
1. Open Plex Web UI: http://your-server:32400/web
2. Sign in to your Plex account
3. Open browser developer tools (F12)
4. Look for `X-Plex-Token` in network requests
5. Or visit: https://support.plex.tv/articles/204059436-finding-an-authentication-token-x-plex-token/

## 🧪 Testing

### Test Existing Configuration:
```bash
cd /Storage/docker/mediabox/scripts
python3 test-plex-comprehensive.py
```

**Expected output**:
- ✅ Existing Token: Working  
- ✅ PlexAPI Integration: Working
- ✅ Library sections detected
- ✅ Server connection successful

### Test Notification System:
```bash
python3 test-plex-notification.py
```

**Expected output**:
- ✅ TV notification successful
- ✅ Movie notification successful  
- ✅ Music notification successful

### Demo Interactive Setup Process:
```bash
# Safe simulation of interactive setup
python3 demo-interactive-safe.py

# Complete setup demonstration
./demo-complete-setup.sh
```

### Test Real Interactive Mode (Safe):
```bash
# Test with invalid credentials (demonstrates error handling)
python3 get-plex-token.py --interactive --url http://localhost:32400
# Enter test credentials - shows proper error handling
```

## 📋 Configuration Files

### `.env` (Auto-configured)
```bash
PLEX_URL=http://localhost:32400
PLEX_TOKEN=your_token_here
```

### `requirements.txt` (Updated)
```
ffmpeg-python==0.2.0
future==1.0.0
PlexAPI==4.15.8
requests==2.31.0
```

## 🔄 Integration Points

### 1. Media Processing (`media_update.py`)
- Automatically detects Plex configuration from `.env`
- Uses PlexAPI for reliable library updates
- Matches file paths to correct library sections
- Logs all notification attempts

### 2. Webhook Integration (`import.sh`)
- Triggers `media_update.py` after download completion
- `media_update.py` handles Plex notification after transcoding
- No changes needed - existing webhook continues to work

### 3. *arr Application Changes (Manual)
To complete the optimization, disable immediate Plex notifications:

**Sonarr** (http://localhost:8989):
- Settings → Connect → Find "Plex Media Server" connections
- Disable "On Import/Upgrade" notifications
- Keep "Mediabox Processing" webhook enabled

**Radarr** (http://localhost:7878):
- Settings → Connect → Find "Plex Media Server" connections  
- Disable "On Import/Upgrade" notifications
- Keep "Mediabox Processing" webhook enabled

**Lidarr** (http://localhost:8686):
- Settings → Connect → Find "Plex Media Server" connections
- Disable "On Import/Upgrade" notifications
- Keep "Mediabox Processing" webhook enabled

## 🚀 Production Workflow

### Normal Operation:
1. **Download completes** → Sonarr/Radarr/Lidarr webhook triggers
2. **`import.sh` calls `media_update.py`** → Transcoding begins
3. **Transcoding completes** → `media_update.py` notifies Plex automatically
4. **Plex scans** → Only sees final optimized files

### Benefits:
- ✅ No duplicate library entries
- ✅ No processing conflicts
- ✅ Optimized files only
- ✅ Automatic library updates
- ✅ Reduced Plex server load

## 🔍 Troubleshooting

### Token Issues:
```bash
# Validate current token
curl -s "http://localhost:32400/library/sections?X-Plex-Token=YOUR_TOKEN"
```

### Connection Issues:
```bash
# Test server accessibility
python3 scripts/get-plex-token.py --test-only --url http://localhost:32400
```

### Library Update Issues:
```bash
# Check Plex logs
tail -f plex/Library/Application\ Support/Plex\ Media\ Server/Logs/Plex\ Media\ Server.log
```

## ✨ Your Setup is Ready!

Your Mediabox system already has everything configured correctly:
- ✅ Valid Plex token
- ✅ PlexAPI integration working
- ✅ Library sections detected
- ✅ Notification system tested

**Next step**: Configure *arr applications to disable immediate Plex notifications, then enjoy the optimized workflow!
