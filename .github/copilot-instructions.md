# Mediabox - Automated Media Processing Stack
Mediabox is a Docker-based automated media management system with sophisticated media processing capabilities. It manages TV shows, movies, and music through a collection of integrated applications (Sonarr, Radarr, Lidarr) with automated downloading, conversion, and library management.

Always reference these instructions first and fallback to search or bash commands only when you encounter unexpected information that does not match the info here.

## Working Effectively

### Bootstrap and Deploy the System:
- Install prerequisites:
  - `sudo apt update && sudo apt full-upgrade`  
  - `sudo apt install curl git bridge-utils`
  - Install Docker CE: `curl -fsSL https://get.docker.com -o get-docker.sh && sudo sh get-docker.sh`
  - Install Docker-Compose: `sudo curl -s https://api.github.com/repos/docker/compose/releases/latest | grep "browser_download_url" | grep -i -m1 "$(uname -s)"-"$(uname -m)" | cut -d '"' -f4 | xargs sudo curl -L -o /usr/local/bin/docker-compose && sudo chmod +x /usr/local/bin/docker-compose`
  - `sudo usermod -aG docker $USER`
  - `sudo /sbin/modprobe iptable_mangle && sudo bash -c "echo iptable_mangle >> /etc/modules"`
  - **REBOOT REQUIRED**: `sudo reboot`

### Deploy Mediabox:
- Clone: `git clone https://github.com/wildardoc/mediabox.git && cd mediabox/`
- **NEVER CANCEL**: Run setup: `./mediabox.sh` -- takes 5-15 minutes depending on setup complexity. Set timeout to 30+ minutes.
- **Docker image pull**: `docker-compose pull` -- takes ~1 minute
- **Container startup**: `docker-compose up -d` -- takes ~10 seconds
- **Container shutdown**: `docker-compose down` -- takes ~7 seconds

### System Requirements:
- **Operating System**: Ubuntu 18.04 LTS / 20.04 LTS (Server or Desktop)
- **VPN**: Private Internet Access (PIA) account required for torrent functionality
- **Dependencies**: Docker, Docker-Compose, Python3, FFmpeg (auto-installed)
- **Disk Space**: Plan for significant media storage requirements

## Validation

### CRITICAL - System Validation Steps:
After any changes, ALWAYS run these validation steps:

1. **Container Health Check**:
   ```bash
   docker-compose ps
   # All containers should show "Up" status
   ```

2. **Web Interface Testing**:
   - **Homer Dashboard**: `curl -s -o /dev/null -w "%{http_code}" http://localhost:80` (expect 200)
   - **Sonarr**: `curl -s -I http://localhost:8989 | head -1` (expect 401 Unauthorized - auth required)
   - **Radarr**: `curl -s -I http://localhost:7878 | head -1` (expect 401 Unauthorized - auth required)
   - **Lidarr**: `curl -s -I http://localhost:8686 | head -1` (expect 401 Unauthorized - auth required)

3. **Media Processing Validation**:
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
- **ALWAYS verify Docker containers are accessible**: Use `docker-compose logs [service]` to debug issues

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

### Webhook Configuration:
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
- **Container fails to start**: Check `docker-compose logs [service]` for specific errors
- **Web interface not accessible**: Verify container is "Up" with `docker-compose ps`
- **Media processing errors**: Check `scripts/media_update_*.log` for FFmpeg errors
- **Webhook failures**: Check `scripts/import_*.log` for integration issues
- **VPN connection issues**: Verify PIA credentials in secure environment file

### Debugging Commands:
```bash
# Container status
docker-compose ps

# Service logs
docker-compose logs sonarr
docker-compose logs radarr

# Restart specific service
docker-compose restart sonarr

# Complete system restart
docker-compose down && docker-compose up -d
```

## Performance & Timing Expectations

### CRITICAL - NEVER CANCEL Operations:
- **Initial Setup**: `./mediabox.sh` takes 5-15 minutes - NEVER CANCEL, set timeout to 30+ minutes
- **Docker Image Pull**: `docker-compose pull` takes ~1 minute - Set timeout to 5+ minutes  
- **Container Startup**: `docker-compose up -d` takes ~10 seconds - Set timeout to 2+ minutes
- **Container Shutdown**: `docker-compose down` takes ~7 seconds - Set timeout to 1+ minute
- **Media Processing**: Variable based on file size - Large files may take 30+ minutes

### Expected Response Times:
- **Web Interfaces**: Should respond within 1-2 seconds after container initialization
- **Container Health**: Allow 10-30 seconds for services to fully initialize
- **Media Conversion**: 1-5x real-time depending on source format and system performance

## Security & Credentials

### Credential Management:
- **Location**: Credentials stored in `~/.mediabox/credentials.env` (user-only access)
- **Setup**: Run `./scripts/setup-secure-env.sh` for credential configuration
- **Required**: PIA VPN username/password, daemon passwords for services

### Important Security Notes:
- **Never commit credentials**: Project uses secure external credential sourcing
- **File permissions**: Credential file automatically set to 600 (user-only)
- **VPN requirement**: Torrent functionality requires active PIA VPN connection

## Common Tasks Reference

### Repository Structure:
```
mediabox/
├── mediabox.sh                 # Main setup script (ENTRY POINT)
├── docker-compose.yml         # Container definitions (12 services)
├── .env                       # Environment configuration (auto-generated)
├── scripts/                   # Automation directory
│   ├── import.sh             # Webhook handler for *arr integration
│   ├── media_update.py       # Core media processing engine
│   ├── remove_files.py       # Media cleanup automation
│   ├── rotate-logs.sh        # Log management system
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
docker-compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"

# Service health
curl -s -o /dev/null -w "Homer: %{http_code}\n" http://localhost:80

# Log overview
ls -la scripts/*.log scripts/*.log.gz | tail -10

# Disk usage
du -sh content/*/ scripts/
```

This system provides enterprise-grade automated media processing with comprehensive error handling, logging, and maintenance automation. Always test changes in a non-production environment first.