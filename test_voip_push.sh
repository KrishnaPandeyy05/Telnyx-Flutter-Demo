#!/bin/bash

# VoIP Push Notification Test Script
# Make sure your app is running in debug mode first!

# Your device token (from the logs)
DEVICE_TOKEN="7b940c82d92a811f74d748e5e8a65d3a9460c0858b7bbb41f98226dd6331c29b"

# APNs endpoint for development (sandbox)
APNS_URL="https://api.sandbox.push.apple.com:443"

# Your bundle ID
BUNDLE_ID="com.adit.callapp"

# Create the payload
PAYLOAD='{
  "aps": {
    "alert": {
      "title": "Incoming Call",
      "body": "Test VoIP Push Notification"
    },
    "sound": "default"
  },
  "call_id": "test-call-123",
  "caller_name": "Test Caller",
  "caller_number": "1234567890",
  "voice_sdk_id": "test-sdk-id"
}'

echo "🚀 Testing VoIP Push Notification..."
echo "📱 Device Token: ${DEVICE_TOKEN:0:20}..."
echo "📦 Bundle ID: $BUNDLE_ID"
echo "🌐 APNs URL: $APNS_URL"
echo ""

# Note: You'll need to replace this with your actual .p8 key file
echo "⚠️  To use this script, you need:"
echo "1. Your VoIP Services Key (.p8 file) from Apple Developer Portal"
echo "2. Your Team ID from Apple Developer Portal"
echo "3. Your Key ID from Apple Developer Portal"
echo ""
echo "Then run:"
echo "curl -v -H 'authorization: bearer YOUR_JWT_TOKEN' \\"
echo "     -H 'apns-topic: $BUNDLE_ID.voip' \\"
echo "     -H 'apns-push-type: voip' \\"
echo "     -H 'apns-priority: 10' \\"
echo "     -H 'apns-expiration: 0' \\"
echo "     --data '$PAYLOAD' \\"
echo "     $APNS_URL/3/device/$DEVICE_TOKEN"
