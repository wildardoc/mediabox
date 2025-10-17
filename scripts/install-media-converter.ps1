#Requires -Version 5.1
<#
.SYNOPSIS
    Mediabox Standalone Media Converter Installation Script for Windows

.DESCRIPTION
    This script installs the media_update.py conversion tools on Windows 11 systems.
    Ideal for dedicated conversion workstations with powerful hardware (NVIDIA GPUs, high-end CPUs).

.PARAMETER GpuType
    Specify GPU acceleration type. Values: auto, nvidia, intel, none. Default: auto (auto-detect)

.PARAMETER InstallDir
    Installation directory. Default: $env:LOCALAPPDATA\mediabox-converter

.EXAMPLE
    .\install-media-converter.ps1
    Auto-detect GPU and install with defaults

.EXAMPLE
    .\install-media-converter.ps1 -GpuType nvidia
    Force NVIDIA GPU support

.EXAMPLE
    .\install-media-converter.ps1 -GpuType none
    Software encoding only (no GPU)
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet('auto', 'nvidia', 'intel', 'none')]
    [string]$GpuType = 'auto',

    [Parameter()]
    [string]$InstallDir = "$env:LOCALAPPDATA\mediabox-converter"
)

$ErrorActionPreference = 'Stop'

# Colors for output
$Colors = @{
    Info = 'Cyan'
    Success = 'Green'
    Warning = 'Yellow'
    Error = 'Red'
}

function Write-Status {
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        
        [Parameter()]
        [ValidateSet('Info', 'Success', 'Warning', 'Error')]
        [string]$Type = 'Info'
    )
    
    $prefix = switch ($Type) {
        'Info' { '[INFO]' }
        'Success' { '[SUCCESS]' }
        'Warning' { '[WARNING]' }
        'Error' { '[ERROR]' }
    }
    
    Write-Host "$prefix " -ForegroundColor $Colors[$Type] -NoNewline
    Write-Host $Message
}

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Banner
Write-Host ""
Write-Host "╔═══════════════════════════════════════════════════════════╗"
Write-Host "║                                                           ║"
Write-Host "║     Mediabox Standalone Media Converter Installer         ║"
Write-Host "║                  Windows 11 Edition                       ║"
Write-Host "║                                                           ║"
Write-Host "║  Install media_update.py conversion tools on Windows      ║"
Write-Host "║  Optimized for dedicated conversion workstations          ║"
Write-Host "║                                                           ║"
Write-Host "╚═══════════════════════════════════════════════════════════╝"
Write-Host ""

# Check for administrator privileges (needed for Chocolatey)
if (Test-Administrator) {
    Write-Status "Running with administrator privileges" -Type Success
} else {
    Write-Status "Not running as administrator. Will try to install without admin rights." -Type Warning
    Write-Status "If installation fails, please run PowerShell as Administrator." -Type Warning
}

# System requirements check
Write-Status "Checking system requirements..." -Type Info

# Check OS version (Windows 10 1809+ or Windows 11)
$osVersion = [System.Environment]::OSVersion.Version
if ($osVersion.Major -lt 10) {
    Write-Status "Windows 10 (1809+) or Windows 11 required. Found: Windows $($osVersion.Major).$($osVersion.Minor)" -Type Error
    exit 1
}
Write-Status "Windows version: $($osVersion.Major).$($osVersion.Minor).$($osVersion.Build)" -Type Success

# Check for Python 3.8+
Write-Status "Checking for Python..." -Type Info
$pythonCmd = $null

# Try common Python commands
$pythonCommands = @('python', 'python3', 'py')
foreach ($cmd in $pythonCommands) {
    try {
        $version = & $cmd --version 2>&1 | Out-String
        if ($version -match 'Python (\d+)\.(\d+)\.(\d+)') {
            $major = [int]$matches[1]
            $minor = [int]$matches[2]
            
            if ($major -eq 3 -and $minor -ge 8) {
                $pythonCmd = $cmd
                Write-Status "Python $major.$minor detected using '$cmd'" -Type Success
                break
            }
        }
    } catch {
        # Command not found, continue
    }
}

