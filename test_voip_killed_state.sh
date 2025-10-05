#!/bin/bash

# Telnyx VoIP Push - Killed State Test Script
# This script helps you monitor device logs while testing VoIP pushes

echo "═══════════════════════════════════════════════════════════════"
echo "  Telnyx VoIP Push - Killed State Testing"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Check if device is connected
if ! idevice_id -l &>/dev/null; then
    echo "❌ ERROR: No iOS device connected via USB"
    echo ""
    echo "Please:"
    echo "1. Connect your iPhone via USB cable"
    echo "2. Trust this computer on your iPhone"
    echo "3. Run this script again"
    echo ""
    exit 1
fi

DEVICE_UDID=$(idevice_id -l | head -1)
echo "✅ Device connected: $DEVICE_UDID"
echo ""

echo "📋 Testing Instructions:"
echo "────────────────────────────────────────────────────────────────"
echo ""
echo "🔹 TEST 1: Background State (should work)"
echo "   1. Open the app on your iPhone"
echo "   2. Login to Telnyx"
echo "   3. Press HOME button (app goes to background)"
echo "   4. Make a call to your Telnyx number"
echo "   5. ✅ You should see CallKit notification"
echo ""
echo "🔹 TEST 2: Killed State (the critical test!)"
echo "   1. Force quit the app (swipe up from app switcher)"
echo "   2. Wait 5 seconds"
echo "   3. Make a call to your Telnyx number"
echo "   4. ✅ You should see CallKit notification appear!"
echo ""
echo "────────────────────────────────────────────────────────────────"
echo ""
echo "🔍 Starting log monitor... Press Ctrl+C to stop"
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Start monitoring logs with nice formatting
idevicesyslog | while IFS= read -r line; do
    # Color coding for important events
    if [[ "$line" =~ "📥" ]] || [[ "$line" =~ "didReceiveIncomingPushWith" ]]; then
        echo -e "\033[1;32m[PUSH RECEIVED]\033[0m $line"
    elif [[ "$line" =~ "📞" ]] || [[ "$line" =~ "CallKit" ]]; then
        echo -e "\033[1;34m[CALLKIT]\033[0m $line"
    elif [[ "$line" =~ "🔊" ]] || [[ "$line" =~ "Activate Audio" ]]; then
        echo -e "\033[1;35m[AUDIO]\033[0m $line"
    elif [[ "$line" =~ "✅" ]]; then
        echo -e "\033[1;32m[SUCCESS]\033[0m $line"
    elif [[ "$line" =~ "❌" ]] || [[ "$line" =~ "Error" ]] || [[ "$line" =~ "error" ]]; then
        echo -e "\033[1;31m[ERROR]\033[0m $line"
    elif [[ "$line" =~ "Telnyx" ]] || [[ "$line" =~ "VoIP" ]] || [[ "$line" =~ "voip" ]]; then
        echo -e "\033[1;33m[TELNYX]\033[0m $line"
    fi
done


