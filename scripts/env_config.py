#!/usr/bin/env python3
"""
Shared environment and config-loading helpers for mediabox automation scripts.

Centralizes .env parsing, mediabox_config.json loading/validation, and
container-vs-host environment detection so individual scripts (media_update.py,
remove_files.py, deluge-cleanup-orphaned.py, ...) don't each reimplement their
own version of "read a value out of .env".
"""

import os
import json


def load_env_file(env_file=None):
    """Load KEY=VALUE pairs from a .env file into os.environ.

    Variables already present in os.environ take precedence (not overwritten).
    Returns True if a file was found and loaded, False otherwise.
    """
    if env_file is None:
        env_file = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '.env')

    if not os.path.exists(env_file):
        return False

    try:
        with open(env_file, 'r') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    key, value = line.split('=', 1)
                    key = key.strip()
                    value = value.strip()

                    if (value.startswith('"') and value.endswith('"')) or \
                       (value.startswith("'") and value.endswith("'")):
                        value = value[1:-1]

                    if key not in os.environ:
                        os.environ[key] = value
        return True
    except Exception as e:
        print(f"Warning: Failed to load .env file: {e}")
        return False


def get_env_value(key, default=None, env_file=None):
    """Read a single KEY=VALUE from a .env file without touching os.environ.

    For scripts that only need one or two values (e.g. IP_ADDRESS) and don't
    want to load the whole file into the process environment.
    """
    if env_file is None:
        env_file = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '.env')
    try:
        if os.path.exists(env_file):
            with open(env_file) as f:
                for line in f:
                    line = line.strip()
                    if line.startswith(f'{key}='):
                        return line.split('=', 1)[1].strip().strip('"').strip("'")
    except Exception:
        pass
    return default


def detect_container_environment():
    """Detect if running inside a Docker container and identify which one.

    Returns (is_container, container_type). container_type is one of
    'sonarr', 'radarr', 'lidarr', 'unknown', or None (when not in a container).
    """
    script_dir = os.path.dirname(os.path.abspath(__file__))
    is_container = script_dir == "/scripts"

    if not is_container:
        print(f"DEBUG: Running on host environment (script_dir: {script_dir})")
        return False, None

    if os.path.exists('/tv') and not os.path.exists('/movies') and not os.path.exists('/music'):
        container_type = 'sonarr'
    elif os.path.exists('/movies') and not os.path.exists('/tv') and not os.path.exists('/music'):
        container_type = 'radarr'
    elif os.path.exists('/music') and not os.path.exists('/tv') and not os.path.exists('/movies'):
        container_type = 'lidarr'
    else:
        container_type = 'unknown'

    print(f"DEBUG: Running in Docker container environment ({container_type})")
    return True, container_type


def adapt_config_for_environment(config):
    """Adapt configuration paths based on execution environment (container vs host)."""
    is_container, container_type = detect_container_environment()

    if not is_container:
        return config

    adapted_config = config.copy()
    adapted_config['venv_path'] = "/scripts/.venv"
    adapted_config['library_dirs'] = {
        'tv': '/tv',
        'movies': '/movies',
        'music': '/music',
        'misc': '/misc',
    }
    adapted_config['download_dirs'] = [
        '/downloads/completed',
        '/downloads/incomplete',
    ]

    print(f"DEBUG: Adapted venv_path from {config['venv_path']} to {adapted_config['venv_path']}")
    print(f"DEBUG: Adapted library_dirs for container environment ({container_type})")
    return adapted_config


def validate_config(config):
    """Validate configuration structure and paths. Raises ValueError on
    structural problems (missing keys, wrong types, missing venv_path)."""
    required_keys = ['venv_path', 'download_dirs', 'library_dirs']
    for key in required_keys:
        if key not in config:
            raise ValueError(f"Missing required configuration key: {key}")

    if not os.path.exists(config['venv_path']):
        raise ValueError(f"Virtual environment path does not exist: {config['venv_path']}")

    is_container, container_type = detect_container_environment()

    if not isinstance(config['download_dirs'], list):
        raise ValueError("'download_dirs' must be a list")

    if not is_container:  # Only validate download dirs on host
        for path in config['download_dirs']:
            if not os.path.exists(path):
                print(f"Warning: Download directory does not exist: {path}")

    if not isinstance(config['library_dirs'], dict):
        raise ValueError("'library_dirs' must be a dictionary")

    # Smart validation based on container type
    if is_container and container_type:
        validation_map = {
            'sonarr': ['tv'],
            'radarr': ['movies'],
            'lidarr': ['music'],
        }
        lib_keys_to_check = validation_map.get(container_type, ['tv', 'movies', 'music'])
        print(f"DEBUG: Validating only {lib_keys_to_check} directories for {container_type} container")
    else:
        lib_keys_to_check = ['tv', 'movies', 'music']

    for lib_key in lib_keys_to_check:
        if lib_key not in config['library_dirs']:
            print(f"Warning: Missing library directory key: {lib_key}")
        else:
            lib_path = config['library_dirs'][lib_key]
            if not os.path.exists(lib_path):
                print(f"Warning: Library directory does not exist: {lib_path}")

    return config


def load_config(config_path):
    """Load mediabox_config.json, adapt it for the current environment
    (container vs host), and validate it."""
    try:
        with open(config_path, "r") as f:
            config = json.load(f)
        config = adapt_config_for_environment(config)
        config = validate_config(config)
        return config
    except FileNotFoundError:
        raise FileNotFoundError(f"Configuration file not found: {config_path}")
    except json.JSONDecodeError as e:
        raise ValueError(f"Invalid JSON in configuration file: {e}")
    except Exception as e:
        raise ValueError(f"Configuration validation failed: {e}")
