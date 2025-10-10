import 'dart:io';
import 'package:firebase_core/firebase_core.dart' as fb_core;
import 'package:firebase_messaging/firebase_messaging.dart' as fb_msg;

/// Android-specific Firebase messaging handler
class AndroidFirebaseHandler {
  static bool _initialized = false;

  /// Initialize Firebase for Android only
  static Future<void> initialize() async {
    if (!Platform.isAndroid || _initialized) return;

    try {
      print('🤖 Android: Initializing Firebase...');
      await fb_core.Firebase.initializeApp();
      
      // Request notification permissions (Android 13+)
      await fb_msg.FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      
      _initialized = true;
      print('✅ Android: Firebase initialized successfully');
    } catch (e) {
      print('❌ Android: Error initializing Firebase: $e');
    }
  }

  /// Get FCM token for Android push notifications
  static Future<String?> getFCMToken() async {
    if (!Platform.isAndroid) return null;

    try {
      final token = await fb_msg.FirebaseMessaging.instance.getToken();
      if (token != null) {
        print('🤖 Android: FCM Token: ${token.substring(0, 20)}...');
      }
      return token;
    } catch (e) {
      print('❌ Android: Error getting FCM token: $e');
      return null;
    }
  }

  /// Setup Firebase messaging for Android
  static Future<void> setupMessaging(
    Function(fb_msg.RemoteMessage) onMessage,
    Function(fb_msg.RemoteMessage) onBackgroundMessage,
  ) async {
    if (!Platform.isAndroid) return;

    try {
      // Foreground messages
      fb_msg.FirebaseMessaging.onMessage.listen(onMessage);
      
      // Background messages
      fb_msg.FirebaseMessaging.onBackgroundMessage(
        (message) async => onBackgroundMessage(message),
      );
      
      print('✅ Android: Firebase messaging configured');
    } catch (e) {
      print('❌ Android: Error setting up Firebase messaging: $e');
    }
  }
}



