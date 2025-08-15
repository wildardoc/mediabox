#!/usr/bin/env python3
"""
Interactive Token Retrieval Demo (Safe)
=======================================

This script safely demonstrates the interactive token retrieval process
without actually making real authentication attempts.
"""

import getpass
import sys

def demo_interactive_token_retrieval():
    """Demonstrate the interactive token retrieval process safely"""
    
    print("🎬 Interactive Plex Token Retrieval Demo")
    print("=" * 45)
    print()
    
    print("This demonstrates what happens when a new user runs:")
    print("  python3 get-plex-token.py --interactive")
    print()
    print("=" * 45)
    print()
    
    # Step 1: Connection test
    print("1. Testing connection to: http://localhost:32400")
    print("❌ Connection failed: Authentication required or invalid token")
    print("ℹ️  Server requires authentication - you'll need MyPlex credentials")
    print()
    
    # Step 2: Interactive credential collection  
    print("2. MyPlex Account Setup")
    print("=" * 25)
    print()
    print("To retrieve a Plex token, you need your MyPlex account credentials.")
    print("These are the same credentials you use to sign in at plex.tv")
    print()
    
    # Demonstrate the prompts (but don't actually collect real credentials)
    print(">>> MyPlex username (email): ", end="")
    demo_username = input()
    
    if not demo_username:
        print("❌ Username is required for token retrieval")
        return
    
    # Safe password demo - don't actually collect password
    print(">>> MyPlex password for " + demo_username + ": ", end="")
    print("(password would be hidden)")
    demo_password = "demo_password_hidden"
    
    print()
    print("3. Retrieving authentication token...")
    print(f"🔐 Authenticating with MyPlex account: {demo_username}")
    
    # Simulate the authentication process
    if demo_username == "demo@example.com":
        # Successful demo case
        demo_token = "AbCdEf123456XyZ789"
        print("✅ MyPlex authentication successful")
        print(f"🔑 Retrieved authentication token: {demo_token[:10]}...")
        print("🔗 Testing token with local Plex server...")
        print("✅ Token retrieved successfully!")
        print("   Method: Retrieved via MyPlex account (Demo Plex Server)")
        print(f"   Token: {demo_token}")
        print()
        print("4. Validating token...")
        print("✅ Token validation successful")
        print()
        print("=" * 50)
        print("🎯 Configuration for your .env file:")
        print("=" * 50)
        print("PLEX_URL=http://localhost:32400")
        print(f"PLEX_TOKEN={demo_token}")
        print("=" * 50)
        print()
        print("💡 Copy the lines above to your .env file")
        print("   Or run: ./scripts/setup-plex-notifications.sh")
        
    else:
        # Demo error case
        print("❌ Could not retrieve token: MyPlex authentication failed: Invalid credentials")
        print()
        print("🔧 Alternative token retrieval methods:")
        print("1. Open: http://localhost:32400/web")
        print("2. Sign in to your Plex account")
        print("3. Open browser developer tools (F12)")
        print("4. Look for 'X-Plex-Token' in network requests")
        print("5. Or visit: https://support.plex.tv/articles/204059436-finding-an-authentication-token-x-plex-token/")

def demo_real_interactive():
    """Show the actual interactive script in action"""
    
    print("\n" + "=" * 50)
    print("🚀 REAL Interactive Script Demo")
    print("=" * 50)
    print()
    print("To see the actual interactive script in action, run:")
    print("  python3 get-plex-token.py --interactive")
    print()
    print("Features:")
    print("✅ Prompts for MyPlex username/email")
    print("✅ Securely prompts for password (hidden input)")
    print("✅ Authenticates with plex.tv")
    print("✅ Retrieves actual authentication token")
    print("✅ Tests token with your local Plex server")
    print("✅ Outputs ready-to-use .env configuration")
    print()
    print("Safe to test with:")
    print("- Valid MyPlex credentials (creates working token)")
    print("- Invalid credentials (demonstrates error handling)")
    print("- Ctrl+C to cancel at any time")

def main():
    print("Choose demo type:")
    print("1. Safe simulation (no real authentication)")
    print("2. Information about real interactive mode")
    print()
    
    choice = input("Enter choice (1 or 2): ").strip()
    print()
    
    if choice == "1":
        demo_interactive_token_retrieval()
    elif choice == "2":
        demo_real_interactive()
    else:
        print("Invalid choice. Run script again with 1 or 2.")
        sys.exit(1)
    
    print()
    print("🎉 Demo complete!")

if __name__ == "__main__":
    main()
