# Mediabox

Mediabox is an all Docker Container based media aggregator stack with **automated media processing capabilities**.

## 🎯 **Active Components**

Your current Mediabox deployment includes:

* **[Sonarr](https://sonarr.tv/) - TV Show Management & Automation** ✅
* **[Radarr](https://radarr.video/) - Movie Management & Automation** ✅  
* **[Lidarr](https://lidarr.audio/) - Music Management & Automation** ✅
* **[Prowlarr](https://github.com/Prowlarr/Prowlarr) - Indexer Manager/Proxy** ✅
* **[Deluge torrent client (using VPN)](http://deluge-torrent.org/)** ✅
* **[NZBGet Usenet Downloader](https://nzbget.net/)** ✅
* **[Overseerr Media Request Management](https://github.com/sct/overseerr)** ✅
* **[Homer - Server Home Page](https://github.com/bastienwirtz/homer)** ✅
* **[Portainer Docker Container Manager](https://portainer.io/)** ✅
* **[Maintainerr Media Manager](https://maintainerr.info/)** ✅
* **[Tautulli Plex Media Server Monitor](https://github.com/tautulli/tautulli)** ✅

### **Optional Components** 
* **[Plex Media Server](https://www.plex.tv/)** - *Ready for Docker deployment when needed*

## 🚀 **Enhanced Features**

### **Service Profiles for Flexible Deployment** 🎯

Mediabox now supports Docker Compose profiles for resource-efficient deployments based on your needs:

**Available Profiles:**
- **`core`**: Essential media management services (sonarr, radarr, prowlarr, delugevpn, homer)
- **`full`**: All services - complete mediabox experience (default behavior)
- **`plex`**: Plex Media Server with Tautulli monitoring
- **`monitoring`**: Plex with Tautulli for usage statistics (same as plex profile)
- **`music`**: Lidarr for music management
- **`usenet`**: NZBGet for Usenet downloads  
- **`requests`**: Overseerr for media request management
- **`maintenance`**: Maintainerr and Portainer for system management

**Usage Examples:**
```bash
# Start core services only (minimal resource usage)
docker compose --profile core up -d

# Start everything (traditional behavior)  
docker compose --profile full up -d

# Start core services with Plex
docker compose --profile core --profile plex up -d

# Start Plex with monitoring (note: plex profile includes tautulli)
docker compose --profile plex up -d

# Custom combination: core + music + requests
docker compose --profile core --profile music --profile requests up -d
```

**Benefits:**
- **💰 Resource Savings**: Run only what you need
- **🔧 Flexible Deployment**: Perfect for different hardware configurations
- **⚡ Faster Startup**: Fewer containers = quicker initialization
- **📊 Better Performance**: Optimized resource allocation

### **Automated Media Processing**
Mediabox includes intelligent media processing that automatically triggers when new content is downloaded:

- **📺 TV Shows**: Video conversion with subtitle preservation 
- **🎬 Movies**: Comprehensive audio/video processing
- **🎵 Music**: High-quality audio conversion (FLAC/WAV/etc → MP3 320kbps)
- **📋 Subtitles**: PGS subtitle extraction and preservation
- **🔗 *arr Integration**: Webhook-based automation with Sonarr/Radarr/Lidarr

### **Intelligent Log Management**
- **📊 Automatic rotation**: Weekly log compression and cleanup
- **💾 Space optimization**: 90%+ space savings on historical logs
- **🗓️ Smart retention**: 14 days active, 90 days archived, auto-delete thereafter

## Prerequisites

* [Ubuntu 18.04 LTS](https://www.ubuntu.com/) Or [Ubuntu 20.04 LTS](https://www.ubuntu.com/)
* [VPN account from Private internet Access](https://www.privateinternetaccess.com/) (Please see [binhex's Github Repo](https://github.com/binhex/arch-delugevpn) if you want to use a different VPN)
* [Git](https://git-scm.com/)
* [Docker](https://www.docker.com/)
* [Docker-Compose](https://docs.docker.com/compose/)

### **PLEASE NOTE**

For simplicity's sake (eg. automatic dependency management), the method used to install these packages is Ubuntu's default package manager, [APT](https://wiki.debian.org/Apt).  There are several other methods that work just as well, if not better (especially if you don't have superuser access on your system), so use whichever method you prefer.  Continue when you've successfully installed all packages listed.

### Installation

(You'll need superuser access to run these commands successfully)

Start by updating and upgrading our current packages:

`$ sudo apt update && sudo apt full-upgrade`

Install the prerequisite packages:

`$ sudo apt install curl git bridge-utils`

**Note** - Mediabox uses Docker CE as the default Docker version - if you skip this and run with older/other Docker versions you may have issues.

1. Uninstall old versions - It’s OK if apt and/or snap report that none of these packages are installed.  
    `$ sudo apt remove docker docker-engine docker.io containerd runc`  
    `$ sudo snap remove docker`  

2. Install Docker CE:  
    `$ curl -fsSL https://get.docker.com -o get-docker.sh`  
    `$ sudo sh get-docker.sh`  

3. Install Docker-Compose:  

    ```bash
    sudo curl -s https://api.github.com/repos/docker/compose/releases/latest | grep "browser_download_url" | grep -i -m1 `uname -s`-`uname -m` | cut -d '"' -f4 | xargs sudo curl -L -o /usr/local/bin/docker-compose
    ```

4. Set the permissions: `$ sudo chmod +x /usr/local/bin/docker-compose`  

5. Verify the Docker Compose installation: `$ docker-compose -v`  

Add the current user to the docker group:

`$ sudo usermod -aG docker $USER`

Adjustments for the the DelugeVPN container

**VPN Configuration**: Mediabox uses WireGuard for VPN connectivity, providing faster performance and simpler configuration compared to legacy OpenVPN methods.

`$ sudo /sbin/modprobe iptable_mangle`

`$ sudo bash -c "echo iptable_mangle >> /etc/modules"`

Reboot your machine manually, or using the command line:

`$ sudo reboot`

## Using mediabox

Once the prerequisites are all taken care of you can move forward with using mediabox.

1. Clone the mediabox repository: `$ git clone https://github.com/tom472/mediabox.git`

2. Change directory into mediabox: `$ cd mediabox/`

3. Run the mediabox.sh script: `$ ./mediabox.sh`  (**See below for the script questions**)

4. To upgrade Mediabox at anytime, re-run the mediabox script: `$ ./mediabox.sh`

### Please be prepared to supply the following details after you run Step 3 above

As the script runs you will be prompted for:

1. Your Private Internet Access credentials
    * **username**
    * **password**

2. The version of Plex you want to run
    * **latest**
    * **public**
    * **plexpass**

    Note: If you choose plexpass as your version you may optionally specify CLAIM_TOKEN - you can get your claim token by logging in at [plex.tv/claim](https://www.plex.tv/claim)

3. Credentials for the NBZGet interface and the Deluge daemon which needed for the CouchPotato container.
    * **username**
    * **password**

Upon completion, the script will launch your mediabox containers using the **full** profile (all services).

### **Customizing Your Deployment with Profiles**

After initial setup, you can customize which services run using Docker Compose profiles:

```bash
# Stop all services
docker compose down

# Start with different profiles
docker compose --profile core up -d                    # Essential services only
docker compose --profile core --profile plex up -d     # Core + Plex
docker compose --profile full up -d                    # All services (default)
```

**Profile Reference:**
- **Core**: `sonarr`, `radarr`, `prowlarr`, `delugevpn`, `homer` (essential media management)
- **Full**: All 12 services (complete functionality)  
- **Plex**: `plex`, `tautulli` (media server with monitoring)
- **Monitoring**: `plex`, `tautulli` (same as plex profile)
- **Music**: `lidarr` (music management)
- **Usenet**: `nzbget` (Usenet downloads)
- **Requests**: `overseerr` (media requests)
- **Maintenance**: `maintainerr`, `portainer` (system management)

**Note**: The `mediabox.sh` script uses `docker compose --profile full up -d` for initial deployment. You can customize this after setup.  

## 🔐 **Credential Security**

Mediabox automatically implements secure credential management during setup:

- **🔒 Secure Storage**: Credentials are stored in `~/.mediabox/credentials.env` with user-only access (600 permissions)
- **📂 Project Safety**: No sensitive data remains in the project directory 
- **🚫 Git Protection**: Eliminates risk of accidentally committing passwords
- **🔄 Environment Integration**: Credentials are automatically sourced into Docker containers

### **Managing Credentials**

**To change your PIA or daemon passwords:**
```bash
# Option 1: Edit directly (recommended for quick changes)
nano ~/.mediabox/credentials.env

# Option 2: Interactive script (recommended for complete updates)
./scripts/setup-secure-env.sh
```

**To verify credential security:**
```bash
# Check file permissions (should show 600)
ls -la ~/.mediabox/credentials.env

# Test credential loading
source .env && echo "Credentials loaded successfully"
```

**Note**: The `mediabox.sh` script automatically calls `setup-secure-env.sh` during initial setup, ensuring consistent credential management across all scenarios.

**🎯 Automated Media Processing Setup**

The setup script automatically configures:
- **Python environment** with required packages (ffmpeg-python, future)
- **Log rotation** via weekly cron job (Sundays at 2 AM)  
- **Webhook scripts** for *arr application integration
- **Container dependencies** (Python3, ffmpeg, pip) installed automatically

**🔗 Configuring *arr Webhooks**

After setup, configure webhooks in each *arr application:

1. **Sonarr**: Settings → Connect → Add → Custom Script
2. **Radarr**: Settings → Connect → Add → Custom Script  
3. **Lidarr**: Settings → Connect → Add → Custom Script

**Webhook Settings:**
- **Path**: `/scripts/import.sh`
- **Triggers**: ✅ On Import, ✅ On Upgrade
- **Arguments**: *(leave blank - uses environment variables)*

The system will automatically:
- Detect download completion via webhooks
- Process media based on type (TV/Movies/Music)
- Convert formats for Plex compatibility
- Preserve metadata and subtitles
- Log all activities with rotation

Portainer has been switched to the **CE** branch  

* **A Password** will now be required - the password can be set at initial login to Portiner.  
* **Initial Username** The initial username for Portainer is **admin**  

### **Mediabox has been tested to work on Ubuntu 18.04 LTS / 20.04 LTS - Server and Desktop**

## 🛠️ **Advanced Usage & Maintenance**

### **Scripts Directory**
All automation scripts are organized in the `scripts/` directory:
```
scripts/
├── import.sh                 # Webhook handler for *arr integration
├── media_update.py          # Core media processing engine  
├── rotate-logs.sh           # Log rotation utility
├── mediabox_config.json     # Configuration file
├── requirements.txt         # Python dependencies
├── LOG_MANAGEMENT.md        # Log management documentation
└── .venv/                   # Python virtual environment
```

## **Core Processing Engine**

### **media_update.py Overview**
The `media_update.py` script is the intelligent core of the Mediabox automation system, providing comprehensive media processing capabilities:

**Key Features:**
- **Video Processing**: Converts video files to H.264/H.265 MP4 format with subtitle preservation
- **Audio Processing**: Converts FLAC, WAV, AIFF and other formats to high-quality MP3 (320kbps)
- **Subtitle Handling**: Extracts PGS subtitles to .sup files for Plex compatibility
- **Batch Processing**: Handles both directory-wide and single-file processing
- **Metadata Preservation**: Maintains audio tags during conversion
- **Error Recovery**: Robust error handling with detailed logging

**Processing Modes:**
- `--type video`: Video conversion with subtitle preservation (TV shows via Sonarr)
- `--type audio`: Audio-only conversion (Music via Lidarr) 
- `--type both`: Complete audio and video processing (Movies via Radarr)

**Supported Formats:**
- **Video Input**: MKV, AVI, MOV, WMV, FLV, M4V, 3GP, WEBM → MP4 output
- **Audio Input**: FLAC, WAV, AIFF, APE, WV, M4A, OGG, OPUS, WMA → MP3 320kbps output
- **Subtitles**: PGS subtitle tracks → SUP files for Plex

### **Manual Media Processing**
```bash
# Process specific directory
cd /path/to/mediabox/scripts
python3 media_update.py --dir "/path/to/media" --type video

# Process single file  
python3 media_update.py --file "/path/to/file.mkv" --type both

# Audio-only conversion
python3 media_update.py --dir "/path/to/music" --type audio
```

### **Media Cleanup & Maintenance**
```bash
# Manual cleanup of duplicate/old downloads (dry-run first)
cd scripts && python3 remove_files.py --dry-run

# Actually remove files
cd scripts && python3 remove_files.py

# Manual log rotation
cd scripts && ./rotate-logs.sh

# View compressed logs
zcat media_update_*.log.gz | less

# Check automation history
cat scripts/log-rotation.log
cat scripts/cleanup_downloads.log
```

**Automatic Cleanup Features:**
- **Smart Duplicate Detection**: Compares download files against library files
- **Resolution-Based Cleanup**: Removes lower-quality duplicates automatically  
- **Age-Based Cleanup**: Removes unmatched files older than 7 days
- **Weekly Schedule**: Runs automatically on Mondays at 3 AM

### **Troubleshooting**
- **Logs**: Check `scripts/import_YYYYMMDD.log` for webhook activity
- **Processing**: Check `scripts/media_update_*.log` for conversion details  
- **Webhooks**: Test via *arr application Settings → Connect → Test
- **Dependencies**: Containers auto-install Python packages on startup

**Thanks go out to:**

[@kspillane](https://github.com/kspillane)

[@mnkhouri](https://github.com/mnkhouri)

[@danipolo](https://github.com/danipolo)

[binhex](https://github.com/binhex)

[LinuxServer.io](https://github.com/linuxserver)

[Docker](https://github.com/docker)

[Portainer.io](https://github.com/portainer)

---

If you enjoy the project -- Fuel it with some caffeine :)

[![Donate](https://img.shields.io/badge/Donate-SquareCash-brightgreen.svg)](https://cash.me/$TomMorgan)

---

## Disclaimer

THIS SOFTWARE IS PROVIDED "AS IS" AND ANY EXPRESSED OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE REGENTS OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

## License

MIT License

Copyright (c) 2017 Tom Morgan

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
