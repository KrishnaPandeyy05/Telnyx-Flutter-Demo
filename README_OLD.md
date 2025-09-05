# Telnyx Flutter CallKit App

A comprehensive Flutter application demonstrating WebRTC calling functionality using Telnyx SDK with native CallKit integration for Android and iOS.

## 🚀 Features

- **WebRTC Voice Calls**: High-quality voice calling using Telnyx WebRTC SDK
- **CallKit Integration**: Native call interface with system-level call management
- **Push Notifications**: Firebase Cloud Messaging for incoming call notifications
- **Background Call Handling**: Accept/decline calls even when app is killed or in background
- **Cross-Platform**: Supports both Android and iOS platforms
- **Real-time Communication**: WebSocket-based signaling for instant connectivity

## 📱 Screenshots

*Add screenshots of your app here showing the call interface, CallKit notifications, etc.*

## 🛠️ Tech Stack

- **Flutter**: Cross-platform mobile framework
- **Telnyx WebRTC SDK**: Voice calling infrastructure
- **Firebase**: Cloud messaging for push notifications
- **CallKit (iOS)**: Native call interface
- **ConnectionService (Android)**: Android's native calling framework
- **Provider**: State management
- **WebSocket**: Real-time communication

## 📋 Prerequisites

- Flutter SDK (>=3.8.1)
- Dart SDK
- Android Studio / Xcode
- Firebase project with Cloud Messaging enabled
- Telnyx account with WebRTC credentials
- Physical devices for testing (CallKit doesn't work on simulators)

## 🔧 Installation

1. **Clone the repository**
   ```bash
   git clone <your-repo-url>
   cd telnyx_fresh_app
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Firebase Configuration**
   - Create a Firebase project
   - Add your Android/iOS apps to Firebase
   - Download `google-services.json` (Android) and `GoogleService-Info.plist` (iOS)
   - Place them in the appropriate directories:
     - Android: `android/app/google-services.json`
     - iOS: `ios/Runner/GoogleService-Info.plist`

4. **Telnyx Configuration**
   - Sign up for a Telnyx account
   - Get your WebRTC credentials
   - Update the credentials in your app configuration

5. **Run the app**
   ```bash
   flutter run
   ```

## ⚙️ Configuration

### Android Setup

1. **Permissions** - Already configured in `android/app/src/main/AndroidManifest.xml`:
   ```xml
   <uses-permission android:name="android.permission.RECORD_AUDIO" />
   <uses-permission android:name="android.permission.INTERNET" />
   <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
   <uses-permission android:name="android.permission.CALL_PHONE" />
   <uses-permission android:name="android.permission.READ_PHONE_STATE" />
   <uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW" />
   <uses-permission android:name="android.permission.USE_FULL_SCREEN_INTENT" />
   ```

2. **CallKit Integration** - Configured with intent filters for call actions

### iOS Setup

1. **Info.plist Configuration** - Add to `ios/Runner/Info.plist`:
   ```xml
   <key>NSMicrophoneUsageDescription</key>
   <string>This app needs microphone access for voice calls</string>
   ```

2. **Background Modes** - Enable in Xcode:
   - Background App Refresh
   - Voice over IP

## 🔑 Key Components

### MainActivity.kt (Android)
- Handles CallKit intents from system notifications
- Converts Android Bundle objects to Flutter-compatible data
- Manages method channel communication with Flutter

### TelnyxService (Flutter)
- Manages WebRTC connection to Telnyx servers
- Handles call state management
- Processes push notifications for incoming calls

### CallKit Integration
- Shows native call interface
- Handles call acceptance/rejection
- Manages call audio routing

## 🚨 Critical Issues Resolved

### Bundle Serialization Fix
The app previously crashed when handling CallKit intents due to Bundle serialization issues. This has been resolved by implementing a `convertToFlutterCompatible()` function that properly converts Android Bundle objects to Flutter-compatible Map objects.

**Before Fix:**
```
java.lang.IllegalArgumentException: Unsupported value: 'Bundle[mParcelledData.dataSize=3568]' of type 'class android.os.Bundle'
```

**After Fix:**
- Bundle objects are recursively converted to Map<String, Any?>
- Arrays and Lists are properly handled
- Primitive types are preserved
- Complex objects fallback to string representation

### CallKit State Management
- Fixed killed state call acceptance
- Improved background state UI navigation
- Enhanced method channel reliability

## 🧪 Testing

### Testing CallKit Functionality

1. **Install on Physical Device**
   ```bash
   flutter build apk --debug
   adb install -r build/app/outputs/flutter-apk/app-debug.apk
   ```

2. **Test Scenarios**
   - Incoming call when app is in foreground
   - Incoming call when app is in background
   - Incoming call when app is killed
   - Call acceptance from notification
   - Call rejection from notification

3. **Debug Logs**
   ```bash
   # View real-time logs
   adb logcat | grep -E "(MainActivity|flutter|telnyx)"
   
   # Clear logs
   adb logcat -c
   ```

## 📊 Architecture

```
┌─────────────────────────────────────┐
│           Flutter Layer             │
├─────────────────────────────────────┤
│  TelnyxService │ CallKit Manager    │
│  State Mgmt    │ UI Components      │
├─────────────────────────────────────┤
│        Method Channel Bridge        │
├─────────────────────────────────────┤
│          Native Layer              │
│  MainActivity  │ CallKit Service   │
│  Push Handling │ Audio Management  │
└─────────────────────────────────────┘
```

## 🔧 Troubleshooting

### Common Issues

1. **CallKit not working**
   - Ensure you're testing on a physical device
   - Check that all permissions are granted
   - Verify Firebase configuration

2. **Audio issues**
   - Check microphone permissions
   - Verify audio routing settings
   - Test with different audio devices

3. **Push notifications not received**
   - Verify Firebase configuration
   - Check device network connectivity
   - Ensure app is whitelisted from battery optimization

4. **WebSocket connection fails**
   - Check Telnyx credentials
   - Verify network connectivity
   - Check firewall/proxy settings

### Debug Commands

```bash
# Check app logs
adb logcat -s "telnyx_fresh_app"

# Monitor system logs
adb logcat | grep -i callkit

# Check Firebase token
adb logcat | grep -i firebase
```

## 📚 Dependencies

| Package | Version | Purpose |
|---------|---------|----------|
| telnyx_webrtc | ^3.0.0 | WebRTC calling functionality |
| firebase_core | ^3.3.0 | Firebase initialization |
| firebase_messaging | ^15.0.4 | Push notifications |
| flutter_callkit_incoming | ^2.0.0 | CallKit integration |
| permission_handler | ^11.3.1 | Runtime permissions |
| provider | ^6.1.2 | State management |
| just_audio | ^0.9.40 | Audio playback |

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🆘 Support

For support and questions:

- Open an issue on GitHub
- Check the [Telnyx Documentation](https://developers.telnyx.com/)
- Review [Flutter CallKit Plugin Documentation](https://pub.dev/packages/flutter_callkit_incoming)

## 🚧 Roadmap

- [ ] Video calling support
- [ ] Group calling functionality
- [ ] Call recording features
- [ ] Enhanced UI/UX improvements
- [ ] iOS CallKit implementation
- [ ] Advanced call analytics

## 👏 Acknowledgments

- [Telnyx](https://telnyx.com) for WebRTC infrastructure
- [Flutter CallKit Incoming](https://pub.dev/packages/flutter_callkit_incoming) plugin
- Firebase team for messaging services
- Flutter community for excellent documentation

---

**Note**: This app requires physical devices for testing CallKit functionality. Simulators/Emulators have limited CallKit support.
