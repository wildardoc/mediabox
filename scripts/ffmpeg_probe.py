#!/usr/bin/env python3
"""
FFmpeg/ffprobe-related helpers shared by mediabox automation scripts:
HDR detection and HDR->SDR tone mapping, hardware acceleration detection,
and network-drive detection (used to avoid SMB/CIFS quirks during transcoding).
"""

import os
import platform
import subprocess
import logging


def detect_hdr_video(probe):
    """
    Detect if video stream contains HDR content (HDR10, HDR10+, Dolby Vision, HLG).

    Args:
        probe (dict): ffmpeg.probe() result dictionary

    Returns:
        dict: HDR information with keys:
            - is_hdr (bool): True if HDR content detected
            - hdr_type (str): Type of HDR (HDR10, HDR10+, Dolby Vision, HLG, or None)
            - color_transfer (str): Transfer characteristic (smpte2084, arib-std-b67, etc.)
            - color_primaries (str): Color primaries (bt2020, bt709, etc.)
            - color_space (str): Color space (bt2020nc, bt709, etc.)
            - pix_fmt (str): Pixel format (yuv420p10le, yuv420p, etc.)
            - bit_depth (int): Bit depth (8, 10, 12)
    """
    hdr_info = {
        'is_hdr': False,
        'hdr_type': None,
        'color_transfer': None,
        'color_primaries': None,
        'color_space': None,
        'pix_fmt': None,
        'bit_depth': 8
    }

    try:
        video_stream = next((s for s in probe['streams'] if s['codec_type'] == 'video'), None)
        if not video_stream:
            return hdr_info

        color_transfer = video_stream.get('color_transfer', '')
        color_primaries = video_stream.get('color_primaries', '')
        color_space = video_stream.get('color_space', '')
        pix_fmt = video_stream.get('pix_fmt', '')

        hdr_info['color_transfer'] = color_transfer
        hdr_info['color_primaries'] = color_primaries
        hdr_info['color_space'] = color_space
        hdr_info['pix_fmt'] = pix_fmt

        if '10le' in pix_fmt or '10be' in pix_fmt or 'p10' in pix_fmt:
            hdr_info['bit_depth'] = 10
        elif '12le' in pix_fmt or '12be' in pix_fmt or 'p12' in pix_fmt:
            hdr_info['bit_depth'] = 12
        else:
            hdr_info['bit_depth'] = 8

        if color_transfer == 'smpte2084':
            # PQ transfer function = HDR10/HDR10+
            hdr_info['is_hdr'] = True
            hdr_info['hdr_type'] = 'HDR10'
            logging.info(f"HDR10 content detected (PQ/SMPTE ST 2084 transfer)")
        elif color_transfer == 'arib-std-b67':
            # HLG transfer function
            hdr_info['is_hdr'] = True
            hdr_info['hdr_type'] = 'HLG'
            logging.info(f"HLG (Hybrid Log-Gamma) HDR content detected")
        elif color_primaries == 'bt2020' and hdr_info['bit_depth'] > 8:
            # BT.2020 color primaries with 10/12-bit = likely HDR even without explicit transfer
            hdr_info['is_hdr'] = True
            hdr_info['hdr_type'] = 'HDR (BT.2020)'
            logging.info(f"HDR content detected (BT.2020 color primaries, {hdr_info['bit_depth']}-bit)")

        # Check for Dolby Vision (side_data or codec-specific markers)
        if 'side_data_list' in video_stream:
            for side_data in video_stream['side_data_list']:
                if side_data.get('side_data_type') == 'DOVI configuration record':
                    hdr_info['is_hdr'] = True
                    hdr_info['hdr_type'] = 'Dolby Vision'
                    logging.info(f"Dolby Vision HDR content detected")
                    break

        return hdr_info

    except Exception as e:
        logging.warning(f"Error detecting HDR: {e}")
        return hdr_info


def build_hdr_tonemap_filter(hdr_info, scale_filter=None):
    """
    Build FFmpeg filter for HDR to SDR tone mapping.

    Args:
        hdr_info (dict): HDR information from detect_hdr_video()
        scale_filter (str, optional): Existing scale filter (e.g., 'scale=1920:-2')

    Returns:
        str: FFmpeg video filter string for tone mapping, or None if no tone mapping needed
    """
    if not hdr_info['is_hdr']:
        return scale_filter  # Return existing scale filter if provided, otherwise None

    # Build tone mapping filter using zscale - handles color space conversion
    # better than scale for HDR.
    tonemap_filters = []

    # Step 1: Convert to linear light (required for tone mapping)
    tonemap_filters.append('zscale=t=linear:npl=100')

    # Step 2: Apply tone mapping to compress HDR range to SDR.
    # Use Hable (filmic) tone mapping for natural results.
    tonemap_filters.append('format=gbrpf32le')
    tonemap_filters.append('zscale=p=bt709')
    tonemap_filters.append('tonemap=tonemap=hable:desat=0')

    # Step 3: Convert to SDR color space (BT.709)
    tonemap_filters.append('zscale=t=bt709:m=bt709:r=tv')

    # Step 4: Convert to 8-bit YUV 4:2:0 for compatibility
    tonemap_filters.append('format=yuv420p')

    # Step 5: Add scaling if requested
    if scale_filter:
        tonemap_filters.append(scale_filter.replace('scale=', 'scale=w=').replace(':', ':h='))

    filter_string = ','.join(tonemap_filters)
    logging.info(f"Built HDR→SDR tone mapping filter for {hdr_info['hdr_type']}")
    logging.debug(f"Tone mapping filter: {filter_string}")

    return filter_string


