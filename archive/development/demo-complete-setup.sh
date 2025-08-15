#!/bin/bash
"""
Complete Plex Setup Demonstration
=================================

This script demonstrates the complete end-to-end setup process for
new Mediabox installations, including interactive token retrieval.
"""

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"

echo "🎬 Mediabox Plex Setup - Complete Demo"
echo "=" * 45
echo

# Function to simulate new installation (backup existing .env)
setup_demo_environment() {
    echo "1. 📋 Simulating New Installation Environment"
    echo "=" * 45
    
    if [[ -f "$ENV_FILE" ]]; then
        echo "   Backing up existing .env to .env.backup"
        cp "$ENV_FILE" "$ENV_FILE.backup"
        
        # Create a temporary .env without Plex settings
        echo "   Creating demo environment without Plex configuration"
        grep -v "PLEX_" "$ENV_FILE" > "$ENV_FILE.demo" || true
        mv "$ENV_FILE.demo" "$ENV_FILE"
    fi
    
    echo "   ✅ Demo environment ready (Plex configuration removed)"
    echo
}

# Function to restore original environment
restore_environment() {
    echo "🔄 Restoring Original Environment"
    echo "=" * 35
    
    if [[ -f "$ENV_FILE.backup" ]]; then
        echo "   Restoring original .env file"
        mv "$ENV_FILE.backup" "$ENV_FILE"
        echo "   ✅ Original configuration restored"
    fi
    echo
}

# Function to demonstrate interactive token setup
demo_interactive_setup() {
    echo "2. 🔐 Interactive Token Retrieval Demo"
    echo "=" * 40
    echo
    echo "This is how a new user would get their Plex token:"
    echo
    
    # Check if we're in demo mode or real mode
    read -p "Run REAL token retrieval demo? (y/n): " demo_choice
    echo
    
    if [[ "$demo_choice" =~ ^[Yy]$ ]]; then
        echo "🚀 Running REAL interactive token retrieval..."
        echo "   (You can use test credentials or cancel with Ctrl+C)"
        echo
        
        # Run the actual token retrieval script in interactive mode
        if python3 "$SCRIPT_DIR/get-plex-token.py" --interactive --url http://localhost:32400; then
            echo
            echo "✅ Token retrieval completed successfully!"
            echo "   Check the output above for your .env configuration"
        else
            echo "❌ Token retrieval failed or was cancelled"
            return 1
        fi
    else
        echo "📋 SIMULATED token retrieval process:"
        echo "   1. Script prompts: 'MyPlex username (email): '"
        echo "   2. User enters: user@example.com"
        echo "   3. Script prompts: 'MyPlex password for user@example.com: '"
        echo "   4. User enters password (hidden)"
        echo "   5. Script authenticates with plex.tv"
        echo "   6. Script retrieves authentication token"
        echo "   7. Script tests token with local server"
        echo "   8. Script outputs .env configuration:"
        echo
        echo "      🎯 Configuration for your .env file:"
        echo "      =" * 50
        echo "      PLEX_URL=http://localhost:32400"
        echo "      PLEX_TOKEN=K22ZgfFgyKVyxgtXY_6u"
        echo "      =" * 50
        echo
        echo "   9. User copies configuration to .env file"
        echo "   ✅ Setup complete!"
    fi
    echo
}

# Function to demonstrate verification
demo_verification() {
    echo "3. ✅ Setup Verification Demo"  
    echo "=" * 30
    echo
    echo "After token setup, the system automatically verifies everything works:"
    echo
    
    # Run comprehensive test
    echo "Running: python3 test-plex-comprehensive.py"
    echo
    if python3 "$SCRIPT_DIR/test-plex-comprehensive.py"; then
        echo
        echo "✅ All verification tests passed!"
    else
        echo "❌ Some tests failed - check configuration"
    fi
    echo
}

# Function to demonstrate notification testing
demo_notification_test() {
    echo "4. 🔔 Notification System Demo"
    echo "=" * 32
    echo
    echo "Testing Plex notification after media processing:"
    echo
    
    # Run notification test
    echo "Running: python3 test-plex-notification.py"
    echo
    if python3 "$SCRIPT_DIR/test-plex-notification.py"; then
        echo
        echo "✅ Notification system working perfectly!"
    else
        echo "❌ Notification test failed"
    fi
    echo
}

# Function to show final workflow
demo_final_workflow() {
    echo "5. 🎯 Complete Workflow Demonstration"
    echo "=" * 38
    echo
    echo "OPTIMIZED WORKFLOW (after setup):"
    echo "1. Media downloaded → Sonarr/Radarr/Lidarr webhook"
    echo "2. import.sh calls media_update.py → Transcoding starts"  
    echo "3. Transcoding completes → media_update.py notifies Plex"
    echo "4. Plex scans library → Only sees optimized files"
    echo
    echo "BENEFITS:"
    echo "✅ No duplicate entries in Plex"
    echo "✅ No processing conflicts"
    echo "✅ Automatic library updates"
    echo "✅ Optimized workflow efficiency"
    echo
    echo "NEXT STEPS:"
    echo "1. Configure *arr apps to disable immediate Plex notifications"
    echo "2. Keep Mediabox Processing webhooks enabled"
    echo "3. Enjoy optimized media processing!"
    echo
}

# Cleanup function
cleanup() {
    echo
    echo "🧹 Cleanup"
    restore_environment
}

# Main execution
main() {
    # Set trap for cleanup
    trap cleanup EXIT
    
    # Ask user what type of demo to run
    echo "Select demo type:"
    echo "1. Full demo with simulated new environment"
    echo "2. Quick demo with current environment"
    echo
    read -p "Choose (1 or 2): " demo_type
    echo
    
    if [[ "$demo_type" == "1" ]]; then
        setup_demo_environment
    fi
    
    demo_interactive_setup
    demo_verification  
    demo_notification_test
    demo_final_workflow
    
    echo "🎉 Complete Plex Setup Demonstration Finished!"
    echo "   All components tested and documented."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