if (-not $pythonCmd) {
    Write-Status "Python 3.8+ not found. Installing via winget..." -Type Warning
    
    try {
        # Try installing via winget (Windows Package Manager)
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            Write-Status "Installing Python 3.12 via winget..." -Type Info
            winget install Python.Python.3.12 --silent --accept-source-agreements --accept-package-agreements
            
            # Refresh PATH
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
            
            # Check again
            $pythonCmd = 'python'
            $version = & $pythonCmd --version 2>&1 | Out-String
            if ($version -match 'Python (\d+)\.(\d+)') {
                Write-Status "Python installed successfully" -Type Success
            } else {
                throw "Python installation verification failed"
            }
        } else {
            Write-Status "winget not available. Please install Python manually from python.org" -Type Error
            Write-Status "Download: https://www.python.org/downloads/" -Type Info
            exit 1
        }
    } catch {
        Write-Status "Failed to install Python automatically" -Type Error
        Write-Status "Please install Python 3.8+ from: https://www.python.org/downloads/" -Type Error
        Write-Status "Make sure to check 'Add Python to PATH' during installation" -Type Warning
        exit 1
    }
}

# Check for pip
Write-Status "Checking for pip..." -Type Info
try {
    & $pythonCmd -m pip --version | Out-Null
    Write-Status "pip is available" -Type Success
} catch {
    Write-Status "pip not found. Installing..." -Type Warning
    & $pythonCmd -m ensurepip --upgrade
}

# Check for FFmpeg
Write-Status "Checking for FFmpeg..." -Type Info
$ffmpegInstalled = $false
try {
    $ffmpegVersion = & ffmpeg -version 2>&1 | Select-Object -First 1
    if ($ffmpegVersion -match 'ffmpeg version') {
        Write-Status "FFmpeg detected: $ffmpegVersion" -Type Success
        $ffmpegInstalled = $true
    }
} catch {
    # FFmpeg not found
}

if (-not $ffmpegInstalled) {
    Write-Status "FFmpeg not found. Attempting to install..." -Type Warning
    
    # Try Chocolatey first
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        Write-Status "Installing FFmpeg via Chocolatey..." -Type Info
        try {
            choco install ffmpeg -y
            $ffmpegInstalled = $true
            Write-Status "FFmpeg installed via Chocolatey" -Type Success
        } catch {
            Write-Status "Chocolatey installation failed" -Type Warning
        }
    }
    
    # Try winget if Chocolatey failed
    if (-not $ffmpegInstalled -and (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Status "Installing FFmpeg via winget..." -Type Info
        try {
            winget install Gyan.FFmpeg --silent --accept-source-agreements --accept-package-agreements
            $ffmpegInstalled = $true
            Write-Status "FFmpeg installed via winget" -Type Success
        } catch {
            Write-Status "winget installation failed" -Type Warning
        }
    }
    
    if (-not $ffmpegInstalled) {
        Write-Status "Could not install FFmpeg automatically" -Type Warning
        Write-Status "Please install FFmpeg manually from: https://www.gyan.dev/ffmpeg/builds/" -Type Warning
        Write-Status "Download the 'release essentials' build and add to PATH" -Type Info
        Write-Status "Installation will continue, but conversion will not work without FFmpeg" -Type Warning
    }
}

# GPU Detection
Write-Status "Detecting GPU capabilities..." -Type Info

$detectedGpu = 'none'

