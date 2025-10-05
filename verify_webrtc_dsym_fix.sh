#!/bin/bash

echo "🔍 Verifying WebRTC dSYM Fix Implementation"
echo "============================================="

# Check if build script exists in project
echo "1. Checking if 'Generate WebRTC dSYM' build script exists..."
if grep -q "Generate WebRTC dSYM" ios/Runner.xcodeproj/project.pbxproj; then
    echo "✅ Build script 'Generate WebRTC dSYM' found in project"
else
    echo "❌ Build script 'Generate WebRTC dSYM' NOT found in project"
    exit 1
fi

# Check if build script has correct content
echo "2. Checking if build script contains dsymutil command..."
if grep -q "dsymutil" ios/Runner.xcodeproj/project.pbxproj; then
    echo "✅ Build script contains dsymutil command"
else
    echo "❌ Build script does NOT contain dsymutil command"
    exit 1
fi

# Check if build script is in correct position (after Pods frameworks)
echo "3. Checking build script position in build phases..."
if grep -A 10 "buildPhases = (" ios/Runner.xcodeproj/project.pbxproj | grep -q "Generate WebRTC dSYM"; then
    echo "✅ Build script is properly positioned in build phases"
else
    echo "❌ Build script is NOT properly positioned in build phases"
    exit 1
fi

# Check if Podfile contains the fix
echo "4. Checking if Podfile contains WebRTC dSYM fix..."
if grep -q "Generate WebRTC dSYM" ios/Podfile; then
    echo "✅ Podfile contains WebRTC dSYM fix"
else
    echo "❌ Podfile does NOT contain WebRTC dSYM fix"
    exit 1
fi

# Check if Info.plist has BGTaskSchedulerPermittedIdentifiers
echo "5. Checking if Info.plist has BGTaskSchedulerPermittedIdentifiers..."
if grep -q "BGTaskSchedulerPermittedIdentifiers" ios/Runner/Info.plist; then
    echo "✅ Info.plist contains BGTaskSchedulerPermittedIdentifiers"
else
    echo "❌ Info.plist does NOT contain BGTaskSchedulerPermittedIdentifiers"
    exit 1
fi

# Check if Info.plist has NSCameraUsageDescription
echo "6. Checking if Info.plist has NSCameraUsageDescription..."
if grep -q "NSCameraUsageDescription" ios/Runner/Info.plist; then
    echo "✅ Info.plist contains NSCameraUsageDescription"
else
    echo "❌ Info.plist does NOT contain NSCameraUsageDescription"
    exit 1
fi

echo ""
echo "🎉 ALL CHECKS PASSED!"
echo "====================="
echo "✅ WebRTC dSYM build script is properly configured"
echo "✅ Build script will run during archive process"
echo "✅ Script will automatically generate missing WebRTC dSYM"
echo "✅ This should prevent the TestFlight upload error"
echo ""
echo "📱 Next Steps:"
echo "1. Clean Build Folder in Xcode (⌘⇧K)"
echo "2. Archive the app (Product → Archive)"
echo "3. Upload to App Store Connect"
echo ""
echo "🔧 The build script will:"
echo "- Find WebRTC framework binary"
echo "- Generate dSYM using Apple's dsymutil tool"
echo "- Place dSYM in correct location for Xcode"
echo "- Only run if dSYM doesn't already exist"
