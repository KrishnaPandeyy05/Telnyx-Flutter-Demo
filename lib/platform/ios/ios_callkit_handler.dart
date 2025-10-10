import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/ios_params.dart';
import 'package:flutter_callkit_incoming/entities/notification_params.dart';
import '../../core/constants/app_constants.dart';

/// iOS-specific CallKit handler
class IOSCallKitHandler {
  static const MethodChannel _voipChannel = MethodChannel('com.adit.callapp/voip');

  /// Initialize iOS VoIP channel
  static void initializeVoIPChannel(Future<dynamic> Function(MethodCall) handler) {
    _voipChannel.setMethodCallHandler(handler);
  }

  /// Show CallKit incoming call UI
  static Future<void> showCallKitIncoming(Map<String, dynamic> data) async {
    final callId = data['call_id'] ?? 'unknown';
    final callerName = data['caller_name'] ?? 'Unknown';
    final callerNumber = data['caller_number'] ?? 'Unknown';

    final params = CallKitParams(
      id: callId,
      nameCaller: callerName,
      appName: 'Telnyx Call',
      avatar: '',
      handle: callerNumber,
      type: 0,
      duration: 30000,
      textAccept: 'Accept',
      textDecline: 'Decline',
      missedCallNotification: const NotificationParams(
        showNotification: true,
        isShowCallback: false,
        subtitle: 'Missed call',
        callbackText: 'Call back',
      ),
      extra: {
        'metadata': jsonEncode(data),
        'call_id': callId,
        'voice_sdk_id': data['voice_sdk_id'] ?? '',
      },
      ios: const IOSParams(
        iconName: 'CallKitLogo',
        handleType: 'generic',
        supportsVideo: false,
        maximumCallGroups: 1,
        maximumCallsPerCallGroup: 1,
        audioSessionMode: 'default',
        audioSessionActive: true,
        audioSessionPreferredSampleRate: 44100.0,
        audioSessionPreferredIOBufferDuration: 0.005,
        supportsDTMF: true,
        supportsHolding: true,
        supportsGrouping: false,
        supportsUngrouping: false,
        ringtonePath: 'system_ringtone_default',
      ),
    );

    await FlutterCallkitIncoming.showCallkitIncoming(params);
  }

  /// Handle VoIP token received
  static void handleVoIPToken(String token) {
    AppGlobals.globalVoipToken = token;
    print('📱 iOS VoIP token stored: ${token.substring(0, 20)}...');
  }

  /// Clear all CallKit notifications
  static Future<void> clearCallKitNotifications() async {
    try {
      await FlutterCallkitIncoming.endAllCalls();
      print('✅ iOS: Cleared all CallKit notifications');
    } catch (e) {
      print('⚠️ iOS: Error clearing CallKit notifications: $e');
    }
  }
}


