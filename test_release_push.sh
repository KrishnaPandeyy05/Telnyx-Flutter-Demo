#!/bin/bash

# VoIP Push Notification Testing Script for RELEASE Mode
# This script builds and installs the app in release mode for proper push notification testing

echo "🚀 Building Flutter app in RELEASE mode for VoIP push testing..."
echo ""

# Clean previous builds
echo "🧹 Cleaning previous builds..."
flutter clean

# Get dependencies
echo "📦 Getting dependencies..."
flutter pub get

# Build iOS app in release mode
echo "🔨 Building iOS app in RELEASE mode..."
flutter build ios --release

# Install on connected device
echo "📱 Installing on connected device..."
flutter install --release

echo ""
echo "✅ App installed in RELEASE mode!"
echo ""
echo "📋 Testing Instructions:"
echo "1. Open the app and enable offline mode:"
echo "   - Call: telnyxService.enableOfflineMode()"
echo "2. Force quit the app (swipe up and swipe away)"
echo "3. Send a test call from another device"
echo "4. You should receive a VoIP push notification"
echo "5. Accept the call to test the full flow"
echo ""
echo "🔧 Environment Configuration:"
echo "   - Debug builds: Uses 'development' entitlements (sandbox APNs)"
echo "   - Release builds: Uses 'production' entitlements (production APNs)"
echo ""
echo "⚠️  IMPORTANT: VoIP push notifications ONLY work in RELEASE mode!"
echo "   - Debug mode: Only works when app is in foreground"
echo "   - Release mode: Works in background and killed state"
echo ""
echo "🔍 To check build mode in app:"
echo "   - Look for 'RELEASE MODE' in console logs"
echo "   - Use: telnyxService.getBuildModeInfo()"