if ($GpuType -eq 'auto') {
    # Check for NVIDIA GPU
    try {
        $nvidiaGpu = & nvidia-smi --query-gpu=name --format=csv,noheader 2>&1 | Select-Object -First 1
        if ($nvidiaGpu -and $nvidiaGpu -notmatch 'not recognized') {
            $detectedGpu = 'nvidia'
            Write-Status "NVIDIA GPU detected: $nvidiaGpu" -Type Success
        }
    } catch {
        # nvidia-smi not found
    }
    
    # Check for Intel GPU
    if ($detectedGpu -eq 'none') {
        $intelGpu = Get-WmiObject Win32_VideoController | Where-Object { $_.Name -match 'Intel' }
        if ($intelGpu) {
            $detectedGpu = 'intel'
            Write-Status "Intel GPU detected: $($intelGpu.Name)" -Type Success
        }
    }
    
    if ($detectedGpu -eq 'none') {
        Write-Status "No GPU detected. Will use software encoding." -Type Warning
    }
} else {
    $detectedGpu = $GpuType
    Write-Status "GPU type forced to: $detectedGpu" -Type Info
}

# Create installation directory
Write-Status "Creating installation directory: $InstallDir" -Type Info
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

# Create Python virtual environment
Write-Status "Creating Python virtual environment..." -Type Info
$venvPath = Join-Path $InstallDir '.venv'

if (Test-Path $venvPath) {
    Write-Status "Virtual environment already exists. Removing and recreating..." -Type Warning
    Remove-Item -Recurse -Force $venvPath
}

& $pythonCmd -m venv $venvPath
if ($LASTEXITCODE -ne 0) {
    Write-Status "Failed to create virtual environment" -Type Error
    exit 1
}
Write-Status "Virtual environment created" -Type Success

# Activate virtual environment
$venvPython = Join-Path $venvPath 'Scripts\python.exe'
$venvPip = Join-Path $venvPath 'Scripts\pip.exe'

# Install Python dependencies
Write-Status "Installing Python dependencies..." -Type Info
& $venvPip install --upgrade pip setuptools wheel | Out-Null

# Check for requirements.txt
$requirementsPath = Join-Path $PSScriptRoot 'requirements.txt'
if (Test-Path $requirementsPath) {
    Write-Status "Installing from requirements.txt..." -Type Info
    & $venvPip install -r $requirementsPath
} else {
    Write-Status "requirements.txt not found, installing dependencies manually..." -Type Warning
    & $venvPip install ffmpeg-python==0.2.0 future==1.0.0 PlexAPI==4.15.8 requests==2.31.0
}

if ($LASTEXITCODE -ne 0) {
    Write-Status "Failed to install Python dependencies" -Type Error
    exit 1
}
Write-Status "Python dependencies installed" -Type Success

# Copy media_update.py script
Write-Status "Installing media_update.py..." -Type Info
$mediaUpdateSrc = Join-Path $PSScriptRoot 'media_update.py'

if (-not (Test-Path $mediaUpdateSrc)) {
    Write-Status "media_update.py not found in $PSScriptRoot" -Type Error
    Write-Status "Please run this script from the scripts/ directory" -Type Error
    exit 1
}

Copy-Item $mediaUpdateSrc $InstallDir -Force
Write-Status "media_update.py installed" -Type Success

# Copy database support files
Write-Status "Installing database support files..." -Type Info

$databaseFiles = @('media_database.py', 'build_media_database.py', 'query_media_database.py')
$databaseInstalled = $false

foreach ($file in $databaseFiles) {
    $filePath = Join-Path $PSScriptRoot $file
    if (Test-Path $filePath) {
        Copy-Item $filePath $InstallDir -Force
        $databaseInstalled = $true
        Write-Status "$file installed" -Type Success
    }
}

if ($databaseInstalled) {
    Write-Status "Database caching: ENABLED (11x faster scans)" -Type Success
} else {
    Write-Status "Database caching: DISABLED (files not found)" -Type Warning
}

# Copy requirements.txt
if (Test-Path $requirementsPath) {
    Copy-Item $requirementsPath $InstallDir -Force
}

