import 'dart:io';
import '../android/android_audio_handler.dart';
import '../android/android_firebase_handler.dart';
import '../ios/ios_callkit_handler.dart';
import 'package:telnyx_webrtc/call.dart';

/// Common platform handler that routes to iOS or Android specific implementations
class PlatformHandler {
  /// Initialize platform-specific features
  static Future<void> initialize() async {
    if (Platform.isAndroid) {
      await AndroidFirebaseHandler.initialize();
    } else if (Platform.isIOS) {
      // iOS initialization happens in AppDelegate.swift
      print('🍎 iOS: CallKit and VoIP configured in native layer');
    }
  }

  /// Get push notification token (FCM for Android, VoIP for iOS)
  static Future<String?> getPushToken() async {
    if (Platform.isAndroid) {
      return await AndroidFirebaseHandler.getFCMToken();
    } else if (Platform.isIOS) {
      // iOS VoIP token is handled by native layer
      return null; // Token comes via method channel
    }
    return null;
  }

  /// Apply audio routing fix (Android-specific, iOS handles via CallKit)
  static Future<void> applyAudioRoutingFix(Call? call) async {
    if (Platform.isAndroid) {
      await AndroidAudioHandler.applyAudioRoutingFix(call);
    }
    // iOS audio is handled automatically by CallKit
  }

  /// Clear push notifications
  static Future<void> clearNotifications() async {
    if (Platform.isIOS) {
      await IOSCallKitHandler.clearCallKitNotifications();
    }
    // Android notifications are handled by Flutter CallKit plugin
  }

  /// Get platform name
  static String get platformName {
    if (Platform.isIOS) return 'iOS';
    if (Platform.isAndroid) return 'Android';
    return 'Unknown';
  }

  /// Check if platform supports CallKit
  static bool get supportsCallKit => Platform.isIOS;

  /// Check if platform supports Firebase
  static bool get supportsFirebase => Platform.isAndroid;
}



