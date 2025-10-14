# Docker Compose Profiles Guide

## Overview

Mediabox uses Docker Compose profiles to organize services into logical groups. This allows you to start only the services you need, or run everything at once.

## Default Configuration

The `.env` file contains:
```bash
COMPOSE_PROFILES=full
```

This means **all services start by default** when you run:
```bash
docker compose up -d
```

## Available Profiles

### **core** - Essential Media Services
Core automation services needed for most media workflows:
- **Sonarr** - TV show management
- **Radarr** - Movie management  
- **Prowlarr** - Indexer management
- **DelugeVPN** - VPN-protected torrent client
- **Homer** - Dashboard

### **full** - All Services (Default)
Everything! All containers will start:
- All core services
- Music (Lidarr)
- Usenet (NZBGet)
- Plex + monitoring
- Request management (Overseerr)
- Maintenance tools (Portainer, Maintainerr)

### **music** - Music Services
- **Lidarr** - Music management and automation

### **usenet** - Usenet Downloader
- **NZBGet** - Usenet download client

### **plex** - Plex Media Server
- **Plex** - Media server

### **monitoring** - Plex Monitoring
- **Plex** - Media server
- **Tautulli** - Plex usage statistics and monitoring

### **requests** - Media Requests
- **Overseerr** - User media request interface

### **maintenance** - System Maintenance
- **Portainer** - Docker container management
- **Maintainerr** - Plex library cleanup automation

## Usage Examples

### Start All Services (Default)
```bash
docker compose up -d
```
This uses `COMPOSE_PROFILES=full` from `.env`

### Start Specific Profile(s)
```bash
# Just core services
docker compose --profile core up -d

# Core + Plex + monitoring
docker compose --profile core --profile plex --profile monitoring up -d

# Everything except music and usenet
docker compose --profile core --profile plex --profile monitoring --profile requests --profile maintenance up -d
```

### Override Default Profile
```bash
# Temporarily override the default
COMPOSE_PROFILES=core docker compose up -d

# Or export it for the session
export COMPOSE_PROFILES=core,plex,monitoring
docker compose up -d
```

### Change Default Profile Permanently

Edit `/Storage/docker/mediabox/.env`:
```bash
# Change from:
COMPOSE_PROFILES=full

# To (example - core services only):
COMPOSE_PROFILES=core

# Or multiple profiles:
COMPOSE_PROFILES=core,plex,monitoring
```

## Service Profile Mapping

| Service | Profiles |
|---------|----------|
| **DelugeVPN** | core, full |
| **Homer** | core, full |
| **Sonarr** | core, full |
| **Radarr** | core, full |
| **Prowlarr** | core, full |
| **Lidarr** | music, full |
| **NZBGet** | usenet, full |
| **Plex** | plex, monitoring, full |
| **Tautulli** | monitoring, plex, full |
| **Overseerr** | requests, full |
| **Portainer** | maintenance, full |
| **Maintainerr** | maintenance, full |

## Common Scenarios

### Minimal Setup (Core Media Only)
```bash
# Edit .env
COMPOSE_PROFILES=core

# Start
docker compose up -d
```
**Starts**: Sonarr, Radarr, Prowlarr, DelugeVPN, Homer

### Media Server + Monitoring
```bash
# Edit .env
COMPOSE_PROFILES=core,plex,monitoring

# Start
docker compose up -d
```
**Starts**: Core services + Plex + Tautulli

### Everything Except Music
```bash
# Edit .env  
COMPOSE_PROFILES=core,usenet,plex,monitoring,requests,maintenance

# Start
docker compose up -d
```
**Starts**: Everything except Lidarr

### Development/Testing
```bash
# Edit .env
COMPOSE_PROFILES=core,maintenance

# Start
docker compose up -d
```
**Starts**: Core services + Portainer for container management

## Checking Active Profiles

### See Available Profiles
```bash
cd /Storage/docker/mediabox
docker compose config --profiles
```

### See Which Services Will Start
```bash
cd /Storage/docker/mediabox
docker compose config --services
```

### See Current Profile Setting
```bash
cd /Storage/docker/mediabox
grep COMPOSE_PROFILES .env
```

## Troubleshooting

### No Containers Starting
**Problem**: Running `docker compose up -d` starts nothing

**Solution**: Check that `COMPOSE_PROFILES` is set in `.env`:
```bash
cd /Storage/docker/mediabox
grep COMPOSE_PROFILES .env
```

If missing, add:
```bash
echo "COMPOSE_PROFILES=full" >> .env
```

### Wrong Services Starting
**Problem**: Only some services start when you expected all

**Solution**: Verify profile setting:
```bash
cd /Storage/docker/mediabox
cat .env | grep COMPOSE_PROFILES
```

Change to `full` to start everything:
```bash
sed -i 's/COMPOSE_PROFILES=.*/COMPOSE_PROFILES=full/' .env
docker compose up -d
```

### Profile Flag Not Working
**Problem**: `--profile` flag seems ignored

**Solution**: The `COMPOSE_PROFILES` in `.env` takes precedence. Either:

1. Remove from `.env` temporarily:
```bash
sed -i '/COMPOSE_PROFILES/d' .env
docker compose --profile core up -d
```

2. Or override with command:
```bash
COMPOSE_PROFILES=core docker compose up -d
```

## Best Practices

### 1. **Set Default in .env**
Always have `COMPOSE_PROFILES` in your `.env` file so `docker compose up -d` works consistently.

### 2. **Use 'full' for Production**
For a complete media server, use `COMPOSE_PROFILES=full` to ensure all services start.

### 3. **Use Specific Profiles for Development**
When testing or developing, use minimal profiles like `core` or `core,maintenance`.

### 4. **Document Your Setup**
If you use a custom profile combination, document it in your setup notes.

### 5. **Version Control .env.example**
Keep an `.env.example` with your preferred `COMPOSE_PROFILES` setting for reference.

## Related Commands

```bash
# View all running containers
docker compose ps

# Stop all containers
docker compose down

# Restart specific service
docker compose restart sonarr

# View logs for a service
docker compose logs -f radarr

# Update and restart
docker compose pull && docker compose up -d
```

## References

- [Docker Compose Profiles Documentation](https://docs.docker.com/compose/profiles/)
- [Mediabox Setup Guide](../README.md)
- [Docker Compose V2 Migration](../DOCKER_COMPOSE_V2_MIGRATION.md)
