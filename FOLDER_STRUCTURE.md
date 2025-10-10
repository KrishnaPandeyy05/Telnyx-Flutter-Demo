# Flutter Telnyx App - Folder Structure

## Overview
This app follows industry-standard Flutter architecture with clear separation of concerns and platform-specific code.

## Folder Structure

```
lib/
├── core/                           # Core application utilities
│   ├── config/                     # App configuration
│   ├── constants/
│   │   └── app_constants.dart      # SIP credentials, routes, globals
│   └── utils/
│       └── custom_logger.dart      # Telnyx SDK logger
│
├── features/                       # Feature-based modules
│   ├── call/                       # Call feature
│   │   ├── models/                 # Call-related models
│   │   ├── providers/              # Call state management
│   │   ├── screens/                # Call screens
│   │   └── widgets/                # Call-specific widgets
│   │
│   └── home/                       # Home feature
│       ├── screens/                # Home screen
│       └── widgets/                # Home widgets
│
├── platform/                       # Platform-specific code
│   ├── android/
│   │   ├── android_audio_handler.dart      # Android audio routing
│   │   └── android_firebase_handler.dart   # FCM push notifications
│   │
│   ├── ios/
│   │   └── ios_callkit_handler.dart        # iOS CallKit & VoIP
│   │
│   └── common/
│       └── platform_handler.dart           # Platform abstraction layer
│
├── services/                       # Business logic services
│   ├── call_state_persistence.dart # Call state persistence
│   ├── initialization_manager.dart # App initialization
│   ├── navigation_manager.dart     # Navigation logic
│   └── unified_call_manager.dart   # Unified call management
│
├── ui/                            # Shared UI components
│   ├── screens/                   # Shared screens
│   ├── theme/
│   │   └── app_theme.dart         # App theme
│   └── widgets/                   # Reusable widgets
│
└── main.dart                      # App entry point

ios/
└── Runner/
    └── AppDelegate.swift          # iOS native CallKit & VoIP configuration

android/
└── app/
    ├── build.gradle.kts           # Android build configuration
    └── google-services.json       # Firebase configuration
```

## Platform-Specific Code

### iOS (CallKit & VoIP)
- **Native Layer**: `ios/Runner/AppDelegate.swift`
  - PushKit registration for VoIP notifications
  - CallKit integration
  - WebRTC audio session management
  
- **Flutter Layer**: `lib/platform/ios/ios_callkit_handler.dart`
  - CallKit UI presentation
  - VoIP token handling
  - Method channel communication

### Android (Firebase & Audio)
- **Firebase**: `lib/platform/android/android_firebase_handler.dart`
  - FCM push notification setup
  - Token management
  
- **Audio Routing**: `lib/platform/android/android_audio_handler.dart`
  - Audio output routing fixes
  - Speaker/earpiece management

### Common Platform Interface
- **Abstraction**: `lib/platform/common/platform_handler.dart`
  - Platform-agnostic API
  - Routes to iOS or Android implementations

## Key Features

### iOS-Specific
✅ VoIP Push Notifications
✅ CallKit Integration
✅ Background & Killed State Support
✅ WebRTC Audio Session Management
✅ Native Call UI

### Android-Specific
✅ Firebase Cloud Messaging
✅ Audio Routing Fixes
✅ Speaker/Earpiece Management
✅ Notification Handling

### Shared
✅ Telnyx WebRTC Integration
✅ Call State Management
✅ Clean Architecture
✅ Provider State Management
✅ Proper Error Handling

## Benefits of This Structure

1. **Separation of Concerns**: Each platform has its own folder
2. **Maintainability**: Easy to find and update platform-specific code
3. **Scalability**: Easy to add new features without bloating main.dart
4. **Testability**: Each module can be tested independently
5. **Industry Standard**: Follows Flutter best practices
6. **Clean Code**: No massive 2000+ line files
7. **Platform Safety**: iOS code doesn't affect Android and vice versa

## Next Steps

The main.dart file needs to be refactored to use these new modules:
1. Import platform handlers
2. Use constants from app_constants.dart
3. Move TelnyxService to services folder
4. Move UI screens to features folder
5. Remove duplicate code
6. Clean up unused variables



