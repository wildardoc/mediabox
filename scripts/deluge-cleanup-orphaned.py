#!/usr/bin/env python3
"""
Find Deluge torrents whose files are missing or size-mismatched on disk
(caused by past direct deletions from the completed downloads folder) and
remove them through Deluge's own RPC so they stop erroring/blocking the
queue. Companion to the fix in remove_files.py, which now routes deletions
through Deluge instead of touching files directly.

Usage:
    python3 deluge-cleanup-orphaned.py            # dry run, lists broken torrents
    python3 deluge-cleanup-orphaned.py --remove    # actually removes them
"""
import argparse
import json
import os

from deluge_client import DelugeRPCClient

SCRIPT_DIR = os.path.dirname(__file__)


def load_env_value(key, default=None):
    env_file = os.path.join(SCRIPT_DIR, '..', '.env')
    if os.path.exists(env_file):
        with open(env_file) as f:
            for line in f:
                line = line.strip()
                if line.startswith(f'{key}='):
                    return line.split('=', 1)[1].strip().strip('"')
    return default


def load_deluge_auth():
    auth_path = os.path.normpath(os.path.join(SCRIPT_DIR, '..', 'delugevpn', 'config', 'auth'))
    with open(auth_path) as f:
        username, password = f.readline().strip().split(':')[:2]
    return username, password


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--remove', action='store_true', help='Actually remove broken torrents (default: dry run)')
    args = parser.parse_args()

    host = load_env_value('IP_ADDRESS', '127.0.0.1')
    dldir = load_env_value('DLDIR')
    username, password = load_deluge_auth()

    client = DelugeRPCClient(host, 58846, username, password, decode_utf8=True)
    client.connect()
    statuses = client.call('core.get_torrents_status', {}, ['name', 'save_path', 'files', 'state', 'progress'])

    broken = []
    for torrent_id, info in statuses.items():
        # Skip torrents that are still actively downloading - partial/missing
        # files are expected there, not a sign of corruption.
        if info.get('progress', 0) < 100:
            continue
        save_path = info.get('save_path', '')
        missing_or_mismatched = []
        for f in info.get('files', []):
            container_path = os.path.normpath(os.path.join(save_path, f['path']))
            if dldir and container_path.startswith('/data'):
                host_path = os.path.normpath(container_path.replace('/data', dldir, 1))
            else:
                host_path = container_path
            if not os.path.exists(host_path):
                missing_or_mismatched.append((host_path, 'missing'))
            elif os.path.getsize(host_path) != f['size']:
                missing_or_mismatched.append((host_path, 'size mismatch'))
        if missing_or_mismatched:
            broken.append((torrent_id, info.get('name', '?'), info.get('state', '?'), missing_or_mismatched))

    if not broken:
        print("No broken torrents found.")
        return

    print(f"Found {len(broken)} torrent(s) with missing/mismatched files:\n")
    for torrent_id, name, state, problems in broken:
        print(f"[{state}] {name} ({torrent_id})")
        for path, reason in problems:
            print(f"    {reason}: {path}")
        print()

    if args.remove:
        for torrent_id, name, _, _ in broken:
            try:
                client.call('core.remove_torrent', torrent_id, True)
                print(f"Removed: {name}")
            except Exception as e:
                print(f"Failed to remove {name}: {e}")
    else:
        print("Dry run - nothing removed. Re-run with --remove to actually remove these torrents.")


if __name__ == '__main__':
    main()
