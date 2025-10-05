#!/bin/bash

echo "🔍 Clean VoIP Token & Push Monitor"
echo "=================================="
echo ""
echo "📱 Instructions:"
echo "1. Open your TestFlight app on iPhone"
echo "2. Login to Telnyx"
echo "3. Look for VoIP token below"
echo "4. Test calls to see push notifications"
echo ""
echo "🔍 Starting clean monitor... Press Ctrl+C to stop"
echo "=================================================="

# Clean monitor with better filtering
log stream --predicate 'process == "Runner" OR process == "apsd" OR process == "CallKit" OR process == "PushKit"' --style compact | grep -E --line-buffered '📱|📥|📞|🔊|VoIP|PushKit|CallKit|didReceiveIncomingPushWith|Telnyx|INVITE|SocketMethod|onIncomingCall|handlePushNotification|Device Token|VoIP Device Token|pushRegistry|didUpdate.*pushCredentials|didReceiveIncomingPushWith|showCallkitIncoming|Activate Audio Session|DeActivate Audio Session'
