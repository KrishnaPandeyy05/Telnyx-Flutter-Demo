#!/bin/bash

# Push Notification Log Monitor
echo "🔍 Push Notification Log Monitor"
echo "================================"
echo ""

echo "📱 Your iPhone 13 is connected and ready!"
echo "📱 App 'Telnyx Fresh App' (com.adit.callapp) is installed"
echo ""

echo "🔍 To monitor push notification logs:"
echo ""
echo "1. Open Console app (Applications > Utilities > Console)"
echo "2. Select your iPhone from the sidebar"
echo "3. Search for: 'Runner' or 'com.adit.callapp'"
echo "4. Clear logs (Edit > Clear Display)"
echo ""

echo "📱 Test Steps:"
echo "1. Force quit your app (swipe up and swipe away)"
echo "2. Send a test call from another device"
echo "3. Watch Console logs for these entries:"
echo ""

echo "✅ Expected Log Entries:"
echo "   📥 didReceiveIncomingPushWith type=voIP payload=..."
echo "   📞 Telnyx VoIP Push - CallID: xxx, Caller: xxx"
echo "   📞 CallKit Accept"
echo "   🔊 Activate Audio Session (WebRTC)"
echo ""

echo "❌ If you don't see these logs:"
echo "   - Check if you're in RELEASE mode (not DEBUG)"
echo "   - Check if app is in offline mode"
echo "   - Check APNS environment configuration"
echo ""

echo "🔧 Quick Commands:"
echo "   - Build release: ./test_release_push.sh"
echo "   - Check build mode: telnyxService.getBuildModeInfo()"
echo "   - Enable offline mode: telnyxService.enableOfflineMode()"
echo ""

echo "📋 Current Status:"
echo "   - Device: iPhone 13 (iOS 18.6.2)"
echo "   - App: Telnyx Fresh App (com.adit.callapp)"
echo "   - Connection: USB (Connected)"
echo "   - Developer Mode: Enabled"
echo ""

echo "🚀 Ready to test! Open Console app and send a test call."
