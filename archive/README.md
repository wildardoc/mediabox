# Mediabox Archive Directory

This directory contains archived files and documentation about removed legacy components from previous Mediabox versions.

## Directory Structure

### `legacy/`
Records of legacy components that have been removed during repository organization:
- `ovpn-directory-removed.txt` - Documentation of OpenVPN directory removal after WireGuard migration

## Purpose

The archive serves to:
1. **Document removals** - Keep track of what was removed and why
2. **Preserve context** - Maintain understanding of past implementations
3. **Enable recovery** - Provide information if legacy components need to be restored
4. **Clean repository** - Keep the main directory focused on current functionality

## Related Issues

- **Issue #15** - Repository organization and cleanup
- **Issue #16** - WireGuard implementation replacing OpenVPN

## Restoration

If any archived functionality needs to be restored, check the Git history for the actual implementations:
```bash
# Search for removed files in Git history
git log --all --full-history -- path/to/removed/file

# Find commits that mention specific functionality
git log --all --grep="openvpn\|wireguard" --oneline
```
