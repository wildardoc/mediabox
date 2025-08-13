# Mediabox Documentation

This directory contains user-facing documentation for Mediabox administration and maintenance.

## Available Documentation

### `LOG_MANAGEMENT.md`
Comprehensive guide to Mediabox's automated log management system:
- **Log rotation policies** - Retention schedules and compression settings
- **Manual management** - Commands for manual log rotation and cleanup  
- **Troubleshooting** - Disk space issues, log analysis, and emergency procedures
- **Automation details** - Cron job configuration and monitoring

## Quick Reference

### View Log Management Guide
```bash
cat docs/LOG_MANAGEMENT.md
```

### Common Log Management Tasks
```bash
# Manual log rotation
cd scripts && ./rotate-logs.sh

# Check log sizes
ls -lh scripts/*.log*

# View compressed logs  
zcat scripts/media_update_*.log.gz | less
```

## Documentation Standards

All documentation in this directory should be:
- **User-focused** - Written for Mediabox administrators and users
- **Practical** - Include working examples and commands
- **Current** - Kept up-to-date with the latest Mediabox features
- **Accessible** - Use clear language and logical organization

For development and implementation notes, see the commit history and pull request discussions.
