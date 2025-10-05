#!/bin/bash

# Filter Push Notification Logs Script
echo "🔍 Filtering Push Notification Logs"
echo "=================================="
echo ""

echo "📱 Console App Filtering Tips:"
echo ""
echo "1. In Console app, use these EXACT search terms:"
echo "   - 'didReceiveIncomingPushWith'"
echo "   - 'Telnyx VoIP Push'"
echo "   - 'CallKit Accept'"
echo "   - 'VoIP Device Token'"
echo ""

echo "2. Use the Predicate filter (more powerful):"
echo "   - Click the '+' button next to the search box"
echo "   - Select 'Predicate'"
echo "   - Enter: process == 'Runner'"
echo "   - Or: message CONTAINS 'push'"
echo ""

echo "3. Clear logs before testing:"
echo "   - Edit > Clear Display"
echo "   - Or press Cmd+K"
echo ""

echo "4. Real-time monitoring:"
echo "   - Make sure 'Live' is enabled (button in top right)"
echo "   - Watch for new entries as they appear"
echo ""

echo "📱 Alternative: Use Terminal with specific filters"
echo "   - This will show only push-related logs"
echo ""

# Try to get logs using system log command
echo "🔍 Checking recent push notification logs..."
echo ""

# Check if we can access system logs
if command -v log &> /dev/null; then
    echo "📋 Recent system logs (last 2 minutes):"
    echo "----------------------------------------"
    
    # Try to get logs with a simpler approach
    timeout 10s log stream --predicate 'process == "apsd" OR process == "SpringBoard"' --style compact 2>/dev/null | grep -i "push\|voip\|runner" | head -10 || echo "No recent push logs found"
    
    echo ""
    echo "📋 Recent Runner app logs:"
    echo "-------------------------"
    
    # Try to get Runner-specific logs
    timeout 10s log stream --predicate 'process == "Runner"' --style compact 2>/dev/null | head -10 || echo "No recent Runner logs found"
    
else
    echo "❌ System log access not available"
fi

echo ""
echo "🔧 Manual Testing Steps:"
echo "1. Force quit your app (swipe up and swipe away)"
echo "2. Send a test call from another device"
echo "3. Watch Console app for these specific entries:"
echo ""
echo "✅ Look for these EXACT messages:"
echo "   📥 didReceiveIncomingPushWith type=voIP"
echo "   📞 Telnyx VoIP Push - CallID:"
echo "   📞 CallKit Accept"
echo "   🔊 Activate Audio Session"
echo ""
echo "❌ If you see nothing:"
echo "   - You're probably in DEBUG mode"
echo "   - Build in RELEASE mode: ./test_release_push.sh"
echo "   - Enable offline mode in your app"
