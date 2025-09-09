#!/usr/bin/env python3
"""
Test GPU hardware acceleration detection
"""

import os
import subprocess
import logging

# Set up logging
logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')

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
        # Check if GPU devices are available
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
            # Use optimized software settings for older systems
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

if __name__ == "__main__":
    print("Testing GPU Hardware Acceleration Detection...")
    print("=" * 50)
    
    result = detect_hardware_acceleration()
    
    print(f"Detection Results:")
    print(f"  Available: {result['available']}")
    print(f"  Method: {result['method']}")
    print(f"  Encoder: {result['encoder']}")
    print(f"  Extra Args: {result['extra_args']}")
    
    if result['method'] == 'vaapi':
        print("\n✅ VAAPI hardware acceleration will be used")
    elif result['method'] == 'software_optimized':
        print("\n⚡ Optimized software encoding will be used")
    else:
        print("\n🔧 Basic software encoding fallback")
        
    print("\nThis configuration will be automatically applied in media_update.py")