# Create configuration file
Write-Status "Creating configuration file..." -Type Info
$config = @{
    venv_path = $venvPath
    env_file = "$InstallDir\.env"
    download_dirs = @()
    library_dirs = @{
        tv = ""
        movies = ""
        music = ""
        misc = ""
    }
    container_support = $false
    plex_integration = @{
        url = ""
        token = ""
        path_mappings = @{
            tv = ""
            movies = ""
            music = ""
        }
    }
    transcoding = @{
        video = @{
            codec = "libx264"
            crf = 23
            audio_codec = "aac"
        }
        audio = @{
            codec = "libmp3lame"
            bitrate = "320k"
        }
    }
    gpu_type = $detectedGpu
} | ConvertTo-Json -Depth 10

$config | Out-File -FilePath "$InstallDir\mediabox_config.json" -Encoding UTF8
Write-Status "Configuration created: $InstallDir\mediabox_config.json" -Type Success

# Create wrapper batch script
Write-Status "Creating wrapper script..." -Type Info
$wrapperContent = @"
@echo off
REM Mediabox Media Converter - Wrapper Script
REM Auto-generated by install-media-converter.ps1

set INSTALL_DIR=$InstallDir
set VENV_PYTHON=%INSTALL_DIR%\.venv\Scripts\python.exe

if not exist "%VENV_PYTHON%" (
    echo ERROR: Virtual environment not found at %INSTALL_DIR%\.venv
    echo Please reinstall using install-media-converter.ps1
    exit /b 1
)

REM Pass all arguments to media_update.py
"%VENV_PYTHON%" "%INSTALL_DIR%\media_update.py" %*
"@

$wrapperPath = "$InstallDir\media-converter.bat"
$wrapperContent | Out-File -FilePath $wrapperPath -Encoding ASCII
Write-Status "Wrapper script created: $wrapperPath" -Type Success

# Add to PATH
Write-Status "Adding to system PATH..." -Type Info
$userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")

if ($userPath -notlike "*$InstallDir*") {
    $newPath = "$userPath;$InstallDir"
    [System.Environment]::SetEnvironmentVariable("Path", $newPath, "User")
    $env:Path = "$env:Path;$InstallDir"
    Write-Status "Added $InstallDir to user PATH" -Type Success
    Write-Status "You may need to restart your terminal for PATH changes to take effect" -Type Warning
} else {
    Write-Status "$InstallDir already in PATH" -Type Success
}

# Create usage guide
$usageContent = @'
# Mediabox Media Converter - Windows Usage

## Quick Start

### Process a Single File
```cmd
media-converter --file "C:\Media\video.mp4" --type video
```

### Process a Directory (Batch)
```cmd
media-converter --dir "C:\Media\Movies" --type both
```

### HDR Content (Automatic Detection)
```cmd
media-converter --file "C:\Media\hdr_video.mp4" --type video --downgrade-resolution
```

## Command Reference

### Options
- `--file FILE` - Process single file
- `--dir DIR` - Process entire directory
- `--type {video,audio,both}` - Processing type (default: both)
- `--force-stereo` - Force stereo track creation with dialogue enhancement
- `--downgrade-resolution` - Scale 4K+ to 1080p

### Examples

#### 4K HDR Movie to 1080p SDR
```cmd
media-converter --file "movie.mp4" --type video --downgrade-resolution
```

#### TV Show Directory (Video Only)
```cmd
media-converter --dir "C:\Media\TV\ShowName\Season 01" --type video
```

## Network Shares

### Map Network Drive
```cmd
net use Z: \\server\media /persistent:yes
media-converter --dir "Z:\movies" --type video
```

### UNC Paths (Alternative)
```cmd
media-converter --dir "\\server\media\movies" --type video
```

## Configuration

Edit configuration file to customize settings:
```
%LOCALAPPDATA%\mediabox-converter\mediabox_config.json
```

## Logs

Logs are created in the current directory:
- `media_update_YYYYMMDD.log` - Current log
- `media_update_YYYYMMDD.log.gz` - Compressed old logs

## GPU Acceleration

### NVIDIA (NVENC)
Requires FFmpeg built with CUDA/NVENC support.
Check with: `ffmpeg -encoders | findstr nvenc`

