#!/bin/bash

echo "🔍 Monitoring for VoIP Token and Push Notifications"
echo "=================================================="
echo ""
echo "📱 Instructions:"
echo "1. Open your TestFlight app on iPhone"
echo "2. Login to Telnyx"
echo "3. Look for VoIP token in logs below"
echo "4. Test calls to see push notifications"
echo ""
echo "🔍 Starting log monitor... Press Ctrl+C to stop"
echo "=================================================="

# Monitor system logs for VoIP-related events
log stream --predicate 'process == "Runner" OR process == "apsd" OR process == "CallKit" OR process == "PushKit" OR process == "Telnyx"' --style compact | grep -E --line-buffered '📱|📥|📞|🔊|VoIP|PushKit|CallKit|didReceiveIncomingPushWith|Telnyx|INVITE|SocketMethod|onIncomingCall|handlePushNotification|Device Token|VoIP Device Token'
