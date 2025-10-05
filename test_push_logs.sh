#!/bin/bash

# Push Notification Log Testing Script
echo "🔍 Push Notification Log Testing"
echo "================================"
echo ""

echo "📱 Step 1: Check if your app is installed"
echo "   - Look for 'Runner' or 'com.adit.callapp' in Console app"
echo ""

echo "📱 Step 2: Check Console App Logs"
echo "   1. Open Console app (Applications > Utilities > Console)"
echo "   2. Connect your iPhone via USB"
echo "   3. Select your iPhone from sidebar"
echo "   4. Search for: 'Runner' or 'com.adit.callapp'"
echo "   5. Clear logs (Edit > Clear Display)"
echo ""

echo "📱 Step 3: Test Push Notifications"
echo "   1. Force quit your app (swipe up and swipe away)"
echo "   2. Send a test call from another device"
echo "   3. Watch Console logs for these entries:"
echo ""
echo "   ✅ Expected Log Entries:"
echo "      📥 didReceiveIncomingPushWith type=voIP payload=..."
echo "      📞 Telnyx VoIP Push - CallID: xxx, Caller: xxx"
echo "      📞 CallKit Accept"
echo "      🔊 Activate Audio Session (WebRTC)"
echo ""

echo "📱 Step 4: Check Build Mode"
echo "   - Debug mode: Push notifications only work in foreground"
echo "   - Release mode: Push notifications work in all states"
echo "   - Use: ./test_release_push.sh to build in release mode"
echo ""

echo "📱 Step 5: Check APNS Environment"
echo "   - Debug builds: development (sandbox)"
echo "   - Release builds: production"
echo "   - Look for: 'Using SANDBOX environment' or 'Using PRODUCTION environment'"
echo ""

echo "🔧 Troubleshooting:"
echo "   - If no logs appear: App might not be receiving push notifications"
echo "   - If logs appear but no CallKit: Check CallKit configuration"
echo "   - If CallKit appears but no audio: Check WebRTC audio setup"
echo ""

echo "📋 Quick Commands:"
echo "   - Build release: ./test_release_push.sh"
echo "   - Check build mode: telnyxService.getBuildModeInfo()"
echo "   - Enable offline mode: telnyxService.enableOfflineMode()"