### Intel (Quick Sync)
Automatically detected if drivers installed.
Check with: `ffmpeg -encoders | findstr qsv`

### Software Fallback
Always available. Uses libx264 (slower but works everywhere).

## Distributed Processing

Multiple Windows machines can process the same network share simultaneously.
File locking prevents conflicts. Each machine will:
1. Check for .lock file before processing
2. Create lock file with hostname and timestamp
3. Remove lock after completion

## Troubleshooting

### Command Not Found
```cmd
REM Add to PATH manually or use full path
%LOCALAPPDATA%\mediabox-converter\media-converter.bat --help
```

### FFmpeg Not Found
```cmd
REM Install via Chocolatey
choco install ffmpeg

REM Or via winget
winget install Gyan.FFmpeg

REM Verify installation
ffmpeg -version
```

### Python Errors
```cmd
REM Check Python version
python --version

REM Reinstall dependencies
cd %LOCALAPPDATA%\mediabox-converter
.venv\Scripts\pip.exe install -r requirements.txt
```

## Performance Tips

### Multi-Core Processing
Open multiple PowerShell windows to process different directories:
```powershell
# Window 1
media-converter --dir "C:\Media\Movies\A-M" --type video

# Window 2
media-converter --dir "C:\Media\Movies\N-Z" --type video
```

### Scheduled Tasks
Create a scheduled task to process new media automatically:
```cmd
schtasks /create /tn "Media Converter" /tr "%LOCALAPPDATA%\mediabox-converter\media-converter.bat --dir C:\Downloads --type both" /sc daily /st 03:00
```

## Uninstallation

```cmd
REM Remove installation
rmdir /s /q %LOCALAPPDATA%\mediabox-converter

REM Remove from PATH (via System Properties → Environment Variables)
```

## Support

For issues, see full documentation in the GitHub repository.
'@

$usageContent | Out-File -FilePath "$InstallDir\USAGE.md" -Encoding UTF8
Write-Status "Usage guide created: $InstallDir\USAGE.md" -Type Success

# Installation summary
Write-Host ""
Write-Host "╔═══════════════════════════════════════════════════════════╗"
Write-Host "║                                                           ║"
Write-Host "║              Installation Complete! ✅                     ║"
Write-Host "║                                                           ║"
Write-Host "╚═══════════════════════════════════════════════════════════╝"
Write-Host ""

Write-Status "Installation directory: $InstallDir" -Type Success
Write-Status "Command wrapper: $InstallDir\media-converter.bat" -Type Success
Write-Status "Configuration: $InstallDir\mediabox_config.json" -Type Success
Write-Status "GPU acceleration: $detectedGpu" -Type Success

if ($databaseInstalled) {
    Write-Status "Database caching: ENABLED (11x faster scans)" -Type Success
} else {
    Write-Status "Database caching: DISABLED (files not found)" -Type Warning
}

Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Restart your terminal (for PATH changes)"
Write-Host "  2. Test installation: media-converter --help"
Write-Host "  3. Read usage guide: notepad $InstallDir\USAGE.md"
Write-Host ""

if ($databaseInstalled) {
    Write-Host "Database tools installed:"
    Write-Host "  # Build database cache (speeds up re-scans by 11x)"
    Write-Host "  cd $InstallDir"
    Write-Host "  .venv\Scripts\python.exe build_media_database.py --scan C:\Media"
    Write-Host ""
}

Write-Host "Conversion examples:"
Write-Host '  # Single file'
Write-Host '  media-converter --file "C:\Media\video.mp4" --type video'
Write-Host ""
Write-Host '  # Network share'
Write-Host '  media-converter --dir "\\server\media\movies" --type both'
Write-Host ""
Write-Host '  # HDR tone mapping'
Write-Host '  media-converter --file "hdr_movie.mp4" --type video --downgrade-resolution'
Write-Host ""

Write-Status "For detailed usage, see: $InstallDir\USAGE.md" -Type Info
Write-Host ""
