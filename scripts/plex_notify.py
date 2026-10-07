#!/usr/bin/env python3
"""
Plex library-notification helpers shared by mediabox automation scripts.

Handles container-path-to-Plex-path translation, library-section matching,
and triggering scans/refreshes via PlexAPI after media_update.py converts a
file. Configured entirely through environment variables (PLEX_URL,
PLEX_TOKEN, PLEX_*), so it has no dependency on any script's own config dict.
"""

import os
import time
import logging
import subprocess

# Files processed during the current run, queued up for a single batched
# Plex notification at the end instead of one scan request per file.
processed_files = []


def convert_host_path_to_plex_path(container_path):
    """
    Convert container file path to Plex container path for library matching.

    When running in containers, both media_update.py and Plex run in containers
    with different mount points:

    *arr containers see:           Plex container sees:
        /tv/Show/file.mkv      →      /data/tv/Show/file.mkv
        /movies/Movie/file.mkv →      /data/movies/Movie/file.mkv
        /music/Artist/file.mp3 →      /data/music/Artist/file.mp3

    Args:
        container_path (str): File path as seen by *arr/media_update containers

    Returns:
        str: Corresponding path as Plex container sees it
    """
    # Host path mappings (when running on host system)
    if container_path.startswith('/Storage/media/tv/'):
        plex_path = container_path.replace('/Storage/media/tv/', '/data/tv/', 1)
        logging.debug(f"Host to Plex path: {container_path} → {plex_path}")
        return plex_path
    elif container_path.startswith('/Storage/media/movies/'):
        plex_path = container_path.replace('/Storage/media/movies/', '/data/movies/', 1)
        logging.debug(f"Host to Plex path: {container_path} → {plex_path}")
        return plex_path
    elif container_path.startswith('/Storage/media/music/'):
        plex_path = container_path.replace('/Storage/media/music/', '/data/music/', 1)
        logging.debug(f"Host to Plex path: {container_path} → {plex_path}")
        return plex_path

    # Container-to-container path mapping (when running in containers)
    elif container_path.startswith('/tv/'):
        plex_path = container_path.replace('/tv/', '/data/tv/', 1)
        logging.debug(f"Container to Plex path: {container_path} → {plex_path}")
        return plex_path
    elif container_path.startswith('/movies/'):
        plex_path = container_path.replace('/movies/', '/data/movies/', 1)
        logging.debug(f"Container to Plex path: {container_path} → {plex_path}")
        return plex_path
    elif container_path.startswith('/music/'):
        plex_path = container_path.replace('/music/', '/data/music/', 1)
        logging.debug(f"Container to Plex path: {container_path} → {plex_path}")
        return plex_path
    else:
        logging.debug(f"No path mapping needed for: {container_path}")
        return container_path


def detect_library_type(path):
    """Detect Plex library type based on file path."""
    path_lower = path.lower()
    if '/storage/media/movies/' in path_lower or '/data/movies/' in path_lower or '/movies/' in path_lower:
        return 'movie'
    elif '/storage/media/tv/' in path_lower or '/data/tv/' in path_lower or '/tv/' in path_lower:
        return 'show'
    elif '/storage/media/music/' in path_lower or '/data/music/' in path_lower or '/music/' in path_lower:
        return 'artist'
    else:
        # Fallback: try to guess from path structure
        if 'movie' in path_lower:
            return 'movie'
        elif any(x in path_lower for x in ['tv', 'show', 'series', 'season', 'episode']):
            return 'show'
        elif any(x in path_lower for x in ['music', 'album', 'artist']):
            return 'artist'
        return None