def detect_hardware_acceleration():
    """
    Detect available hardware acceleration methods for FFmpeg.
    Returns a dict with available acceleration options.
    """
    hwaccel_options = {
        'available': False,
        'method': 'software',
        'encoder': 'libx264',
        'extra_args': []
    }

    try:
        if not os.path.exists('/dev/dri'):
            logging.info("No GPU devices found (/dev/dri missing)")
            return hwaccel_options

        # Test VAAPI support
        test_cmd = [
            'ffmpeg', '-hide_banner', '-f', 'lavfi', '-i', 'testsrc2=duration=0.1:size=64x64:rate=1',
            '-vaapi_device', '/dev/dri/renderD128', '-vf', 'format=nv12,hwupload',
            '-c:v', 'h264_vaapi', '-t', '0.1', '-f', 'null', '-'
        ]

        result = subprocess.run(test_cmd, capture_output=True, text=True, timeout=10)
        if result.returncode == 0:
            logging.info("VAAPI hardware acceleration available")
            hwaccel_options.update({
                'available': True,
                'method': 'vaapi',
                'encoder': 'h264_vaapi',
                'extra_args': ['-vaapi_device', '/dev/dri/renderD128', '-vf', 'format=nv12,hwupload']
            })
            return hwaccel_options

    except (subprocess.TimeoutExpired, subprocess.SubprocessError, FileNotFoundError) as e:
        logging.debug(f"VAAPI test failed: {e}")

    try:
        # Test software encoding with optimized settings
        test_cmd = [
            'ffmpeg', '-hide_banner', '-f', 'lavfi', '-i', 'testsrc2=duration=0.1:size=64x64:rate=1',
            '-c:v', 'libx264', '-preset', 'medium', '-crf', '23', '-t', '0.1', '-f', 'null', '-'
        ]

        result = subprocess.run(test_cmd, capture_output=True, text=True, timeout=10)
        if result.returncode == 0:
            logging.info("Software encoding with x264 available")
            hwaccel_options.update({
                'available': True,
                'method': 'software_optimized',
                'encoder': 'libx264',
                'extra_args': ['-preset', 'medium', '-threads', '0']  # 0 = auto-detect threads
            })
            return hwaccel_options

    except (subprocess.TimeoutExpired, subprocess.SubprocessError) as e:
        logging.debug(f"Software encoding test failed: {e}")

    logging.warning("No suitable encoding method found, using basic software fallback")
    return hwaccel_options


def is_network_drive(path):
    """
    Detect if a path is on a network drive in a cross-platform way.
    Returns True if the path is on a network drive that might have SMB/CIFS issues on Windows.
    """
    try:
        abs_path = os.path.abspath(path)

        if platform.system() == "Windows":
            # Windows: Check if path starts with \\server\ (UNC) or is a mapped network drive
            if abs_path.startswith('\\\\'):
                return True

            # Check if it's a mapped network drive (like M:)
            drive_letter = abs_path[:2]  # e.g., "M:"
            if len(drive_letter) == 2 and drive_letter[1] == ':':
                try:
                    result = subprocess.run(['net', 'use', drive_letter],
                                          capture_output=True, text=True, timeout=5)
                    if result.returncode == 0 and ('Remote' in result.stdout or 'Microsoft Windows Network' in result.stdout):
                        return True
                except Exception:
                    pass
        else:
            # Linux/Unix: Check if path is mounted as NFS, SMB/CIFS, or other network FS
            try:
                result = subprocess.run(['mount'], capture_output=True, text=True, timeout=5)
                if result.returncode == 0:
                    mount_lines = result.stdout.split('\n')
                    for line in mount_lines:
                        if abs_path in line and ('nfs' in line or 'cifs' in line or 'smb' in line):
                            # NFS works fine, only return True for problematic ones
                            if 'cifs' in line or 'smb' in line:
                                return True
            except Exception:
                pass

        return False
    except Exception:
        return False
