#!/bin/bash

echo "🚀 Building iOS app with CallKit support..."

# Navigate to iOS directory
cd ios

# Clean previous builds
echo "🧹 Cleaning previous builds..."
flutter clean

# Get dependencies
echo "📦 Getting Flutter dependencies..."
flutter pub get

# Build iOS app
echo "🔨 Building iOS app..."
flutter build ios --release --no-codesign

# Instructions for Xcode
echo ""
echo "✅ Build completed!"
echo ""
echo "📱 Next steps to test iOS CallKit:"
echo "1. Open ios/Runner.xcworkspace in Xcode"
echo "2. Select your target device (iPhone/iPad)"
echo "3. In Xcode, go to Product > Scheme > Edit Scheme"
echo "4. Add these environment variables to the Run scheme:"
echo "   - OS_ACTIVITY_MODE: disable"
echo "   - Development Team: [Your Apple ID Team ID]"
echo ""
echo "5. Build and run on device"
echo ""
echo "🔧 iOS CallKit Features Implemented:"
echo "✅ CallKit UI for incoming calls"
echo "✅ Background VoIP push notifications"
echo "✅ Foreground/background call handling"
echo "✅ Lock screen call controls"
echo "✅ Audio session management"
echo "✅ Microphone permissions"
echo ""
echo "🧪 Testing CallKit:"
echo "1. Make sure your device has push notifications enabled"
echo "2. Use the 'Test CallKit' button in the app"
echo "3. Or send a VoIP push notification from your server"
echo ""
echo "📞 VoIP Push Payload Format:"
echo '{'
echo '  "call_data": {'
echo '    "call_id": "unique-call-id",'
echo '    "caller_name": "John Doe",'
echo '    "caller_number": "+1234567890",'
echo '    "voice_sdk_id": "voice-sdk-id-from-telnyx"'
echo '  }'
echo '}'
