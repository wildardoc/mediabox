#!/usr/bin/env python3
"""
Plex Token Retrieval Script
===========================

This script helps automatically retrieve a Plex authentication token using
the PlexAPI library. It supports multiple methods:

1. Using existing server connection (if token already exists)
2. Using MyPlex account credentials
3. Manual token input with validation

Usage:
------
python3 get-plex-token.py --url http://localhost:32400
python3 get-plex-token.py --url http://192.168.86.2:32400 --username your_username
python3 get-plex-token.py --interactive

Virtual Environment:
-------------------
This script automatically activates the configured virtual environment from
mediabox_config.json if available, ensuring all dependencies are accessible.
"""

import sys
import os
import argparse
import getpass
import requests
import re
from urllib.parse import urlparse

# Auto-activate virtual environment if configured
def setup_virtual_environment():
    """Activate virtual environment if configured in mediabox_config.json"""
    try:
        import json
        config_file = os.path.join(os.path.dirname(__file__), 'mediabox_config.json')
        
        if os.path.exists(config_file):
            with open(config_file, 'r') as f:
                config = json.load(f)
            
            venv_path = config.get('venv_path')
            if venv_path and os.path.exists(venv_path):
                # Add venv site-packages to Python path
                import site
                venv_site_packages = os.path.join(venv_path, 'lib', 'python' + 
                                                sys.version[:3], 'site-packages')
                if os.path.exists(venv_site_packages):
                    site.addsitedir(venv_site_packages)
    except Exception:
        # If venv setup fails, continue without it
        pass

# Setup virtual environment before importing dependencies
setup_virtual_environment()

def test_plex_connection(url, token=None):
    """Test if Plex server is accessible and optionally validate token"""
    try:
        headers = {}
        if token:
            headers['X-Plex-Token'] = token
            
        response = requests.get(f"{url}/library/sections", headers=headers, timeout=10)
        if response.status_code == 200:
            return True, "Connection successful"
        elif response.status_code == 401:
            return False, "Authentication required or invalid token"
        else:
            return False, f"HTTP {response.status_code}: {response.text}"
    except requests.exceptions.RequestException as e:
        return False, f"Connection error: {e}"

def get_token_via_plexapi(url, username=None, password=None):
    """Get token using PlexAPI library"""
    try:
        from plexapi.server import PlexServer
        from plexapi.myplex import MyPlexAccount
        
        if username and password:
            print(f"🔐 Authenticating with MyPlex account: {username}")
            try:
                account = MyPlexAccount(username, password)
                print(f"✅ MyPlex authentication successful")
                
                # Get the token from the account
                token = account.authenticationToken
                print(f"🔑 Retrieved authentication token: {token[:10]}...")
                
                # Now try to connect to the local server with this token
                print(f"🔗 Testing token with local Plex server...")
                plex = PlexServer(url, token)
                
                return token, f"Retrieved via MyPlex account ({plex.friendlyName})"
                
            except Exception as e:
                return None, f"MyPlex authentication failed: {e}"
        else:
            # Try to connect without authentication first (rare case)
            print(f"🔍 Testing direct connection to: {url}")
            try:
                plex = PlexServer(url)
                token = getattr(plex, '_token', None) or getattr(plex, 'token', None)
                if token:
                    return token, f"Direct connection ({plex.friendlyName})"
                else:
                    return None, "Server accessible but no token available (authentication required)"
            except Exception as e:
                return None, f"Direct connection failed: {e}"
            
    except ImportError:
        return None, "PlexAPI library not available. Install with: pip install PlexAPI"
    except Exception as e:
        return None, f"PlexAPI error: {e}"

def load_credentials_from_file(credentials_file):
    """Load credentials from the secure credentials file"""
    credentials = {}
    try:
        with open(credentials_file, 'r') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    key, value = line.split('=', 1)
                    credentials[key] = value
        return credentials
    except Exception as e:
        print(f"❌ Failed to read credentials file {credentials_file}: {e}")
        return None