def notify_plex_library_update(file_path, max_retries=2, retry_delay=5, force_refresh=False):
    """Enhanced Plex notification with smart scanning, validation, and thorough refresh support.

    Args:
        file_path: Path to the media file
        max_retries: Number of retry attempts
        retry_delay: Delay between retries
        force_refresh: If True, forces thorough metadata refresh for audio stream changes
    """
    plex_url = os.getenv('PLEX_URL', 'http://192.168.86.2:32400')
    plex_token = os.getenv('PLEX_TOKEN', '')

    if not plex_token:
        logging.warning("PLEX_TOKEN not set. Skipping Plex notification.")
        return False

    smart_scanning = os.getenv('PLEX_SMART_SCANNING', 'true').lower() == 'true'
    detailed_logging = os.getenv('PLEX_DETAILED_LOGGING', 'true').lower() == 'true'

    # Convert host path to Plex container path for better matching
    plex_file_path = convert_host_path_to_plex_path(file_path)

    expected_library_type = detect_library_type(file_path)
    logging.info(f"🔍 Detected library type: {expected_library_type} for path: {file_path}")

    for attempt in range(1, max_retries + 1):
        try:
            # Import PlexAPI components inside try block to avoid scoping issues
            from plexapi.server import PlexServer
            from plexapi.exceptions import PlexApiException, Unauthorized, BadRequest

            logging.info(f"🔌 Connecting to Plex server: {plex_url}")
            plex = PlexServer(plex_url, plex_token, timeout=15)

            if detailed_logging:
                logging.info(f"📺 Connected to Plex: {plex.friendlyName}")

            # Get library sections
            sections = plex.library.sections()
            matched_section = None

            # Enhanced library matching logic - prioritize by library type
            for section in sections:
                if detailed_logging:
                    logging.info(f"📚 Checking library: {section.title} ({section.type})")
                    for location in section.locations:
                        logging.info(f"   📁 Library path: {location}")

                # First, try to match by library type
                if expected_library_type and section.type == expected_library_type:
                    # Then check if path matches
                    for location in section.locations:
                        if plex_file_path.startswith(location) or file_path.startswith(location):
                            matched_section = section
                            logging.info(f"✅ Found matching library: {section.title} (type: {section.type})")
                            break

                    if matched_section:
                        break

            # If no type-specific match, fall back to path matching
            if not matched_section:
                for section in sections:
                    for location in section.locations:
                        if plex_file_path.startswith(location) or file_path.startswith(location):
                            matched_section = section
                            logging.info(f"✅ Found matching library: {section.title} (fallback path match)")
                            break

                    if matched_section:
                        break

            if not matched_section:
                logging.warning(f"⚠️ No matching Plex library found for: {plex_file_path}")
                logging.warning(f"   Host path: {file_path}")
                logging.warning(f"   Expected library type: {expected_library_type}")
                return False

            # Enhanced scanning logic with thorough refresh support
            if force_refresh:
                logging.info(f"🔄 Force refresh enabled - performing thorough metadata refresh")
                try:
                    file_dir = os.path.dirname(plex_file_path)
                    filename_without_ext = os.path.splitext(os.path.basename(plex_file_path))[0]

                    # Enhanced search logic for different media types
                    media_item = None

                    if expected_library_type == 'show':
                        # For TV shows, try multiple search strategies
                        # 1. Search by show name (extract from path or filename)
                        show_name = None
                        path_parts = plex_file_path.split('/')
                        for part in path_parts:
                            if part and not part.startswith('Season'):
                                show_name = part
                                break

                        if show_name:
                            logging.info(f"🔍 Searching for TV show: {show_name}")
                            show_results = matched_section.search(show_name)
                            if show_results:
                                show = show_results[0]
                                logging.info(f"📺 Found show: {show.title}")

                                # Search for specific episode within the show
                                try:
                                    # Extract season/episode info from filename
                                    import re
                                    episode_match = re.search(r'S(\d+)E(\d+)', filename_without_ext, re.IGNORECASE)
                                    if episode_match:
                                        season_num = int(episode_match.group(1))
                                        episode_num = int(episode_match.group(2))

                                        # Try to find the specific episode
                                        for season in show.seasons():
                                            if season.seasonNumber == season_num:
                                                for episode in season.episodes():
                                                    if episode.episodeNumber == episode_num:
                                                        media_item = episode
                                                        logging.info(f"🎯 Found specific episode: {episode.title}")
                                                        break
                                                break
                                except Exception as e:
                                    logging.debug(f"Episode search failed: {e}")

                                # If episode not found, refresh the show
                                if not media_item:
                                    media_item = show
                                    logging.info(f"📺 Using show for refresh: {show.title}")
                    else:
                        # For movies and other media, use filename search
                        search_results = matched_section.search(filename_without_ext)
                        if search_results:
                            media_item = search_results[0]
                            logging.info(f"🎯 Found specific media item: {media_item.title}")

                    # Perform thorough refresh if item found
                    if media_item:
                        # Multiple refresh approaches for maximum effectiveness
                        media_item.refresh()
                        logging.info(f"🔄 Triggered metadata refresh for: {media_item.title}")

                        # For TV shows, also refresh at show level if we found an episode
                        if expected_library_type == 'show' and hasattr(media_item, 'show'):
                            media_item.show().refresh()
                            logging.info(f"📺 Also refreshed show: {media_item.show().title}")

                    # Always perform directory update as additional measure
                    matched_section.update(path=file_dir)
                    logging.info(f"📁 Updated directory: {file_dir}")

                    # Brief delay to allow Plex to process the update
                    time.sleep(2)

                    # For maximum effectiveness, also trigger section refresh
                    matched_section.refresh()
                    logging.info(f"📚 Triggered section refresh for: {matched_section.title}")

                except Exception as refresh_error:
                    logging.warning(f"⚠️ Enhanced refresh failed: {refresh_error}")
                    logging.info(f"🔄 Falling back to aggressive directory refresh")
                    file_dir = os.path.dirname(plex_file_path)
                    matched_section.update(path=file_dir)
                    matched_section.refresh()
                    logging.info(f"📚 Performed fallback section refresh")

            elif smart_scanning:
                file_dir = os.path.dirname(plex_file_path)
                logging.info(f"🎯 Smart scanning directory: {file_dir}")
                matched_section.update(path=file_dir)
            else:
                logging.info(f"📚 Full library scan: {matched_section.title}")
                matched_section.update()

            refresh_type = "thorough refresh" if force_refresh else ("smart scan" if smart_scanning else "full scan")
            logging.info(f"✅ Successfully triggered Plex {refresh_type} for {matched_section.title} ({matched_section.type})")
            return True

        except ImportError as e:
            logging.error(f"❌ PlexAPI not available: {e}")
            return False

        except Exception as e:
            if "Unauthorized" in str(e) or "401" in str(e):
                logging.error(f"❌ Plex authentication failed: {e}")
                return False
            elif attempt < max_retries:
                logging.error(f"❌ Plex error (attempt {attempt}): {e}")
                logging.info(f"🔄 Retrying in {retry_delay} seconds...")
                time.sleep(retry_delay)
                continue
            else:
                logging.error(f"❌ Failed to notify Plex after {max_retries} attempts: {e}")
                return False

    return False


