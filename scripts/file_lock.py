#!/usr/bin/env python3
"""
File Locking Utility for Distributed Media Processing
=====================================================

Provides cross-platform file locking to prevent multiple workers from
processing the same media file simultaneously. Supports distributed
processing across multiple machines accessing shared storage.

FEATURES:
--------
• Cross-platform: Works on Linux, Windows, and macOS
• Network-safe: Uses file-based locking for NFS/SMB shares
• Stale lock detection: Automatically cleans up abandoned locks
• Hostname tracking: Identifies which machine holds the lock
• Timeout handling: Configurable lock timeout for crashed processes

USAGE:
-----
from file_lock import FileLock

# Try to acquire lock
lock = FileLock("/path/to/video.mp4", timeout=300)
if lock.acquire():
    try:
        # Process the file
        process_video(file_path)
    finally:
        # Always release the lock
        lock.release()
else:
    print(f"File is locked by {lock.lock_info['hostname']}")
"""

import os
import socket
import time
import json
from pathlib import Path
from datetime import datetime, timedelta


class FileLock:
    """
    Cross-platform file lock using filesystem-based locking.
    
    Creates a .lock file next to the target file containing:
    - hostname: Machine that acquired the lock
    - pid: Process ID that acquired the lock
    - timestamp: When the lock was acquired
    - file: Path to the file being locked
    """
    
    def __init__(self, file_path, timeout=300, lock_suffix=".lock"):
        """
        Initialize file lock.
        
        Args:
            file_path: Path to the file to lock
            timeout: Lock timeout in seconds (default: 300 = 5 minutes)
            lock_suffix: Suffix for lock file (default: .lock)
        """
        self.file_path = Path(file_path).resolve()
        self.timeout = timeout
        
        # Simple approach: create filename.lock in same directory
        self.lock_path = self.file_path.parent / (self.file_path.name + lock_suffix)
        self.target_filename = self.file_path.name
        
        # Current machine info
        self.hostname = socket.gethostname()
        self.pid = os.getpid()
        
        # Generate unique identifier for this machine/process
        import uuid
        self.lock_id = f"{self.hostname}_{self.pid}_{uuid.uuid4().hex[:8]}"
        
        # Lock info (populated when checking locks)
        self.lock_info = None
        
    def _try_create_lock(self):
        """Try to create lock file atomically."""
        try:
            with open(self.lock_path, 'x') as f:  # 'x' = exclusive creation
                lock_data = {
                    "lock_id": self.lock_id,
                    "hostname": self.hostname,
                    "pid": self.pid,
                    "timestamp": time.time(),
                    "file": str(self.file_path),
                    "locked_at": datetime.now().isoformat()
                }
                json.dump(lock_data, f, indent=2)
            return True
        except FileExistsError:
            return False
        except (IOError, OSError):
            return False
    
    def _verify_our_lock(self):
        """Verify the lock file contains our identifier."""
        try:
            with open(self.lock_path, 'r') as f:
                data = json.load(f)
                return data.get('lock_id') == self.lock_id
        except:
            return False
    
    def _cleanup_stale_lock(self, max_age_seconds=21600):  # 6 hours default
        """Remove lock file if it's older than max_age_seconds."""
        if not self.lock_path.exists():
            return
            
        try:
            with open(self.lock_path, 'r') as f:
                data = json.load(f)
                
            lock_timestamp = data.get('timestamp', 0)
            current_time = time.time()
            
            if current_time - lock_timestamp > max_age_seconds:
                self.lock_path.unlink()
                print(f"🧹 Removed stale lock (age: {(current_time - lock_timestamp)/3600:.1f} hours)")
                
        except (IOError, OSError, json.JSONDecodeError):
            # If we can't read the lock file, remove it
            try:
                self.lock_path.unlink()
                print("🧹 Removed corrupted lock file")
            except:
                pass

    def _create_lock_data(self):
        """Create lock data dictionary."""
        return {
            "hostname": self.hostname,
            "pid": self.pid,
            "timestamp": time.time(),
            "file": str(self.file_path),
            "locked_at": datetime.now().isoformat()
        }
    
    def _read_lock_file(self):
        """
        Read existing lock file.
        
        Returns:
            dict: Lock data, or None if lock file doesn't exist or is invalid
        """
        try:
            if not self.lock_path.exists():
                return None
            
            with open(self.lock_path, 'r') as f:
                lock_data = json.load(f)
            
            # Validate lock data structure
            required_keys = ['hostname', 'timestamp', 'file']
            if not all(key in lock_data for key in required_keys):
                return None
            
            return lock_data
        except (json.JSONDecodeError, IOError, OSError):
            # Invalid or unreadable lock file
            return None
    
    def _is_lock_stale(self, lock_data):
        """
        Check if lock is stale (timed out).
        
        Args:
            lock_data: Lock data dictionary
            
        Returns:
            bool: True if lock is stale and should be removed
        """
        if not lock_data:
            return True
        
        lock_time = lock_data.get('timestamp', 0)
        current_time = time.time()
        
        # Check if lock has timed out
        if current_time - lock_time > self.timeout:
            return True
        
        return False
    
    def _remove_lock_file(self):
        """Remove lock file safely."""
        try:
            if self.lock_path.exists():
                self.lock_path.unlink()
                return True
        except (IOError, OSError):
            return False
        return False
    
    def _create_lock_file(self):
        """
        Create lock file atomically.
        
        Returns:
            bool: True if lock was created successfully, False if it already exists
        """
        try:
            # Try to create lock file exclusively (fails if exists)
            # Using 'x' mode ensures atomic creation on most filesystems
            with open(self.lock_path, 'x') as f:
                json.dump(self._create_lock_data(), f, indent=2)
            return True
        except FileExistsError:
            # Lock already exists
            return False
        except (IOError, OSError):
            # Filesystem error
            return False
    
    def acquire(self, wait=False, poll_interval=1.0):
        """
        Attempt to acquire the lock using simple approach:
        1. Check if filename.lock exists
        2. If not, create it with our identifier
        3. Verify it's our lock file
        4. Clean up stale locks (6+ hours old)
        
        Args:
            wait: If True, wait for lock to become available
            poll_interval: Seconds to wait between lock checks (if wait=True)
            
        Returns:
            bool: True if lock was acquired, False otherwise
        """
        while True:
            # Clean up stale locks first (6 hours = 21600 seconds)
            self._cleanup_stale_lock(max_age_seconds=21600)
            
            # Check if lock file exists
            if not self.lock_path.exists():
                # No lock file - try to create one
                if self._try_create_lock():
                    # Verify it's our lock file
                    if self._verify_our_lock():
                        return True
                    else:
                        # Another process beat us, continue loop
                        continue
                else:
                    # Failed to create lock, continue loop
                    continue
            else:
                # Lock file exists - check if it's stale or ours
                lock_info = self.get_lock_info()
                if lock_info and lock_info.get('lock_id') == self.lock_id:
                    # Already our lock
                    return True
                
                if not wait:
                    return False
                    
                # Wait and try again
                time.sleep(poll_interval)
            
            if lock_data:
                # Check if lock is stale
                if self._is_lock_stale(lock_data):
                    # Remove stale lock
                    self._remove_lock_file()
                    lock_data = None
                else:
                    # Valid lock exists
                    self.lock_info = lock_data
                    
                    if not wait:
                        return False
                    
                    # Wait and retry
                    time.sleep(poll_interval)
                    continue
            
            # No valid lock exists, try to acquire
            if self._create_lock_file():
                self.lock_info = self._create_lock_data()
                return True
            
            # Race condition: another process created lock between check and create
            if not wait:
                return False
            
            time.sleep(poll_interval)
    
    def release(self):
        """
        Release the lock.
        
        Returns:
            bool: True if lock was released, False if lock doesn't exist or couldn't be removed
        """
        # Verify we own the lock before removing
        lock_data = self._read_lock_file()
        
        if not lock_data:
            # No lock file exists
            return False
        
        # Only remove if we own the lock
        if (lock_data.get('hostname') == self.hostname and 
            lock_data.get('pid') == self.pid):
            return self._remove_lock_file()
        
        # Lock is owned by another process
        return False
    
    def is_locked(self):
        """
        Check if file is currently locked.
        
        Returns:
            bool: True if file is locked (and lock is valid)
        """
        lock_data = self._read_lock_file()
        
        if not lock_data:
            return False
        
        if self._is_lock_stale(lock_data):
            # Stale lock, remove it
            self._remove_lock_file()
            return False
        
        self.lock_info = lock_data
        return True
    
    def get_lock_info(self):
        """
        Get information about current lock.
        
        Returns:
            dict: Lock information, or None if not locked
        """
        if self.is_locked():
            return self.lock_info
        return None
    
    def __enter__(self):
        """Context manager entry."""
        if not self.acquire():
            raise RuntimeError(
                f"Could not acquire lock for {self.file_path}. "
                f"Locked by {self.lock_info.get('hostname', 'unknown')} "
                f"at {self.lock_info.get('locked_at', 'unknown time')}"
            )
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        """Context manager exit."""
        self.release()
        return False