def main():
    parser = argparse.ArgumentParser(description='Retrieve Plex authentication token')
    parser.add_argument('--url', default='http://localhost:32400', 
                       help='Plex server URL (default: http://localhost:32400)')
    parser.add_argument('--username', help='MyPlex username (optional)')
    parser.add_argument('--interactive', action='store_true',
                       help='Interactive mode - prompts for credentials')
    parser.add_argument('--auto-credential-env', action='store_true',
                       help='Automatic mode - read credentials from environment variables')
    parser.add_argument('--auto-credential-file', 
                       help='Automatic mode - read credentials from specified file')
    parser.add_argument('--test-only', action='store_true', 
                       help='Only test connection, don\'t retrieve token')
    
    args = parser.parse_args()
    
    # Handle auto-credential-file mode
    if args.auto_credential_file:
        credentials_file = args.auto_credential_file
        credentials = load_credentials_from_file(credentials_file)
        
        if not credentials:
            sys.exit(1)
            
        username = credentials.get('PLEX_USERNAME')
        password = credentials.get('PLEX_PASSWORD')
        
        if not username or not password:
            print("❌ PLEX_USERNAME and PLEX_PASSWORD not found in credentials file")
            sys.exit(1)
            
        # Suppress normal output for automatic mode
        token, method = get_token_via_plexapi(args.url, username, password)
        
        if token:
            # Store token in .env file
            env_file = os.path.join(os.path.dirname(__file__), '..', '.env')
            try:
                # Read existing .env content
                env_content = ""
                if os.path.exists(env_file):
                    with open(env_file, 'r') as f:
                        env_content = f.read()
                
                # Check if PLEX_TOKEN already exists
                if 'PLEX_TOKEN=' in env_content:
                    # Update existing token
                    env_content = re.sub(r'PLEX_TOKEN=.*', f'PLEX_TOKEN={token}', env_content)
                else:
                    # Add new token
                    env_content += f"\nPLEX_TOKEN={token}\n"
                
                # Add PLEX_URL if not exists
                if 'PLEX_URL=' not in env_content:
                    env_content += f"PLEX_URL={args.url}\n"
                elif args.url != 'http://localhost:32400':  # Update if non-default
                    env_content = re.sub(r'PLEX_URL=.*', f'PLEX_URL={args.url}', env_content)
                
                # Write updated content
                with open(env_file, 'w') as f:
                    f.write(env_content)
                
                sys.exit(0)  # Success
            except Exception as e:
                print(f"❌ Failed to update .env file: {e}")
                sys.exit(1)
        else:
            sys.exit(1)  # Failed to get token
    
    # Handle auto-credential-env mode
    if args.auto_credential_env:
        username = os.environ.get('PLEX_USERNAME')
        password = os.environ.get('PLEX_PASSWORD')
        
        if not username or not password:
            print("❌ PLEX_USERNAME and PLEX_PASSWORD environment variables required for --auto-credential-env mode")
            sys.exit(1)
            
        # Suppress normal output for automatic mode
        token, method = get_token_via_plexapi(args.url, username, password)
        
        if token:
            # Store token in .env file
            env_file = os.path.join(os.path.dirname(__file__), '..', '.env')
            try:
                # Read existing .env content
                env_content = ""
                if os.path.exists(env_file):
                    with open(env_file, 'r') as f:
                        env_content = f.read()
                
                # Check if PLEX_TOKEN already exists
                if 'PLEX_TOKEN=' in env_content:
                    # Update existing token
                    env_content = re.sub(r'PLEX_TOKEN=.*', f'PLEX_TOKEN={token}', env_content)
                else:
                    # Add new token
                    env_content += f"\nPLEX_TOKEN={token}\n"
                
                # Add PLEX_URL if not exists
                if 'PLEX_URL=' not in env_content:
                    env_content += f"PLEX_URL={args.url}\n"
                elif args.url != 'http://localhost:32400':  # Update if non-default
                    env_content = re.sub(r'PLEX_URL=.*', f'PLEX_URL={args.url}', env_content)
                
                # Write updated content
                with open(env_file, 'w') as f:
                    f.write(env_content)
                
                sys.exit(0)  # Success
            except Exception as e:
                print(f"❌ Failed to update .env file: {e}")
                sys.exit(1)
        else:
            sys.exit(1)  # Failed to get token
    
    print("🎬 Plex Token Retrieval")
    print("=" * 30)
    
    # Parse and validate URL
    parsed_url = urlparse(args.url)
    if not parsed_url.scheme or not parsed_url.netloc:
        print(f"❌ Invalid URL: {args.url}")
        sys.exit(1)
    
    # Test basic connectivity
    print(f"1. Testing connection to: {args.url}")
    connected, message = test_plex_connection(args.url)
    if not connected:
        print(f"❌ Connection failed: {message}")
        if "Authentication required" in message:
            print("ℹ️  Server requires authentication - you'll need MyPlex credentials")
            print("   Continuing with credential setup...")
        else:
            print("❌ Cannot reach Plex server. Please check the URL and ensure Plex is running.")
            sys.exit(1)
    else:
        print(f"✅ {message}")
    
    if args.test_only:
        if connected:
            print("✅ Connection test complete")
        else:
            print("❌ Connection test failed - server requires authentication")
        return
    
    # Interactive mode or command line arguments
    username = args.username
    password = None
    
    if args.interactive or not username:
        print("\n2. MyPlex Account Setup")
        print("=" * 25)
        
        if not username:
            print("To retrieve a Plex token, you need your MyPlex account credentials.")
            print("These are the same credentials you use to sign in at plex.tv")
            print()
            username = input("MyPlex username (email): ").strip()
            
        if not username:
            print("❌ Username is required for token retrieval")
            sys.exit(1)
            
        password = getpass.getpass(f"MyPlex password for {username}: ")
        
        if not password:
            print("❌ Password is required for token retrieval")
            sys.exit(1)
    else:
        # Non-interactive mode with username provided
        password = getpass.getpass(f"Enter password for {username}: ")
    
    # Try to get token via PlexAPI
    print(f"\n3. Retrieving authentication token...")
    
    token, method = get_token_via_plexapi(args.url, username, password)
    
    if token:
        print(f"✅ Token retrieved successfully!")
        print(f"   Method: {method}")
        print(f"   Token: {token}")
        
        # Validate the token works
        print("\n4. Validating token...")
        valid, validation_message = test_plex_connection(args.url, token)
        if valid:
            print(f"✅ Token validation successful")
            
            # Output in format suitable for .env file
            print("\n" + "=" * 50)
            print("🎯 Configuration for your .env file:")
            print("=" * 50)
            print(f"PLEX_URL={args.url}")
            print(f"PLEX_TOKEN={token}")
            print("=" * 50)
            print()
            print("💡 Copy the lines above to your .env file")
            print("   Or run: ./scripts/setup-plex-notifications.sh")
            
        else:
            print(f"❌ Token validation failed: {validation_message}")
            sys.exit(1)
    else:
        print(f"❌ Could not retrieve token: {method}")
        print("\n🔧 Alternative token retrieval methods:")
        print(f"1. Open: {args.url}/web")
        print("2. Sign in to your Plex account")
        print("3. Open browser developer tools (F12)")
        print("4. Look for 'X-Plex-Token' in network requests")
        print("5. Or visit: https://support.plex.tv/articles/204059436-finding-an-authentication-token-x-plex-token/")
        sys.exit(1)

if __name__ == "__main__":
    main()