def should_force_refresh_for_section(files):
    """
    Determine if files in a section likely need thorough Plex refresh.
    This checks for indicators that multi-channel audio processing occurred.

    Args:
        files: List of processed file paths

    Returns:
        bool: True if thorough refresh should be forced
    """
    for file_path in files[:3]:  # Check up to 3 files to avoid excessive probing
        try:
            # Quick probe to check for multiple audio streams
            result = subprocess.run([
                'ffprobe', '-v', 'quiet', '-select_streams', 'a',
                '-show_entries', 'stream=channels', '-of', 'csv=p=0',
                file_path
            ], capture_output=True, text=True, timeout=10)

            if result.returncode == 0:
                audio_channels = result.stdout.strip().split('\n')
                # If we have multiple audio streams or channels suggesting 5.1 + stereo
                if len(audio_channels) >= 2:
                    channel_counts = [int(ch) for ch in audio_channels if ch.isdigit()]
                    # Look for pattern of surround (5.1 = 6ch) + stereo (2ch)
                    if len(channel_counts) >= 2 and (6 in channel_counts or 8 in channel_counts):
                        logging.info(f"🔄 Detected multi-channel setup in {os.path.basename(file_path)} - forcing thorough refresh")
                        return True

        except Exception as e:
            logging.debug(f"Could not probe {file_path} for audio streams: {e}")
            continue

    return False


def _env_bool(key, default):
    val = os.getenv(key)
    if val is None:
        return default
    return val.strip().lower() in ('true', 'yes', '1', 'on')


def batch_notify_plex():
    """
    Perform batch Plex notifications for all processed files with smart refresh detection.
    This reduces the number of individual scan requests to Plex while ensuring
    thorough refreshes for files with multiple audio streams.

    Reads ENABLE_PLEX_NOTIFICATIONS / PLEX_FORCE_THOROUGH_REFRESH from the
    process environment (already populated from .env by env_config.load_env_file()
    at script startup), rather than re-reading .env itself.

    Returns:
        bool: True if any notifications were successful, False otherwise
    """
    global processed_files

    if not processed_files:
        return True

    enable_notifications = _env_bool('ENABLE_PLEX_NOTIFICATIONS', True)
    force_thorough_refresh = _env_bool('PLEX_FORCE_THOROUGH_REFRESH', True)

    if not enable_notifications:
        logging.info(f"Plex notifications disabled for {len(processed_files)} processed files")
        processed_files.clear()
        return True

    logging.info(f"Performing batch Plex notification for {len(processed_files)} files")

    # Group files by likely library section to minimize scans
    library_sections = {
        'tv': [],
        'movies': [],
        'music': []
    }

    for file_path in processed_files:
        file_path_lower = file_path.lower()
        if 'tv' in file_path_lower or '/tv/' in file_path_lower:
            library_sections['tv'].append(file_path)
        elif 'movie' in file_path_lower or '/movies/' in file_path_lower:
            library_sections['movies'].append(file_path)
        elif 'music' in file_path_lower or '/music/' in file_path_lower:
            library_sections['music'].append(file_path)
        else:
            # Default to TV if we can't determine
            library_sections['tv'].append(file_path)

    success = False
    for section_type, files in library_sections.items():
        if files:
            # Pick one representative file to trigger the section scan
            representative_file = files[0]

            # Check if any files in this section likely have multiple audio streams
            force_refresh = force_thorough_refresh and should_force_refresh_for_section(files)

            if notify_plex_library_update(representative_file, max_retries=1, force_refresh=force_refresh):
                refresh_type = "thorough refresh" if force_refresh else "standard scan"
                logging.info(f"Successfully triggered {section_type} {refresh_type} for {len(files)} files")
                success = True
            else:
                logging.warning(f"Failed to trigger {section_type} library scan for {len(files)} files")

    # Clear the processed files list
    processed_files.clear()

    return success
