# Firebase Setup Guide for iOS CallKit

## Problem
Your iOS app is crashing because Firebase hasn't been configured properly. You need to download the iOS configuration file from Firebase console.

## Solution

### Step 1: Download iOS Config File

1. **Go to Firebase Console:**
   - Visit: https://console.firebase.google.com
   - Sign in with your Google account

2. **Select Your Project:**
   - If you don't have a project, create one with the name "Telnyx Fresh App"
   - If you have a project, select it

3. **Download iOS Config:**
   - Click the gear icon ⚙️ > Project settings
   - Go to the "General" tab
   - Scroll down to "Your apps" section
   - Click "Add app" (if you haven't added iOS yet)
   - Select the iOS icon ()
   - Enter your Bundle ID: `com.example.telnyxFreshApp` (or your actual bundle ID)
   - Download the `GoogleService-Info.plist` file

4. **Add to Your Project:**
   - Open Finder and navigate to your project folder
   - Copy the downloaded `GoogleService-Info.plist` file
   - Paste it into: `/Users/krishna/Telnyx-Flutter-Demo/ios/Runner/`

### Step 2: Alternative - Create New Firebase Project

If you don't have a Firebase project:

1. **Create New Project:**
   - Go to https://console.firebase.google.com
   - Click "Create a project"
   - Name: "Telnyx Fresh App"
   - Choose your country/region
   - Click "Create project"

2. **Enable Services:**
   - Once project is created, click "Continue"
   - Enable **Authentication** (for user management)
   - Enable **Cloud Messaging** (for push notifications)

3. **Download Config:**
   - Follow steps 3-4 above

### Step 3: Configure iOS Push Notifications

1. **Enable APNs:**
   - In Firebase Console, go to Project Settings > Cloud Messaging
   - Scroll to "iOS app configuration"
   - Click "Upload APNs certificates"
   - Follow the instructions to create and upload certificates

2. **Bundle ID:**
   - Make sure your Bundle ID in Xcode matches: `com.example.telnyxFreshApp`

### Step 4: Test the Setup

1. **Clean and Rebuild:**
   ```bash
   cd /Users/krishna/Telnyx-Flutter-Demo
   flutter clean
   flutter pub get
   cd ios
   pod install
   cd ..
   flutter build ios --simulator
   ```

2. **Run in Simulator:**
   - Open Xcode: `open ios/Runner.xcworkspace`
   - Select iPhone simulator
   - Run the app

### Step 5: What You Should See

After proper Firebase setup, you should see:
- ✅ No Firebase initialization errors
- ✅ Firebase connected successfully
- ✅ Push notifications working
- ✅ CallKit integration functional

## Troubleshooting

### If You Still See Errors:

1. **Check File Location:**
   - Ensure `GoogleService-Info.plist` is in `/ios/Runner/` folder
   - Right-click the file in Finder > Get Info > Check location

2. **Bundle ID Mismatch:**
   - In Xcode: Runner > Targets > Runner > General
   - Check "Bundle Identifier" matches Firebase config

3. **Clean Build:**
   ```bash
   flutter clean
   cd ios
   rm -rf Pods Podfile.lock
   cd ..
   flutter pub get
   cd ios
   pod install
   ```

4. **Restart Simulator:**
   - Close simulator completely
   - Reopen from Xcode

## Need Help?

If you're still having issues:
1. Check that you've downloaded the correct `GoogleService-Info.plist`
2. Verify the Bundle ID matches between Firebase and Xcode
3. Make sure you're using the latest Firebase dependencies
4. Try running `flutter doctor` to check for other issues

## Next Steps

Once Firebase is working:
- Test CallKit functionality
- Test push notifications
- Test VoIP calls
- Move to physical device testing

Your app should now work without Firebase crashes!
