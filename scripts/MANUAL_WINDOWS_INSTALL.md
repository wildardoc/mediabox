# Manual Installation Guide for Windows 11

If the automated installer fails, follow these steps for manual installation:

## Step 1: Install Prerequisites

### Install Python 3.12
```powershell
# Open PowerShell as Administrator and run:
winget install Python.Python.3.12

# IMPORTANT: Close and reopen PowerShell after installation!
# The PATH changes won't take effect in the current session.
```

**After installation completes:**
1. Close your current PowerShell window
2. Open a **new** PowerShell window (regular user - no admin needed)
3. Continue with the verification step below

### Install FFmpeg
```powershell
# Option A: Using winget
winget install Gyan.FFmpeg

# Option B: Using Chocolatey (if installed)
choco install ffmpeg -y

# IMPORTANT: Close and reopen PowerShell after installation!
```

### Verify Installations
```powershell
# IN A NEW POWERSHELL WINDOW, verify:
python --version
# Should show: Python 3.12.x

ffmpeg -version
# Should show: ffmpeg version...
```

**If "python is not recognized":**
1. Make sure you closed and reopened PowerShell after installation
2. If still not found, manually refresh the PATH:
   ```powershell
   $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
   python --version
   ```
3. If still not working, restart your computer

## Step 2: Create Installation Directory

```powershell
# Run in REGULAR PowerShell (no admin needed):
$InstallDir = "$env:LOCALAPPDATA\mediabox-converter"
New-Item -ItemType Directory -Force -Path $InstallDir
cd $InstallDir
```

## Step 3: Create Python Virtual Environment

```powershell
# Create virtual environment
python -m venv .venv

# Activate it
.\.venv\Scripts\Activate.ps1

# Upgrade pip
python -m pip install --upgrade pip setuptools wheel
```

## Step 4: Install Python Dependencies

```powershell
# Still in the virtual environment, install packages:
pip install ffmpeg-python==0.2.0
pip install future==1.0.0
pip install PlexAPI==4.15.8
pip install requests==2.31.0
```

## Step 5: Copy Script Files

```powershell
# Copy the main script
Copy-Item "C:\Users\wilda\mediabox\scripts\media_update.py" $InstallDir

# Copy database tools (optional but recommended)
Copy-Item "C:\Users\wilda\mediabox\scripts\media_database.py" $InstallDir
Copy-Item "C:\Users\wilda\mediabox\scripts\build_media_database.py" $InstallDir
Copy-Item "C:\Users\wilda\mediabox\scripts\query_media_database.py" $InstallDir

# Copy requirements
Copy-Item "C:\Users\wilda\mediabox\scripts\requirements.txt" $InstallDir
```

## Step 6: Create Configuration File

```powershell
# Create config file
$config = @'
{
  "venv_path": "C:\\Users\\wilda\\AppData\\Local\\mediabox-converter\\.venv",
  "env_file": "C:\\Users\\wilda\\AppData\\Local\\mediabox-converter\\.env",
  "download_dirs": [],
  "library_dirs": {
    "tv": "",
    "movies": "",
    "music": "",
    "misc": ""
  },
  "container_support": false,
  "plex_integration": {
    "url": "",
    "token": "",
    "path_mappings": {
      "tv": "",
      "movies": "",
      "music": ""
    }
  },
  "transcoding": {
    "video": {
      "codec": "libx264",
      "crf": 23,
      "audio_codec": "aac"
    },
    "audio": {
      "codec": "libmp3lame",
      "bitrate": "320k"
    }
  },
  "gpu_type": "auto"
}
'@

$config | Out-File -FilePath "$InstallDir\mediabox_config.json" -Encoding UTF8
```

## Step 7: Create Wrapper Script

```powershell
# Create the batch wrapper
$wrapper = @'
@echo off
REM Mediabox Media Converter Wrapper

set INSTALL_DIR=%LOCALAPPDATA%\mediabox-converter
set VENV_PYTHON=%INSTALL_DIR%\.venv\Scripts\python.exe

if not exist "%VENV_PYTHON%" (
    echo ERROR: Virtual environment not found
    echo Please check installation at %INSTALL_DIR%
    exit /b 1
)

REM Run media_update.py with all arguments
"%VENV_PYTHON%" "%INSTALL_DIR%\media_update.py" %*
'@

$wrapper | Out-File -FilePath "$InstallDir\media-converter.bat" -Encoding ASCII
```

## Step 8: Add to PATH

```powershell
# Get current user PATH
$userPath = [System.Environment]::GetEnvironmentVariable('Path', 'User')

# Check if already in PATH
if ($userPath -notlike "*$InstallDir*") {
    # Add to PATH
    $newPath = $userPath + ';' + $InstallDir
    [System.Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
    Write-Host "Added to PATH successfully!"
    Write-Host "Please restart your terminal for changes to take effect."
} else {
    Write-Host "Already in PATH!"
}
```

## Step 9: Test Installation

```powershell
# Close and reopen PowerShell/Terminal, then test:
media-converter --help
```

You should see the help output from media_update.py!

## Usage Examples

### Process a single file
```cmd
media-converter --file "C:\Media\video.mkv" --type video
```

### Process entire directory
```cmd
media-converter --dir "C:\Media\Movies" --type both
```

### HDR tone mapping
```cmd
media-converter --file "C:\Media\4k-movie.mkv" --type video --downgrade-resolution
```

### Network share
```cmd
# First map the drive
net use Z: \\server\media /persistent:yes

# Then process
media-converter --dir "Z:\movies" --type video
```

## Troubleshooting

### "media-converter not found"
Use the full path:
```cmd
%LOCALAPPDATA%\mediabox-converter\media-converter.bat --help
```

### Python/FFmpeg not found
Make sure they're installed and in your PATH:
```powershell
python --version
ffmpeg -version
```

### Permission errors
Run PowerShell as Administrator for the installation steps.

### Virtual environment activation fails
Try changing execution policy:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

## Uninstall

```powershell
# Remove installation directory
Remove-Item -Recurse -Force "$env:LOCALAPPDATA\mediabox-converter"

# Remove from PATH manually:
# Press Win+R → sysdm.cpl → Advanced → Environment Variables
# Edit User PATH and remove the mediabox-converter entry
```

---

**That's it!** Your media converter is now installed and ready to use.
