# iOS CallKit Implementation Guide

This document explains the iOS CallKit implementation in the Telnyx Flutter app, providing native iOS call functionality including foreground, background, and lock screen call handling.

## Features Implemented

✅ **Native iOS CallKit Integration**
- Full-screen incoming call UI
- Lock screen call controls
- Background call handling
- VoIP push notifications

✅ **Audio Session Management**
- Proper audio routing for calls
- Bluetooth support
- Speaker/earpiece switching
- Background audio permissions

✅ **Push Notification Support**
- VoIP push notifications via PushKit
- Regular push notifications via Firebase
- Background app wake-up for calls

✅ **Call States Support**
- Foreground call handling
- Background call handling
- Killed state call handling
- CallKit to app navigation

## Architecture Overview

### iOS Native Components
- **AppDelegate.swift**: Handles CallKit delegate methods and VoIP push notifications
- **Info.plist**: Configured with VoIP background modes and permissions
- **Assets**: CallKit logo for native call interface

### Flutter Integration
- **Method Channels**: Communication between iOS native and Flutter
- **CallKit Plugin**: `flutter_callkit_incoming` for cross-platform CallKit
- **Firebase Messaging**: Push notification handling

## Setup Instructions

### 1. iOS Permissions & Entitlements

The following permissions are automatically configured in `Info.plist`:

```xml
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
    <string>fetch</string>
    <string>processing</string>
    <string>remote-notification</string>
    <string>voip</string>
</array>
```

### 2. Xcode Configuration

1. Open `ios/Runner.xcworkspace` in Xcode
2. Select your target device (iPhone/iPad)
3. Go to **Product > Scheme > Edit Scheme**
4. Add environment variable: `OS_ACTIVITY_MODE = disable`

### 3. Build and Run

```bash
# Build iOS app
./ios_build.sh

# Or manually:
cd ios
flutter build ios --release --no-codesign
```

## CallKit Integration Details

### VoIP Push Notifications

The app uses PushKit for VoIP push notifications. When a call comes in:

1. **Background**: iOS wakes up the app via `PKPushRegistryDelegate`
2. **CallKit**: Native CallKit UI is displayed immediately
3. **Flutter**: App processes the call and handles audio

#### Expected VoIP Push Payload:

```json
{
  "call_data": {
    "call_id": "unique-call-id",
    "caller_name": "John Doe",
    "caller_number": "+1234567890",
    "voice_sdk_id": "voice-sdk-id-from-telnyx"
  }
}
```

### Method Channels

The app uses two method channels for iOS communication:

1. **`com.example.telnyx_fresh_app/callkit`**: CallKit action handling
2. **`com.example.telnyx_fresh_app/voip`**: VoIP push notification handling

### Call States Handling

#### Foreground State
- App is running and active
- CallKit shows native UI
- Flutter app handles call immediately

#### Background State
- App is in background
- VoIP push wakes up the app
- CallKit displays call immediately
- User can accept/decline before app fully loads

#### Killed State
- App is completely terminated
- VoIP push launches the app
- CallKit shows call during app startup
- App navigates directly to call screen

## Audio Session Configuration

The iOS implementation configures audio sessions for optimal call quality:

```swift
let audioSession = AVAudioSession.sharedInstance()
try audioSession.setCategory(.playAndRecord,
                            mode: .voiceChat,
                            options: [.allowBluetooth, .duckOthers])
try audioSession.setActive(true)
```

## Testing CallKit

### Option 1: Test Button
1. Run the app on iOS device
2. Tap "Test CallKit" button
3. Verify CallKit UI appears

### Option 2: Server Push
1. Send VoIP push notification with proper payload
2. Verify app wakes up and shows CallKit

### Option 3: Firebase Push
1. Send Firebase push notification
2. Verify background message handling

## Troubleshooting

### Common Issues

#### CallKit Not Appearing
- Check VoIP push payload format
- Verify PushKit registration
- Check console logs for errors

#### Audio Issues
- Verify microphone permissions
- Check audio session configuration
- Test with actual phone call

#### Background Issues
- Ensure `voip` background mode is enabled
- Check push notification certificates
- Verify device is not in Do Not Disturb mode

### Debug Logs

Enable verbose logging by checking:

1. **iOS Console**: View device logs in Xcode
2. **Flutter Logs**: Check `print()` statements in code
3. **CallKit Events**: Monitor CallKit delegate methods

### Required Certificates

For VoIP push notifications, ensure you have:

1. **APNs Certificate**: For regular push notifications
2. **VoIP Certificate**: For VoIP push notifications
3. **Development/Production**: Match your build configuration

## Server Integration

Your server should send VoIP push notifications with this format:

```json
{
  "aps": {
    "alert": {
      "title": "Incoming Call",
      "body": "Call from John Doe"
    }
  },
  "call_data": {
    "call_id": "unique-call-id",
    "caller_name": "John Doe",
    "caller_number": "+1234567890",
    "voice_sdk_id": "voice-sdk-id-from-telnyx"
  }
}
```

## Performance Considerations

### Background App Launch
- App launches quickly when receiving VoIP pushes
- CallKit UI appears within seconds
- Audio session activates immediately

### Battery Optimization
- VoIP pushes are high-priority but battery-efficient
- Audio session only active during calls
- Background processing is minimal

### Memory Management
- App handles killed state launches efficiently
- CallKit manages UI state independently
- Flutter app focuses on call logic only

## Next Steps

1. **Test on Device**: Run on physical iOS device
2. **Push Testing**: Test with actual push notifications
3. **Production Setup**: Configure production certificates
4. **Server Integration**: Update your server to send VoIP pushes
5. **User Testing**: Test with real users and network conditions

## Support

For issues specific to iOS CallKit implementation:

1. Check iOS console logs in Xcode
2. Verify push notification certificates
3. Test on multiple iOS versions (iOS 12+ required)
4. Ensure device has stable network connection

The implementation follows Apple's CallKit best practices and provides a native iOS calling experience while maintaining full Flutter integration.
