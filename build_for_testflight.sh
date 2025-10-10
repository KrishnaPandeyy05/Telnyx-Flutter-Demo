#!/bin/bash

# Script to build and prepare iOS app for TestFlight upload
# Usage: ./build_for_testflight.sh

set -e  # Exit on error

echo "🚀 Starting iOS TestFlight build process..."
echo ""

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Step 1: Clean previous builds
echo -e "${BLUE}📦 Step 1: Cleaning previous builds...${NC}"
flutter clean
echo -e "${GREEN}✅ Clean complete${NC}"
echo ""

# Step 2: Get Flutter dependencies
echo -e "${BLUE}📦 Step 2: Getting Flutter dependencies...${NC}"
flutter pub get
echo -e "${GREEN}✅ Dependencies fetched${NC}"
echo ""

# Step 3: Install CocoaPods dependencies
echo -e "${BLUE}📦 Step 3: Installing CocoaPods dependencies...${NC}"
cd ios
export LANG=en_US.UTF-8
pod install
cd ..
echo -e "${GREEN}✅ CocoaPods installed${NC}"
echo ""

# Step 4: Build iOS release
echo -e "${BLUE}📦 Step 4: Building iOS release...${NC}"
flutter build ios --release
echo -e "${GREEN}✅ iOS release build complete${NC}"
echo ""

# Step 5: Open in Xcode for archiving
echo -e "${BLUE}📦 Step 5: Opening Xcode for archiving...${NC}"
echo -e "${YELLOW}⚠️  Next steps in Xcode:${NC}"
echo "   1. Select 'Any iOS Device (arm64)' as target"
echo "   2. Product → Archive"
echo "   3. Distribute App → App Store Connect"
echo "   4. Upload"
echo ""
echo -e "${YELLOW}⚠️  Don't forget to:${NC}"
echo "   - Answer Export Compliance questions (Yes, Yes, No)"
echo "   - Fill in 'What to Test' field before submitting"
echo ""

open ios/Runner.xcworkspace

echo -e "${GREEN}✅ Build process complete!${NC}"
echo ""
echo -e "${BLUE}📱 After uploading to TestFlight:${NC}"
echo "   1. Wait for processing (10-30 minutes)"
echo "   2. Add TestFlight testers"
echo "   3. Install on physical device"
echo "   4. Test all states: foreground, background, killed"
echo ""