def cleanup_stale_locks(directory, timeout=300, lock_suffix=".mediabox.lock"):
    """
    Clean up all stale lock files in a directory.
    
    Args:
        directory: Directory to scan for lock files
        timeout: Lock timeout in seconds
        lock_suffix: Suffix for lock files
        
    Returns:
        int: Number of stale locks removed
    """
    directory = Path(directory)
    if not directory.is_dir():
        return 0
    
    removed_count = 0
    
    # Find all lock files
    for lock_file in directory.rglob(f"*{lock_suffix}"):
        try:
            # Read lock data
            with open(lock_file, 'r') as f:
                lock_data = json.load(f)
            
            # Check if stale
            lock_time = lock_data.get('timestamp', 0)
            if time.time() - lock_time > timeout:
                # Remove stale lock
                lock_file.unlink()
                removed_count += 1
        except (json.JSONDecodeError, IOError, OSError):
            # Invalid or unreadable lock file, try to remove
            try:
                lock_file.unlink()
                removed_count += 1
            except (IOError, OSError):
                pass
    
    return removed_count


if __name__ == "__main__":
    # Simple test
    import sys
    
    if len(sys.argv) < 2:
        print("Usage: python3 file_lock.py <file_path>")
        sys.exit(1)
    
    test_file = sys.argv[1]
    
    print(f"Testing file lock for: {test_file}")
    
    lock = FileLock(test_file, timeout=10)
    
    # Check if locked
    if lock.is_locked():
        info = lock.get_lock_info()
        print(f"File is locked by {info['hostname']} (PID {info.get('pid')})")
        print(f"Locked at: {info['locked_at']}")
    else:
        print("File is not locked")
    
    # Try to acquire
    print("\nAttempting to acquire lock...")
    if lock.acquire():
        print(f"Lock acquired by {lock.hostname} (PID {lock.pid})")
        print("Waiting 3 seconds...")
        time.sleep(3)
        print("Releasing lock...")
        lock.release()
        print("Lock released")
    else:
        print("Could not acquire lock")
