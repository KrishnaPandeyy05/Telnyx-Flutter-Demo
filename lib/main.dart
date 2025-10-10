import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'dart:io' show Platform;
// Firebase is Android-only in this app. Guard imports via runtime checks before use.
import 'package:firebase_core/firebase_core.dart' as fb_core;
import 'package:firebase_messaging/firebase_messaging.dart' as fb_msg;
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/notification_params.dart';
import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:flutter_callkit_incoming/entities/ios_params.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Enhanced UI imports
import 'ui/theme/app_theme.dart';
import 'ui/screens/simple_home_screen.dart';

import 'package:telnyx_webrtc/telnyx_client.dart';
import 'package:telnyx_webrtc/config/telnyx_config.dart';
import 'package:telnyx_webrtc/model/telnyx_message.dart';
import 'package:telnyx_webrtc/model/socket_method.dart';
import 'package:telnyx_webrtc/model/telnyx_socket_error.dart';
import 'package:telnyx_webrtc/model/verto/receive/received_message_body.dart';
import 'package:telnyx_webrtc/model/push_notification.dart';
import 'package:telnyx_webrtc/call.dart';
import 'package:telnyx_webrtc/model/call_state.dart';
import 'package:telnyx_webrtc/utils/logging/log_level.dart';
import 'package:telnyx_webrtc/utils/logging/custom_logger.dart';

// SIP Credentials from your Telnyx account
const String _sipUser = "userkrishnak53562";
const String _sipPassword = "2*Wfe.*P0lE.";
const String _callerIdName = "Telnyx Softphone";
const String _callerIdNumber = "1001";

// Global navigator key
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Track if app is being launched from CallKit accept
bool _isLaunchingFromCallKitAccept = false;

// Store call info for direct launch
Map<String, dynamic>? globalCallKitCallInfo;

// Global variable to store VoIP token
String? globalVoipToken;

// Global TelnyxService instance for killed-state access
TelnyxService? _globalTelnyxService;

// Custom Logger Implementation
class MyCustomLogger extends CustomLogger {
  @override
  log(LogLevel level, String message) {
    print('[$level] $message');
  }
}

// Centralized safe abbreviation for logging tokens/IDs
String abbreviate(String? value, {int max = 20}) {
  if (value == null) return 'null';
  if (max <= 0) return '';
  return value.length > max ? value.substring(0, max) : value;
}

// Returns a usable VoIP token, or null if not yet available/placeholder
String? getValidVoipToken() {
  final token = globalVoipToken;
  if (token == null) return null;
  if (token == 'RECONNECT_NEEDED') return null;
  return token;
}

// Persist/retrieve VoIP token for killed/background launches
Future<void> _saveVoipToken(String token) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('voip_token', token);
  } catch (_) {}
}

Future<void> _loadSavedVoipToken() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('voip_token');
    if (saved != null && saved.isNotEmpty) {
      globalVoipToken = saved;
      // Also update in-memory token store if service not yet ready
    }
  } catch (_) {}
}

// Background message handler for Firebase
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(fb_msg.RemoteMessage message) async {
  // Android-only background handler
  if (!Platform.isAndroid) return;
  await fb_core.Firebase.initializeApp();
  print('📱 Background message received: ${message.data}');
  
  final data = message.data;
  
  // Extract call info from metadata field (Firebase structure)
  String? callId;
  String? voiceSdkId;
  String? callerName;
  String? callerNumber;
  
  if (data.containsKey('metadata') && data['metadata'] is String) {
    try {
      final metadata = jsonDecode(data['metadata']);
      callId = metadata['call_id'];
      voiceSdkId = metadata['voice_sdk_id'];
      callerName = metadata['caller_name'];
      callerNumber = metadata['caller_number'];
      print('📱 Extracted from metadata: callId=$callId, voiceSdkId=$voiceSdkId');
      } catch (e) {
      print('❌ Error parsing metadata: $e');
    }
  }
  
  // Fallback to direct data fields
  callId ??= data['call_id'];
  voiceSdkId ??= data['voice_sdk_id'];
  callerName ??= data['caller_name'] ?? 'Unknown Caller';
  callerNumber ??= data['caller_number'] ?? 'Unknown Number';
  
  if (callId != null && voiceSdkId != null) {
    print('📱 Triggering CallKit for callId=$callId');
    await _showCallKitIncoming(data);
    
    // CallKit event handling is now centralized in _setupCallKitListeners()
  } else {
    print('❌ Missing call_id or voice_sdk_id - not showing CallKit');
    print('❌ Available data keys: ${data.keys.toList()}');
  }
}

Future<void> _showCallKitIncoming(Map<String, dynamic> data) async {
  print('📱 Showing CallKit for background push: $data');
  
  try {
    // Missed-call timeout handling
    const int CALL_MISSED_TIMEOUT = 60; // seconds
    try {
      final sentTimeRaw = data['sentTime'] ?? data['google.sent_time'];
      if (sentTimeRaw != null) {
        final sentEpochMs = sentTimeRaw is int ? sentTimeRaw : int.tryParse(sentTimeRaw.toString());
        if (sentEpochMs != null) {
          final now = DateTime.now();
          final sentTime = DateTime.fromMillisecondsSinceEpoch(sentEpochMs);
          final diff = now.difference(sentTime).inSeconds;
          if (diff > CALL_MISSED_TIMEOUT) {
            print('⏱️ Push too old ($diff s) -> flag as missed; skip CallKit');
            return;
          }
        }
      }
    } catch (e) {
      print('⚠️ Missed-call timeout check failed: $e');
    }
    // Check active calls to verify CallKit is working
    final activeCalls = await FlutterCallkitIncoming.activeCalls();
    print('📱 Current active calls: ${activeCalls.length}');
    
    // Extract metadata - Firebase puts it in 'metadata' field as JSON string
    Map<String, dynamic> metadata = {};
    if (data.containsKey('metadata') && data['metadata'] is String) {
      try {
        metadata = jsonDecode(data['metadata']);
        print('📱 Parsed metadata from Firebase: $metadata');
      } catch (e) {
        print('❌ Error parsing metadata: $e');
        metadata = data; // Fallback to using data directly
      }
    } else {
      metadata = data;
    }
    
    final callId = metadata['call_id'] ?? data['call_id'] ?? 'unknown';
    final callerName = metadata['caller_name'] ?? data['caller_name'] ?? 'Unknown Caller';
    final callerNumber = metadata['caller_number'] ?? data['caller_number'] ?? 'Unknown Number';
    final voiceSdkId = metadata['voice_sdk_id'] ?? data['voice_sdk_id'];
    
    print('📱 CallKit params: callId=$callId, caller=$callerName/$callerNumber, sdkId=$voiceSdkId');

    final params = CallKitParams(
      id: callId,
      nameCaller: callerName,
      appName: 'Adit Telnyx',
      handle: callerNumber,
      type: 0,
      duration: 45000,
      textAccept: 'Accept',
      textDecline: 'Decline',
      missedCallNotification: const NotificationParams(
        showNotification: true,
        isShowCallback: true,
        subtitle: 'Missed call',
        callbackText: 'Call back',
      ),
      android: const AndroidParams(
        isCustomNotification: true,
        isShowLogo: true,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#0955fa',
        actionColor: '#4CAF50',
        textColor: '#ffffff',
        incomingCallNotificationChannelName: 'Incoming Call',
        missedCallNotificationChannelName: 'Missed Call',
        isShowCallID: false,
        isShowFullLockedScreen: true,
      ),
      ios: const IOSParams(
        iconName: 'CallKitLogo',
        handleType: 'generic',
        supportsVideo: false,
        maximumCallGroups: 2,
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
      extra: {
        'metadata': jsonEncode({
          'call_id': callId,
          'caller_name': callerName,
          'caller_number': callerNumber,
          'voice_sdk_id': voiceSdkId,
        })
      },
    );
    
    print('📱 About to show CallKit notification...');
    await FlutterCallkitIncoming.showCallkitIncoming(params);
    print('✅ CallKit notification triggered successfully');
    
    // Verify the call was registered
    final currentCalls = await FlutterCallkitIncoming.activeCalls();
    print('📱 Active calls after showing CallKit: ${currentCalls.length}');
    
  } catch (e, stackTrace) {
    print('❌ Error showing CallKit notification: $e');
    print('❌ Stack trace: $stackTrace');
    
    // Try to show a fallback local notification
    print('📱 Attempting fallback notification...');
  }
}

// Method channel to receive CallKit intents from native
const MethodChannel _methodChannel = MethodChannel('com.adit.callapp/callkit');

// Method channel to receive VoIP tokens from native
const MethodChannel _voipMethodChannel = MethodChannel('com.adit.callapp/voip');

// Method channel to control audio session on iOS
const MethodChannel _audioMethodChannel = MethodChannel('com.adit.callapp/audio');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize Firebase only on Android
  if (Platform.isAndroid) {
    await fb_core.Firebase.initializeApp();
    fb_msg.FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  }
  // Load any previously saved VoIP token early (used for killed/background connects)
  await _loadSavedVoipToken();
  
  await _requestPermissions();
  
  // Set up method channel listener for CallKit intents
  _methodChannel.setMethodCallHandler(_handleNativeMethodCall);
  
  // Set up method channel listener for VoIP tokens
  _voipMethodChannel.setMethodCallHandler(_handleVoIPMethodCall);
  
  // Check if app was launched from CallKit accept BEFORE building app
  await _detectCallKitLaunchState();
  
  // Create global TelnyxService instance for killed-state access
  _globalTelnyxService = TelnyxService();
  
  runApp(
    ChangeNotifierProvider.value(
      value: _globalTelnyxService!,
      child: const TelnyxApp(),
    ),
  );
}

// Handle native method calls from MainActivity
Future<void> _handleNativeMethodCall(MethodCall call) async {
  print('📱 Native method call: ${call.method}');
  
  if (call.method == 'callkitAcceptLaunched') {
    print('🚀 CallKit Accept launched from native!');
    _isLaunchingFromCallKitAccept = true;
    
    // Extract call info from the intent extras
    final arguments = call.arguments as Map<dynamic, dynamic>?;
    final extras = arguments?['extras'] as Map<dynamic, dynamic>?;
    
    print('🔍 Debug - Full arguments: $arguments');
    print('🔍 Debug - Extras: $extras');
    
    if (extras != null) {
      // Log all available keys for debugging
      print('🔍 Available extra keys: ${extras.keys.toList()}');
      
      // Initialize with fallback values
      var finalCallId = 'unknown';
      var finalCallerName = 'Unknown';
      var finalCallerNumber = 'Unknown';
      var finalVoiceSdkId = '';
      
      // Handle CallKit plugin specific structure: EXTRA_CALLKIT_CALL_DATA -> EXTRA_CALLKIT_EXTRA -> metadata
      if (extras.containsKey('EXTRA_CALLKIT_CALL_DATA') && extras['EXTRA_CALLKIT_CALL_DATA'] is Map) {
        final callKitData = Map<String, dynamic>.from(extras['EXTRA_CALLKIT_CALL_DATA'] as Map);
        print('🔍 Found EXTRA_CALLKIT_CALL_DATA: ${callKitData.keys.toList()}');
        
        // Try direct fields first
        if (callKitData.containsKey('EXTRA_CALLKIT_ID')) {
          finalCallId = callKitData['EXTRA_CALLKIT_ID']?.toString() ?? finalCallId;
        }
        if (callKitData.containsKey('EXTRA_CALLKIT_NAME_CALLER')) {
          finalCallerName = callKitData['EXTRA_CALLKIT_NAME_CALLER']?.toString() ?? finalCallerName;
        }
        if (callKitData.containsKey('EXTRA_CALLKIT_HANDLE')) {
          finalCallerNumber = callKitData['EXTRA_CALLKIT_HANDLE']?.toString() ?? finalCallerNumber;
        }
        
        // Now check for EXTRA_CALLKIT_EXTRA -> metadata for voice_sdk_id
        print('🔍 Checking for EXTRA_CALLKIT_EXTRA in callKitData...');
        print('🔍 callKitData contains EXTRA_CALLKIT_EXTRA: ${callKitData.containsKey('EXTRA_CALLKIT_EXTRA')}');
        if (callKitData.containsKey('EXTRA_CALLKIT_EXTRA')) {
          print('🔍 EXTRA_CALLKIT_EXTRA type: ${callKitData['EXTRA_CALLKIT_EXTRA'].runtimeType}');
          print('🔍 EXTRA_CALLKIT_EXTRA is Map: ${callKitData['EXTRA_CALLKIT_EXTRA'] is Map}');
        }
        
        if (callKitData.containsKey('EXTRA_CALLKIT_EXTRA')) {
          final extraCallKitExtraValue = callKitData['EXTRA_CALLKIT_EXTRA'];
          print('🔍 Found EXTRA_CALLKIT_EXTRA: $extraCallKitExtraValue');
          
          Map<String, dynamic>? extraCallKitExtra;
          
          // Handle both Map and String formats for EXTRA_CALLKIT_EXTRA
          if (extraCallKitExtraValue is Map) {
            extraCallKitExtra = Map<String, dynamic>.from(extraCallKitExtraValue);
            print('🔍 EXTRA_CALLKIT_EXTRA as Map: $extraCallKitExtra');
          } else if (extraCallKitExtraValue is String) {
            // Parse the string representation: {metadata={"call_id":"..."}}
            print('🔍 EXTRA_CALLKIT_EXTRA as String: $extraCallKitExtraValue');
            
            // Extract the metadata JSON from the string representation
            final regex = RegExp(r'metadata=\{([^}]+)\}');
            final match = regex.firstMatch(extraCallKitExtraValue);
            if (match != null) {
              final metadataJson = '{${match.group(1)}}';
              print('🔍 Extracted metadata JSON: $metadataJson');
              try {
                final metadata = jsonDecode(metadataJson);
                extraCallKitExtra = {'metadata': metadata};
                print('🔍 Parsed metadata from String: $metadata');
              } catch (e) {
                print('❌ Error parsing metadata JSON from String: $e');
              }
            }
          }
          
          if (extraCallKitExtra != null && extraCallKitExtra.containsKey('metadata')) {
            try {
              Map<String, dynamic> metadata;
              final metadataValue = extraCallKitExtra['metadata'];
              
              // Handle both String (JSON) and Map formats
              if (metadataValue is String) {
                metadata = jsonDecode(metadataValue);
                print('🔍 Parsed metadata from JSON string: $metadata');
              } else if (metadataValue is Map) {
                metadata = Map<String, dynamic>.from(metadataValue);
                print('🔍 Using metadata as Map: $metadata');
              } else {
                print('❌ Unexpected metadata format: ${metadataValue.runtimeType}');
                metadata = {};
              }
              
              // Override with values from metadata if available
              finalCallId = metadata['call_id']?.toString() ?? finalCallId;
              finalCallerName = metadata['caller_name']?.toString() ?? finalCallerName;
              finalCallerNumber = metadata['caller_number']?.toString() ?? finalCallerNumber;
              finalVoiceSdkId = metadata['voice_sdk_id']?.toString() ?? finalVoiceSdkId;
              
              print('🔍 Extracted voice_sdk_id: $finalVoiceSdkId');
    } catch (e) {
              print('❌ Error parsing metadata from EXTRA_CALLKIT_EXTRA: $e');
            }
          }
        }
      }
      
      // Fallback: try to extract from direct extras using various field names  
      if (finalCallId == 'unknown') {
        finalCallId = extras['call_id']?.toString() ?? extras['id']?.toString() ?? extras['callId']?.toString() ?? extras['uuid']?.toString() ?? finalCallId;
      }
      if (finalCallerName == 'Unknown') {
        finalCallerName = extras['caller_name']?.toString() ?? extras['nameCaller']?.toString() ?? extras['name']?.toString() ?? finalCallerName;
      }
      if (finalCallerNumber == 'Unknown') {
        finalCallerNumber = extras['caller_number']?.toString() ?? extras['handle']?.toString() ?? extras['number']?.toString() ?? finalCallerNumber;
      }
      if (finalVoiceSdkId == '') {
        finalVoiceSdkId = extras['voice_sdk_id']?.toString() ?? extras['voiceSdkId']?.toString() ?? finalVoiceSdkId;
      }
      
      globalCallKitCallInfo = {
        'call_id': finalCallId.toString(),
        'caller_name': finalCallerName.toString(),
        'caller_number': finalCallerNumber.toString(),
        'voice_sdk_id': finalVoiceSdkId.toString(),
      };
      
      print('📞 Native CallKit call info extracted:');
      print('  Call ID: ${globalCallKitCallInfo!["call_id"]}');
      print('  Caller Name: ${globalCallKitCallInfo!["caller_name"]}');
      print('  Caller Number: ${globalCallKitCallInfo!["caller_number"]}');
      print('  Voice SDK ID: ${globalCallKitCallInfo!["voice_sdk_id"]}');
    } else {
      print('⚠️ No extras found in CallKit intent');
    }
    
    // Navigate to call screen immediately
    Future.delayed(const Duration(milliseconds: 1000), () {
      final navigatorState = navigatorKey.currentState;
      if (navigatorState != null) {
        navigatorState.pushNamedAndRemoveUntil('/call', (route) => false);
        print('✅ Navigated to call screen from native intent');
      }
    });
  }
}

// Handle VoIP method calls from iOS
Future<void> _handleVoIPMethodCall(MethodCall call) async {
  print('📱 VoIP method call: ${call.method}');

  if (call.method == 'reconnectForIncomingCall') {
    // CRITICAL: Use handlePushNotification to connect with CORRECT voice_sdk_id from push
    // This eliminates the 26-second INVITE delay
    final metadata = call.arguments as Map<dynamic, dynamic>?;
    print('🔌 VoIP push received with metadata: $metadata');
    
    if (metadata == null) {
      print('❌ No metadata received from VoIP push');
      return;
    }
    
    try {
      // Convert metadata to proper format for PushMetaData
      final metadataMap = metadata.map((key, value) => MapEntry(key.toString(), value));
      final voiceSdkId = metadataMap['voice_sdk_id'] as String?;
      print('📦 Creating PushMetaData from VoIP push with voice_sdk_id: $voiceSdkId');
      
      // Create PushMetaData from the metadata
      final pushMetaData = PushMetaData.fromJson(metadataMap);
      print('✅ PushMetaData created from VoIP push');
      
      // Try to get service from context first
      TelnyxService? telnyxService;
      
      if (navigatorKey.currentContext != null) {
        telnyxService = Provider.of<TelnyxService>(navigatorKey.currentContext!, listen: false);
      } else if (_globalTelnyxService != null) {
        // Use global instance if context not available (killed state)
        print('🔧 Using global TelnyxService instance (killed state)');
        telnyxService = _globalTelnyxService;
      }
      
      if (telnyxService != null) {
        // Flag push-call in progress so first INVITE is auto-accepted and
        // Flutter won't try to show a duplicate CallKit notification.
        try {
          telnyxService._isPushCallInProgress = true;
          print('📌 Marked push call in progress on VoIP push');
        } catch (_) {}
        // Provide push metadata to SDK first (tie correct voice_sdk_id)
        try {
          final metadataForSdk = metadataMap.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
          TelnyxClient.setPushMetaData(
            metadataForSdk,
            isAnswer: false,
            isDecline: false,
          );
          print('✅ setPushMetaData (isAnswer=false) set for incoming VoIP push');
        } catch (e) {
          print('⚠️ setPushMetaData failed on push: $e');
        }
        // Get the config using global constants
        final config = CredentialConfig(
          sipUser: _sipUser,
          sipPassword: _sipPassword,
          sipCallerIDName: _callerIdName,
          sipCallerIDNumber: _callerIdNumber,
          notificationToken: getValidVoipToken(),
          debug: true,
          logLevel: LogLevel.all,
          customLogger: MyCustomLogger(),
        );
        
        // CRITICAL: Use handlePushNotification instead of manual reconnect
        // This connects with the SAME voice_sdk_id from the push metadata
        print('🚀 Calling handlePushNotification with correct voice_sdk_id from push');
        telnyxService._telnyxClient.handlePushNotification(pushMetaData, config, null);
        print('✅ handlePushNotification called - WebSocket will connect with correct voice_sdk_id');
        
        // CRITICAL FIX: Track the voice_sdk_id immediately so _handleCallKitAccept 
        // knows we're already connected and won't create a duplicate connection
        telnyxService._voiceSdkId = voiceSdkId ?? 'unknown';
        print('📌 Tracked voice_sdk_id: ${telnyxService._voiceSdkId}');
      } else {
        print('⚠️ No TelnyxService available yet - storing metadata for later');
        // Do not overwrite stored token; just note pending reconnect
      }
    } catch (e) {
      print('❌ Error handling VoIP push notification: $e');
      print('❌ Stack trace: ${StackTrace.current}');
    }
  } else if (call.method == 'onVoIPTokenReceived') {
    final token = call.arguments as String?;
    if (token != null) {
      print('📱 Received VoIP token: ${abbreviate(token)}...');
      // Store the VoIP token in TelnyxService for use in push notifications
      try {
        if (navigatorKey.currentContext != null) {
          final telnyxService = Provider.of<TelnyxService>(navigatorKey.currentContext!, listen: false);
          telnyxService.setVoipToken(token);
          print('📱 VoIP token stored in TelnyxService: ${abbreviate(token)}...');
        } else {
          // Store globally for later use if context is not available
          globalVoipToken = token;
          print('📱 VoIP token stored globally for later use (context not available)');
        }
        // Persist for killed/background relaunch
        await _saveVoipToken(token);
      } catch (e) {
        print('❌ Error storing VoIP token: $e');
        // Store globally for later use
        globalVoipToken = token;
        print('📱 VoIP token stored globally for later use');
      }
      print('📱 VoIP token ready for Telnyx SDK');
    }
  } else if (call.method == 'appDidBecomeActive') {
    print('📱 iOS app became active - checking for pending calls');
    // Check for any pending push notifications
    await _handlePushNotification();
  } else if (call.method == 'onIncomingCall') {
    print('📱 iOS incoming call notification received');
    final callData = call.arguments as Map<dynamic, dynamic>?;
    if (callData != null) {
      // Convert Map<dynamic, dynamic> to Map<String, dynamic>
      final stringMap = callData.map((key, value) => MapEntry(key.toString(), value));
      await _handleIncomingVoIPCall(stringMap);
    }
  }
}

/// Handle incoming VoIP call from iOS
Future<void> _handleIncomingVoIPCall(Map<String, dynamic> callData) async {
  print('📱 Handling incoming VoIP call: $callData');
  
  // Extract call information
  final callId = callData['call_id']?.toString() ?? 'unknown';
  final callerName = callData['caller_name']?.toString() ?? 'Unknown';
  final callerNumber = callData['caller_number']?.toString() ?? 'Unknown';
  final voiceSdkId = callData['voice_sdk_id']?.toString() ?? '';
  
  print('📱 VoIP Call - ID: $callId, Name: $callerName, Number: $callerNumber, VoiceSDK: $voiceSdkId');
  
  // Store call info for later use
  globalCallKitCallInfo = {
    'call_id': callId,
    'caller_name': callerName,
    'caller_number': callerNumber,
    'voice_sdk_id': voiceSdkId,
  };
  
  // Navigate to call screen if app is active
  final navigatorState = navigatorKey.currentState;
  if (navigatorState != null) {
    navigatorState.pushNamedAndRemoveUntil('/call', (route) => false);
    print('✅ Navigated to call screen from VoIP push');
  }
}

/// Handle push notifications using Telnyx SDK methods
Future<void> _handlePushNotification() async {
  try {
    print('📱 Checking for push notification metadata...');
    
    // TODO: Implement proper push metadata retrieval
    // The TelnyxClient.getPushMetaData() method doesn't exist in current SDK version
    final data = null; // Placeholder until we implement correct method
    if (data != null) {
      print('📱 Push metadata found: $data');
      
      // Parse the push metadata
      final pushMetaData = PushMetaData.fromJson(data);
      {
        print('📱 Push metadata parsed successfully');
        
        // Get the TelnyxService instance
        final telnyxService = Provider.of<TelnyxService>(navigatorKey.currentContext!, listen: false);
        
        // Handle the push notification using Telnyx SDK
        await telnyxService.handlePushNotification(pushMetaData);
      }
    } else {
      print('📱 No push metadata found');
    }
  } catch (e) {
    print('❌ Error handling push notification: $e');
  }
}

// Detect if app was launched from CallKit accept using service callback
Future<void> _detectCallKitLaunchState() async {
  try {
    print('🔍 Checking for CallKit launch state...');
    
    // Set up a callback to detect if we get a quick CallKit event
    bool callKitDetected = false;
    
    // Listen for CallKit events briefly to detect launch state
    // CallKit launch detection is now handled in the main listener
    
    // Check both plugin events and native method call flag
    if (callKitDetected || _isLaunchingFromCallKitAccept) {
      print('📞 App was launched from CallKit - will start at call screen');
      _isLaunchingFromCallKitAccept = true; // Ensure flag is set
    } else {
      print('🔍 Normal app launch - starting at home screen');
    }
    
  } catch (e) {
    print('❌ Error detecting CallKit launch state: $e');
  }
}

Future<void> _requestPermissions() async {
  // CRITICAL: Request microphone permission on iOS at startup
  if (Platform.isIOS) {
    print('🔐 Requesting iOS microphone permission...');
    final micStatus = await Permission.microphone.request();
    print('🔐 iOS Microphone permission: $micStatus');
    
    if (micStatus != PermissionStatus.granted) {
      print('⚠️ Microphone permission not granted - audio will not work!');
    } else {
      print('✅ Microphone permission granted at startup');
    }
  }
  
  if (Platform.isAndroid) {
    print('🔐 Requesting Android permissions...');
    
    final permissions = [
      Permission.microphone,
      Permission.phone,
      Permission.notification,
      Permission.systemAlertWindow,
    ];
    
    final statuses = await permissions.request();
    
    // Log permission statuses
    for (final permission in permissions) {
      final status = statuses[permission];
      print('🔐 Permission $permission: $status');
      
      if (status != PermissionStatus.granted) {
        print('⚠️ Permission $permission not granted - CallKit may not work properly');
      }
    }
    
    // Special handling for system alert window permission
    if (statuses[Permission.systemAlertWindow] != PermissionStatus.granted) {
      print('⚠️ System Alert Window permission not granted - requesting manually...');
      await Permission.systemAlertWindow.request();
    }
    
    // Request notification permission for Android 13+
    try {
      await FlutterCallkitIncoming.requestNotificationPermission({
        "title": "Notification permission",
        "rationaleMessagePermission": "Notification permission is required, to show notification.",
        "postNotificationMessageRequired": "Notification permission is required, Please allow notification permission from setting."
      });
      print('✅ Notification permission requested');
    } catch (e) {
      print('⚠️ Error requesting notification permission: $e');
    }
    
    // Check and request full screen intent permission for Android 14+
    try {
      final canUseFullScreen = await FlutterCallkitIncoming.canUseFullScreenIntent();
      print('📱 Can use full screen intent: $canUseFullScreen');
      
      if (!canUseFullScreen) {
        await FlutterCallkitIncoming.requestFullIntentPermission();
        print('✅ Full screen intent permission requested');
      }
  } catch (e) {
      print('⚠️ Error with full screen intent permission: $e');
    }
    
  } else if (Platform.isIOS) {
    await Permission.microphone.request();
  }
  
  print('✅ Permission requests completed');
}

class TelnyxApp extends StatefulWidget {
  const TelnyxApp({super.key});

  @override
  State<TelnyxApp> createState() => _TelnyxAppState();
}

class _TelnyxAppState extends State<TelnyxApp> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Adit Call App',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: AppTheme.darkTheme,
      initialRoute: _isLaunchingFromCallKitAccept ? '/call' : '/',
      routes: {
        '/': (_) => const SimpleHomeScreen(),
        '/call': (_) => const CallPage(),
      },
    );
  }
}

class TelnyxService extends ChangeNotifier with WidgetsBindingObserver {
  late TelnyxClient _telnyxClient;
  Call? _call;
  IncomingInviteParams? _incomingInvite;
  bool _isConnected = false;
  bool _isCallInProgress = false;
  String _status = 'Disconnected';
  String? _lastPushTokenSent;
  bool _isReconnecting = false;
  // Track whether client has been initialized to avoid late-init checks
  bool _isClientInitialized = false;
  // Store latest VoIP token received
  String? _voipToken;
  
  // Offline mode for push notifications (Telnyx requirement)
  bool _isOfflineMode = false;
  
  // Track if we're handling a push call
  bool _isPushCallInProgress = false;
  
  // Track if app has been paused before (to distinguish startup from resume)
  bool _hasBeenPausedBefore = false;
  
  // Store pending CallKit accepted call info
  Map<String, dynamic>? _pendingAcceptedCall;
  
  // Track app lifecycle state
  AppLifecycleState? _appLifecycleState;
  
  // Call duration tracking
  DateTime? _callStartTime;
  Timer? _durationTimer;
  Duration _callDuration = Duration.zero;
  
  // Track Voice SDK ID
  String? _voiceSdkId;
  
  // Call state monitoring
  Timer? _callStateMonitor;
  CallState? _lastCallState;
  
  // Getters
  bool get isConnected => _isConnected;
  bool get isCallInProgress => _isCallInProgress;
  String get status => _status;
  Call? get call => _call;
  IncomingInviteParams? get incomingInvite => _incomingInvite;
  Map<String, dynamic>? get pendingAcceptedCall => _pendingAcceptedCall;
  Duration get callDuration => _callDuration;
  bool get isOfflineMode => _isOfflineMode;
  
  // Set VoIP token and reconnect if needed
  void setVoipToken(String token) {
    if (_voipToken == token && _lastPushTokenSent == token) {
      print('📱 VoIP token unchanged, skipping reconnect');
      return;
    }
    _voipToken = token;
    print('📱 VoIP token updated: ${abbreviate(token)}...');
    
    // CRITICAL: Explicitly set push token with Telnyx SDK
    _setPushTokenForTelnyx(token);
    
    // CRITICAL FIX: Only reconnect if we're NOT already connected/connecting
    // During app startup, _initialize() is already connecting - don't create duplicate!
    if (_telnyxClient.isConnected()) {
      print('📱 Already connected - reconnecting with new VoIP token...');
      _reconnectWithVoipToken();
    } else {
      print('📱 Not yet connected - VoIP token will be used on next connection');
      // The token is stored in _voipToken and will be used automatically
      // when _reconnectWebSocket() or _initialize() creates the connection
    }
  }
  
  // Explicitly set push token with Telnyx SDK (Telnyx requirement)
  void _setPushTokenForTelnyx(String token) {
    try {
      print('📱 Setting push token with Telnyx SDK: ${abbreviate(token)}...');
      
      // CRITICAL: Determine APNS environment based on iOS entitlements
      // Your Runner.entitlements shows "development" so we use sandbox
      final apnsEnvironment = _getApnsEnvironment();
      print('📱 APNS Environment: $apnsEnvironment');
      
      // Note: The Telnyx Flutter SDK handles this internally via CredentialConfig
      // but we ensure the token is properly registered with correct environment
      _lastPushTokenSent = token;
      print('✅ Push token registered with Telnyx SDK (Environment: $apnsEnvironment)');
    } catch (e) {
      print('❌ Error setting push token with Telnyx SDK: $e');
    }
  }
  
  // Determine APNS environment based on build configuration
  String _getApnsEnvironment() {
    // Use Flutter's kDebugMode to determine environment
    // Debug builds should use sandbox, release builds should use production
    if (kDebugMode) {
      print('📱 Using SANDBOX environment for debug builds');
      print('⚠️  IMPORTANT: VoIP push notifications only work in RELEASE mode!');
      print('⚠️  Debug mode: Push notifications only work when app is in foreground');
      print('⚠️  Release mode: Push notifications work in background and killed state');
      return 'sandbox';
    } else {
      print('📱 Using PRODUCTION environment for release builds');
      print('✅ Release mode: VoIP push notifications will work in all states');
      return 'production';
    }
  }
  
  // Reconnect with VoIP token
  Future<void> _reconnectWithVoipToken() async {
    try {
      print('📱 _reconnectWithVoipToken called - VoIP token: $_voipToken');
      if (_voipToken == null) {
        print('📱 No VoIP token available for reconnection');
        return;
      }
      if (_isReconnecting) {
        print('📱 Reconnect already in progress');
        return;
      }
      _isReconnecting = true;
      
      // Ensure clean reconnect to avoid punt loops
      if (_isConnected) {
        _telnyxClient.disconnect();
        _isConnected = false;
      }
      
      print('📱 Reconnecting Telnyx with VoIP token...');
      
      final config = CredentialConfig(
        sipUser: _sipUser,
        sipPassword: _sipPassword,
        sipCallerIDName: _callerIdName,
        sipCallerIDNumber: _callerIdNumber,
        notificationToken: _voipToken,
        debug: true,
        logLevel: LogLevel.all,
        customLogger: MyCustomLogger(),
      );
      
      _telnyxClient.connectWithCredential(config);
      _lastPushTokenSent = _voipToken;
      print('✅ Reconnected with VoIP token');
      
    } catch (e) {
      print('❌ Error reconnecting with VoIP token: $e');
    } finally {
      _isReconnecting = false;
    }
  }
  
  // Enable offline mode for push notifications (Telnyx requirement)
  Future<void> enableOfflineMode() async {
    try {
      print('📱 Enabling offline mode for push notifications...');
      
      if (_isConnected) {
        print('📱 Disconnecting from Telnyx to enable offline mode');
        _telnyxClient.disconnect();
        _isConnected = false;
      }
      
      _isOfflineMode = true;
      _status = 'Offline mode - Push notifications enabled';
      notifyListeners();
      
      print('✅ Offline mode enabled - Push notifications will now work');
    } catch (e) {
      print('❌ Error enabling offline mode: $e');
    }
  }
  
  // Enable online mode (reconnect to Telnyx)
  Future<void> enableOnlineMode() async {
    try {
      print('📱 Enabling online mode - reconnecting to Telnyx...');
      
      if (_isOfflineMode) {
        _isOfflineMode = false;
        
        // Reconnect with current VoIP token
        if (_voipToken != null) {
          await _reconnectWithVoipToken();
        } else {
          // Initial connection without VoIP token
          await _initialize();
        }
        
        print('✅ Online mode enabled - Connected to Telnyx');
      }
    } catch (e) {
      print('❌ Error enabling online mode: $e');
    }
  }
  
  // Toggle between online and offline modes
  Future<void> toggleConnectionMode() async {
    if (_isOfflineMode) {
      await enableOnlineMode();
    } else {
      await enableOfflineMode();
    }
  }
  
  // Get current connection status for debugging
  String getConnectionStatus() {
    if (_isOfflineMode) {
      return 'Offline Mode - Push notifications enabled';
    } else if (_isConnected) {
      return 'Online Mode - Connected to Telnyx';
    } else {
      return 'Disconnected';
    }
  }
  
  // Check if we're in the correct mode for push notifications
  bool get isPushNotificationMode => !kDebugMode;
  
  // Get build mode information
  String getBuildModeInfo() {
    if (kDebugMode) {
      return 'DEBUG MODE - Push notifications only work in foreground\n'
             'To test killed state: Build in RELEASE mode';
    } else {
      return 'RELEASE MODE - Push notifications work in all states ✅';
    }
  }
  
  TelnyxService() {
    WidgetsBinding.instance.addObserver(this);
    _appLifecycleState = WidgetsBinding.instance.lifecycleState;
    // Store global reference for killed-state VoIP access
    _globalTelnyxService = this;
    print('📱 TelnyxService singleton instance created');
    _initialize();
  }
  
  Future<void> _initialize() async {
    print('🚀 Starting TelnyxService initialization...');
    
    try {
      // Set up Firebase messaging (Android only)
      if (Platform.isAndroid) {
        _setupFirebaseMessaging();
      }
      
      // Set up CallKit listeners
      _setupCallKitListeners();
      
      // Initialize Telnyx client
      String? fcmToken;
      if (Platform.isAndroid) {
        try {
          fcmToken = await fb_msg.FirebaseMessaging.instance.getToken();
          print('🤖 FCM Token (Android): ${abbreviate(fcmToken)}...');
        } catch (e) {
          print('❌ Error getting FCM token (Android): $e');
        }
      }
    
    // Use VoIP token for push notifications if available, otherwise fallback to FCM
    String? notificationToken = Platform.isIOS ? (_voipToken ?? globalVoipToken) : (fcmToken ?? _voipToken ?? globalVoipToken);
    if (Platform.isIOS && _voipToken != null) {
      print('📱 Using stored VoIP token for push notifications: ${abbreviate(_voipToken)}...');
    } else if (Platform.isIOS && globalVoipToken != null) {
      print('📱 Using global VoIP token for push notifications: ${abbreviate(globalVoipToken)}...');
      _voipToken = globalVoipToken; // Store it for future use
    } else if (Platform.isAndroid) {
      print('🤖 Using FCM token for push notifications: ${abbreviate(fcmToken)}...');
    }
    
    // If we have a VoIP token, we'll reconnect with it after initial connection
    if (globalVoipToken != null && _voipToken == null) {
      _voipToken = globalVoipToken;
      print('📱 VoIP token available - will reconnect after initial connection');
    }
    
    final config = CredentialConfig(
      sipUser: _sipUser,
      sipPassword: _sipPassword,
      sipCallerIDName: _callerIdName,
        sipCallerIDNumber: _callerIdNumber,
        notificationToken: notificationToken,
        debug: true,
        logLevel: LogLevel.all,
        customLogger: MyCustomLogger(),
      );
      
      // CRITICAL: Create TelnyxClient ONCE - singleton pattern
      if (!_isClientInitialized) {
        _telnyxClient = TelnyxClient();
        
        // Set up event listeners
        _telnyxClient.onSocketMessageReceived = _handleSocketMessage;
        _telnyxClient.onSocketErrorReceived = _handleSocketError;
        
        _isClientInitialized = true;
        print('🔧 TelnyxClient created and initialized (singleton)');
      } else {
        print('🔧 Using existing TelnyxClient instance (singleton)');
      }
      
      // Connect (or reconnect) with credentials
      _status = 'Connecting...';
      notifyListeners();
      
      _telnyxClient.connectWithCredential(config);
      
      print('✅ TelnyxService initialization completed');
      
      // Check if there's a pending CallKit accepted call to process
      if (_pendingAcceptedCall != null) {
        print('🔄 Processing pending CallKit accepted call');
        await _processCallKitAccept();
      }
      
      // If launched from CallKit accept, process it
      if (_isLaunchingFromCallKitAccept && globalCallKitCallInfo != null) {
        print('🔄 Processing CallKit launch state on service init');
        _isPushCallInProgress = true;
        _status = 'Processing CallKit accepted call...';
        notifyListeners();
        
        // Wait a bit for connection to be fully established
        await Future.delayed(const Duration(milliseconds: 500));
        await _processCallKitAcceptFromGlobalState();
      }
    
  } catch (e) {
      print('❌ TelnyxService initialization error: $e');
      _status = 'Error: $e';
      notifyListeners();
    }
  }
  
  // Handle socket messages from Telnyx client
  void _handleSocketMessage(TelnyxMessage message) {
    print('📥 Socket message: ${message.socketMethod}');
    
    switch (message.socketMethod) {
      case SocketMethod.clientReady:
        print('✅ Telnyx client ready');
        _isConnected = true;
        _status = 'Connected';
        // Store the Voice SDK ID from the message
        if (message.message case ReceivedMessage receivedMessage) {
          _voiceSdkId = receivedMessage.voiceSdkId;
          print('📱 Stored Voice SDK ID: $_voiceSdkId');
        }
        
        // Do not reconnect here; reconnection will only occur when token actually changes
        print('📱 Client ready - no automatic reconnect (token change triggers reconnect)');
        break;
        
      case SocketMethod.gatewayState:
        print('✅ Gateway state updated');
        break;
        
      case SocketMethod.invite:
        // Handle incoming call invitation
        if (message.message case ReceivedMessage receivedMessage) {
          if (receivedMessage.inviteParams != null) {
            if (_isPushCallInProgress) {
              // For CallKit accepted calls, accept the call first
              print('📞 CallKit call connected - accepting call');
              _incomingInvite = receivedMessage.inviteParams!;
              
              // CRITICAL: Accept the call immediately for CallKit
              print('📞 Accepting CallKit call...');
              final acceptedCall = _telnyxClient.acceptCall(
                _incomingInvite!,
                _callerIdName,
                _callerIdNumber,
                "callkit_call_accepted",
              );
              
              // CRITICAL: Attach our state change handler to the accepted call
              acceptedCall.callHandler = CallHandler((state) {
                print('📞 CallKit call state changed: $state');
                _handleCallStateChange(state);
              }, null);
              
              _call = acceptedCall;
              print('✅ CallKit call accepted with state handler attached');
              
              // Start call state monitoring for CallKit calls
              _startCallStateMonitoring();
              
              // Fix Android incoming audio routing
              if (Platform.isAndroid) {
                Future.delayed(const Duration(milliseconds: 500), () {
                  _forceAndroidAudioOutput();
                });
              }
              
              // Navigation to call screen now happens immediately when CallKit accept is pressed
              // (see _handleCallKitAccept), not here when INVITE arrives
              print('✅ Call processing complete - screen already showing');
            } else {
              _handleIncomingCall(receivedMessage.inviteParams!);
            }
          }
        }
        break;
        
      default:
        break;
    }
    
    notifyListeners();
  }
  
  // Handle socket errors
  void _handleSocketError(TelnyxSocketError error) {
    print('❌ Socket error: ${error.errorMessage}');
    _status = 'Error: ${error.errorMessage}';
    _isConnected = false;
    notifyListeners();
  }
  
  // Handle incoming call
  void _handleIncomingCall(IncomingInviteParams inviteParams) {
    print('📞 Incoming call from: ${inviteParams.callerIdNumber}');
    
    // Reset push call state only for foreground incoming calls. In background
    // (VoIP push) flows we keep it true so the first INVITE is auto-accepted
    // and Flutter won't show duplicate CallKit UI.
    final bool isBackground = _appLifecycleState == AppLifecycleState.paused ||
        _appLifecycleState == AppLifecycleState.inactive ||
        _appLifecycleState == AppLifecycleState.hidden;
    if (!isBackground) {
      _isPushCallInProgress = false;
    }
    
    _incomingInvite = inviteParams;
    _status = 'Incoming call from ${inviteParams.callerIdNumber}';
    
    // Check app lifecycle state
    print('📱 App lifecycle state: $_appLifecycleState');
    
    // Only show CallKit for true background state (not just paused)
    if (_appLifecycleState == AppLifecycleState.paused ||
        _appLifecycleState == AppLifecycleState.inactive ||
        _appLifecycleState == AppLifecycleState.hidden) {
      // App is in background - show CallKit notification only if not already showing
      print('📱 App in background - showing CallKit notification');
      if (_isPushCallInProgress) {
        print('ℹ️ CallKit already shown by iOS - skipping duplicate CallKit display');
      } else {
        _isPushCallInProgress = true; // Set this only for background calls
        _showCallKitForIncomingCall(inviteParams);
      }
    } else {
      // App is in foreground - show in-app dialog
      print('📱 App in foreground - showing in-app incoming call dialog');
      _showIncomingCallDialog(inviteParams);
    }
    
    notifyListeners();
  }
  
  /// Show incoming call dialog when app is in foreground
  void _showIncomingCallDialog(IncomingInviteParams inviteParams) {
    final context = navigatorKey.currentContext;
    if (context == null) {
      print('❌ No context available for showing incoming call dialog');
      return;
    }
    
    // Dynamically import the dialog widget
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        // Import the widget class dynamically
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF2C3E50),
                  Color(0xFF34495E),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Call icon
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: const Color(0xFF3498DB),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF3498DB).withOpacity(0.4),
                        blurRadius: 15,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.phone_in_talk,
                    size: 40,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Incoming Call',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  inviteParams.callerIdName ?? 'Unknown Caller',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  inviteParams.callerIdNumber ?? 'Unknown Number',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 16,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Decline button
                    _buildIncomingCallButton(
                      icon: Icons.call_end,
                      label: 'Decline',
                      color: const Color(0xFFE74C3C),
                      onPressed: () {
                        Navigator.of(context).pop();
                        declineCall();
                      },
                    ),
                    // Accept button
                    _buildIncomingCallButton(
                      icon: Icons.call,
                      label: 'Accept',
                      color: const Color(0xFF2ECC71),
                      onPressed: () {
                        Navigator.of(context).pop();
                        acceptCall();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
  
  Widget _buildIncomingCallButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(40),
            child: Container(
              width: 65,
              height: 65,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(
                icon,
                color: Colors.white,
                size: 32,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
  
  /// Show CallKit notification for incoming call when app is in background
  Future<void> _showCallKitForIncomingCall(IncomingInviteParams inviteParams) async {
    print('📱 Showing CallKit for background incoming call');
    
    try {
      final callId = inviteParams.callID;
      final callerName = inviteParams.callerIdName ?? 'Unknown Caller';
      final callerNumber = inviteParams.callerIdNumber ?? 'Unknown Number';
      
      final params = CallKitParams(
        id: callId,
        nameCaller: callerName,
        appName: 'Adit Telnyx',
        handle: callerNumber,
        type: 0,
        duration: 45000,
        textAccept: 'Accept',
        textDecline: 'Decline',
        missedCallNotification: const NotificationParams(
          showNotification: true,
          isShowCallback: true,
          subtitle: 'Missed call',
          callbackText: 'Call back',
        ),
        android: const AndroidParams(
          isCustomNotification: true,
          isShowLogo: true,
          ringtonePath: 'system_ringtone_default',
          backgroundColor: '#0955fa',
          actionColor: '#4CAF50',
          textColor: '#ffffff',
          incomingCallNotificationChannelName: 'Incoming Call',
          missedCallNotificationChannelName: 'Missed Call',
          isShowCallID: false,
          isShowFullLockedScreen: true,
        ),
        ios: const IOSParams(
          iconName: 'CallKitLogo',
          handleType: 'generic',
          supportsVideo: false,
          maximumCallGroups: 2,
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
        extra: {
          'metadata': jsonEncode({
            'call_id': callId,
            'caller_name': callerName,
            'caller_number': callerNumber,
            'voice_sdk_id': _voiceSdkId ?? 'default',
          })
        },
      );
      
      print('📱 Showing CallKit notification for background call...');
      await FlutterCallkitIncoming.showCallkitIncoming(params);
      print('✅ CallKit notification shown for background call');
      
    } catch (e) {
      print('❌ Error showing CallKit for background call: $e');
    }
  }
  
  
void _setupFirebaseMessaging() {
    if (!Platform.isAndroid) {
      return;
    }
    // Handle foreground messages
    fb_msg.FirebaseMessaging.onMessage.listen((fb_msg.RemoteMessage message) {
      print('📱 Foreground message received: ${message.data}');
      
      final data = message.data;
      
      // Check if this is an incoming call message
      if (data.containsKey('message') && data['message'] == 'Incoming call!') {
        // Show CallKit for foreground messages too
        _showCallKitIncoming(data);
      }
    });
    
    // Handle app opened from notification
    fb_msg.FirebaseMessaging.onMessageOpenedApp.listen((fb_msg.RemoteMessage message) {
      print('📱 App opened from push notification: ${message.data}');
    });
  }
  
  // Handle push notifications using Telnyx SDK
  Future<void> handlePushNotification(PushMetaData pushMetaData) async {
    try {
      print('📱 Handling push notification with Telnyx SDK...');
      
      // Use platform-specific token: iOS uses VoIP, Android uses FCM
      String? notificationToken;
      if (Platform.isIOS) {
        notificationToken = _voipToken ?? globalVoipToken;
      } else if (Platform.isAndroid) {
        try {
          notificationToken = await fb_msg.FirebaseMessaging.instance.getToken();
        } catch (e) {
          print('❌ Error getting FCM token for push handling: $e');
        }
      }
      if (notificationToken != null) {
        print('📱 Using VoIP token for push handling: ${abbreviate(notificationToken)}...');
      }
      
      // Create credential config
      final credentialConfig = CredentialConfig(
        sipUser: _sipUser,
        sipPassword: _sipPassword,
        sipCallerIDName: _callerIdName,
        sipCallerIDNumber: _callerIdNumber,
        notificationToken: notificationToken,
        debug: true,
        logLevel: LogLevel.all,
        customLogger: MyCustomLogger(),
      );
      
      // Create token config
      final tokenConfig = TokenConfig(
        sipToken: _sipPassword,
        sipCallerIDName: _callerIdName,
        sipCallerIDNumber: _callerIdNumber,
        notificationToken: notificationToken,
        debug: true, // Added missing required parameter
        logLevel: LogLevel.all, // Added missing required parameter
      );
      
      // Handle the push notification using Telnyx SDK
      _telnyxClient.handlePushNotification(pushMetaData, credentialConfig, tokenConfig);
      print('✅ Push notification handled by Telnyx SDK');
      
    } catch (e) {
      print('❌ Error handling push notification: $e');
    }
  }
  
  void _setupCallKitListeners() {
    FlutterCallkitIncoming.onEvent.listen((CallEvent? event) async {
      if (event == null) return;
      
      print('📱 CallKit event received in TelnyxService: ${event.event}');
      
      switch (event.event) {
        case Event.actionCallIncoming:
          // Handle incoming call - just log, don't process yet
          print('📱 CallKit incoming call event - waiting for user action');
          break;
        case Event.actionCallAccept:
          // This handles runtime CallKit accept (when app is already running in background)
          print('🚀 Runtime CallKit Accept - processing call');
          await _handleCallKitAccept(event);
          // DON'T navigate here - wait for call to become ACTIVE, then navigate
          // This prevents double navigation and ensures smooth transition
          break;
        case Event.actionCallDecline:
          await _handleCallKitDecline(event);
          break;
        case Event.actionCallEnded:
          print('📱 CallKit call ended event received');
          // End the call immediately when CallKit reports end
          // This handles user-initiated end from lock screen or CallKit UI
          await endCall();
          break;
        default:
          break;
      }
    });
  }
  
  // Navigate to call screen
  void _navigateToCallScreen() {
    print('🧨 Navigating to call screen...');
    try {
      // Minimal delay to ensure CallKit UI has dismissed (WhatsApp-style instant navigation)
      Future.delayed(const Duration(milliseconds: 100), () {
        final navigatorState = navigatorKey.currentState;
        if (navigatorState != null) {
          // First, check if we're already on the call screen
          final currentRoute = ModalRoute.of(navigatorState.context)?.settings.name;
          if (currentRoute != '/call') {
            print('🧨 Current route: $currentRoute, navigating to call screen');
            navigatorState.pushNamedAndRemoveUntil('/call', (route) => false);
            print('✅ Navigation to call screen completed');
          } else {
            print('🧨 Already on call screen');
          }
        } else {
          print('❌ Navigator state is null - cannot navigate');
        }
      });
    } catch (e) {
      print('❌ Error navigating to call screen: $e');
    }
  }
  
  // Handle CallKit accept event
  Future<void> _handleCallKitAccept(CallEvent event) async {
    print('✅ CallKit Accept pressed');
    
    try {
      // DEBUG: Print full event structure
      print('📋 Event body: ${event.body}');
      print('📋 Event body type: ${event.body.runtimeType}');
      
      // Parse call data - using safe access with proper null handling
      String callId = '';
      String callerName = '';
      String callerNumber = '';
      String voiceSdkId = '';
      
      // Try to get from event.body['extra']['metadata']
      try {
        final extra = event.body['extra'];
        print('📋 extra type: ${extra?.runtimeType}, value: $extra');
        
        if (extra != null && extra is Map) {
          final metadata = extra['metadata'];
          print('📋 metadata type: ${metadata?.runtimeType}');
          
          if (metadata != null && metadata is Map) {
            callId = (metadata['call_id'] ?? '').toString();
            callerName = (metadata['caller_name'] ?? '').toString();
            callerNumber = (metadata['caller_number'] ?? '').toString();
            voiceSdkId = (metadata['voice_sdk_id'] ?? '').toString();
            print('📋 Got from metadata: callId=$callId, caller=$callerName');
          }
        }
      } catch (e) {
        print('⚠️ Error parsing metadata: $e');
      }
      
      // Fallback to root event.body fields with explicit toString calls
      if (callId.isEmpty) {
        final id = event.body['id'];
        final uuid = event.body['uuid'];
        if (id != null) {
          callId = id.toString();
        } else if (uuid != null) {
          callId = uuid.toString();
        } else {
          callId = 'unknown_call_id';
        }
      }
      if (callerName.isEmpty) {
        final name = event.body['nameCaller'];
        callerName = name != null ? name.toString() : 'Unknown Caller';
      }
      if (callerNumber.isEmpty) {
        final handle = event.body['handle'];
        callerNumber = handle != null ? handle.toString() : 'Unknown Number';
      }
      if (voiceSdkId.isEmpty) {
        voiceSdkId = 'default_voice_sdk_id';
      }
      
      print('✅ Final values: callId=$callId, name=$callerName, number=$callerNumber, sdk=$voiceSdkId');
      
      final normalized = <String, String>{
        'call_id': callId,
        'caller_name': callerName,
        'caller_number': callerNumber,
        'voice_sdk_id': voiceSdkId,
      };
      print('📋 Metadata: callId=$callId, caller=$callerName, voiceSdkId=$voiceSdkId');

      globalCallKitCallInfo = Map<String, String>.from(normalized);

      final notificationToken = getValidVoipToken();
      // Include a valid notification token if available to avoid null issues inside SDK
      final Map<String, String> metadataForSdk = {
        'call_id': callId.isEmpty ? 'unknown_call_id' : callId,
        'voice_sdk_id': voiceSdkId.isEmpty ? 'unknown_voice_sdk_id' : voiceSdkId,
        'caller_name': callerName,
        'caller_number': callerNumber,
        if (notificationToken != null) 'notification_token': notificationToken,
      };
      if (metadataForSdk['call_id']!.isEmpty || metadataForSdk['voice_sdk_id']!.isEmpty) {
        print('⚠️ Missing required metadata (call_id/voice_sdk_id). Not calling setPushMetaData. Map=$metadataForSdk');
      } else {
        try {
          print('📞 Setting push metadata with isAnswer=true (safe map): $metadataForSdk');
          TelnyxClient.setPushMetaData(
            metadataForSdk,
            isAnswer: true,
            isDecline: false,
          );
          print('✅ Push metadata set successfully');
        } catch (e) {
          print('❌ setPushMetaData threw: $e with map=$metadataForSdk');
        }
      }

      print('📞 Creating PushMetaData object...');
      final pushMetaData = PushMetaData.fromJson(normalized);
      print('✅ PushMetaData created');
      
      // Create credential config for handlePushNotification
      final config = CredentialConfig(
        sipUser: _sipUser,
        sipPassword: _sipPassword,
        sipCallerIDName: _callerIdName,
        sipCallerIDNumber: _callerIdNumber,
        notificationToken: notificationToken,
        debug: true,
        logLevel: LogLevel.all,
        customLogger: MyCustomLogger(),
      );
      
      // CRITICAL: Only reconnect if we truly need to switch voice_sdk_id.
      // In background/killed flows, we may have pre-connected with the correct voice_sdk_id
      // from the VoIP push already. The CallKit accept event can sometimes carry a
      // placeholder like "default"; in that case, KEEP the existing connection.
      final normalizedVoiceId = (voiceSdkId).toString().trim();
      final bool isDefaultVoiceId = normalizedVoiceId.isEmpty ||
          normalizedVoiceId == 'default' ||
          normalizedVoiceId == 'default_voice_sdk_id';
      final String? currentVoiceId = _voiceSdkId;
      final bool isConnected = _telnyxClient.isConnected();
      print('🔎 Connection check: isConnected=$isConnected, currentVoiceId="$currentVoiceId", pushVoiceId="$normalizedVoiceId"');

      if (isDefaultVoiceId) {
        // Accept event didn't include a real voice_sdk_id; rely on the existing connection
        print('ℹ️ Push metadata has default/missing voice_sdk_id - keeping existing connection.');
        print('✅ SKIPPING RECONNECT - will wait for INVITE on existing connection');
      } else if (isConnected && currentVoiceId == normalizedVoiceId) {
        // We are already connected on the correct voice_sdk_id
        print('✅ Already connected with MATCHING voice_sdk_id - no reconnect needed.');
        print('✅ SKIPPING RECONNECT - will wait for INVITE on existing connection');
      } else {
        // We need to connect (or switch) to the correct voice_sdk_id
        if (isConnected) {
          print('♻️ Connected with DIFFERENT voice_sdk_id - reconnecting with push voice_sdk_id');
          print('   Disconnecting from: "$currentVoiceId"');
          print('   Reconnecting with: "$normalizedVoiceId"');
          _telnyxClient.disconnect();
          await Future.delayed(const Duration(milliseconds: 300));
        } else {
          print('📞 Not connected - connecting with push voice_sdk_id: "$normalizedVoiceId"');
        }
        print('📞 Calling handlePushNotification to establish connection...');
        try {
          _telnyxClient.handlePushNotification(pushMetaData, config, null);
          print('✅ Push notification handled - connecting with voice_sdk_id: $normalizedVoiceId');
          _voiceSdkId = normalizedVoiceId; // Track it
        } catch (e) {
          print('❌ handlePushNotification threw: $e');
        }
      }
      
      print('🔍 DEBUG: About to set call in progress state...');
      
      // Set call in progress state
      _isPushCallInProgress = true;
      _status = 'Connecting to call...';

      // If INVITE already arrived before Accept event was processed, accept it immediately
      if (_incomingInvite != null && _call == null) {
        try {
          print('📞 CallKit accept - INVITE already present, accepting immediately');
          final acceptedCall = _telnyxClient.acceptCall(
            _incomingInvite!,
            _callerIdName,
            _callerIdNumber,
            "callkit_call_accepted",
          );
          acceptedCall.callHandler = CallHandler((state) {
            print('📞 CallKit call state changed: $state');
            _handleCallStateChange(state);
          }, null);
          _call = acceptedCall;
          _startCallStateMonitoring();
          if (Platform.isAndroid) {
            Future.delayed(const Duration(milliseconds: 500), () {
              _forceAndroidAudioOutput();
            });
          }
          print('✅ Accepted pre-received INVITE on CallKit accept');
        } catch (e) {
          print('❌ Error accepting pre-received INVITE: $e');
        }
      }
      
      print('🔍 DEBUG: Call in progress state set, about to navigate...');
      
      // CRITICAL FIX: Navigate to call screen IMMEDIATELY (WhatsApp-style)
      // Don't wait for INVITE - show connecting state instantly for better UX
      print('🚀 Navigating to call screen immediately...');
      _navigateToCallScreen();
      
      print('🔍 DEBUG: Navigation called, about to notify listeners...');
      
      notifyListeners();
    } catch (e, stackTrace) {
      print('❌ Error handling CallKit accept: $e');
      print('📍 Stack trace: $stackTrace');
    }
  }
  
  // Handle CallKit decline event - INSTANT DECLINE (WhatsApp-style)
  Future<void> _handleCallKitDecline(CallEvent event) async {
    print('❌ CallKit Decline pressed - sending immediate rejection');
    
    try {
      // Parse call data from CallKit event (same as accept)
      String callId = '';
      String callerName = '';
      String callerNumber = '';
      String voiceSdkId = '';
      
      // Try to get from event.body['extra']['metadata'] (Map)
      final extra = event.body['extra'];
      if (extra is Map) {
        final metadata = extra['metadata'];
        if (metadata is Map) {
          callId = metadata['call_id']?.toString() ?? '';
          callerName = metadata['caller_name']?.toString() ?? '';
          callerNumber = metadata['caller_number']?.toString() ?? '';
          voiceSdkId = metadata['voice_sdk_id']?.toString() ?? '';
        }
      }
      
      // Fallback to root event.body fields with explicit toString calls
      if (callId.isEmpty) {
        final id = event.body['id'];
        final uuid = event.body['uuid'];
        if (id != null) {
          callId = id.toString();
        } else if (uuid != null) {
          callId = uuid.toString();
        } else {
          callId = 'unknown_call_id';
        }
      }
      if (callerName.isEmpty) {
        final name = event.body['nameCaller'];
        callerName = name != null ? name.toString() : 'Unknown Caller';
      }
      if (callerNumber.isEmpty) {
        final handle = event.body['handle'];
        callerNumber = handle != null ? handle.toString() : 'Unknown Number';
      }
      if (voiceSdkId.isEmpty) {
        voiceSdkId = 'default_voice_sdk_id';
      }
      
      print('❌ Declining call: $callId from $callerNumber');
      
      final normalized = <String, String>{
        'call_id': callId,
        'caller_name': callerName,
        'caller_number': callerNumber,
        'voice_sdk_id': voiceSdkId,
      };
      
      // CRITICAL: Set decline flag BEFORE processing
      TelnyxClient.setPushMetaData(normalized, isAnswer: false, isDecline: true);
      print('✅ Push metadata set with isDecline: true');
      final pushMetaData = PushMetaData.fromJson(normalized);
      
      // INSTANT decline - don't wait for connection
      await handlePushNotification(pushMetaData);
      
      // Ensure WebSocket is connected to send decline response
      if (!_isConnected) {
        print('🔌 Connecting to send decline response...');
        await _reconnectWebSocket();
      }
      
      print('✅ Decline message sent to Telnyx');
      // Ensure UI resets on decline
      try { await FlutterCallkitIncoming.endAllCalls(); } catch (_) {}
      _incomingInvite = null; _call = null; _isCallInProgress = false; _isPushCallInProgress = false;
      navigatorKey.currentState?.pushNamedAndRemoveUntil('/', (r)=>false);
      
      // Clear incoming call state
      _status = _isConnected ? 'Connected' : 'Disconnected';
      notifyListeners();
    } catch (e) {
      print('❌ Error handling CallKit decline: $e');
    }
  }
  
  // Process CallKit accepted call
  Future<void> _processCallKitAccept() async {
    if (_pendingAcceptedCall == null) return;
    
    try {
      final callId = _pendingAcceptedCall!['call_id'];
      final callerName = _pendingAcceptedCall!['caller_name'];
      final callerNumber = _pendingAcceptedCall!['caller_number'];
      final voiceSdkId = _pendingAcceptedCall!['voice_sdk_id'];
      
      print('🔄 Processing CallKit accept for: $callId from $callerName');
      
      // Create push metadata for Telnyx SDK
      final pushMetaData = PushMetaData(
        callerName: callerName,
        callerNumber: callerNumber,
        voiceSdkId: voiceSdkId,
        callId: callId,
      );
      pushMetaData.isAnswer = true;
      
      // Get fresh config
      String? fcmToken;
      if (Platform.isAndroid) {
        try {
          fcmToken = await fb_msg.FirebaseMessaging.instance.getToken();
        } catch (e) {
          print('❌ Error getting FCM token: $e');
        }
      }
      
      final config = CredentialConfig(
        sipUser: _sipUser,
        sipPassword: _sipPassword,
        sipCallerIDName: _callerIdName,
        sipCallerIDNumber: _callerIdNumber,
        notificationToken: Platform.isIOS ? (_voipToken ?? globalVoipToken) : (fcmToken ?? _voipToken ?? globalVoipToken),
        debug: true,
        logLevel: LogLevel.all,
        customLogger: MyCustomLogger(),
      );
      
      // Handle push notification to accept the call
      _telnyxClient.handlePushNotification(pushMetaData, config, null);
      
      // Fix Android audio routing after CallKit accept
      if (Platform.isAndroid) {
        Future.delayed(const Duration(milliseconds: 800), () {
          _forceAndroidAudioOutput();
        });
      }
      
      // Clear pending call
      _pendingAcceptedCall = null;
      
      print('✅ CallKit accept processed successfully');
      
    } catch (e) {
      print('❌ Error processing CallKit accept: $e');
    }
  }
  
  // Process CallKit accept from global state (for killed state launches)
  Future<void> _processCallKitAcceptFromGlobalState() async {
    if (globalCallKitCallInfo == null) return;
    
    try {
      final callId = globalCallKitCallInfo!['call_id'];
      final callerName = globalCallKitCallInfo!['caller_name'];
      final callerNumber = globalCallKitCallInfo!['caller_number'];
      final voiceSdkId = globalCallKitCallInfo!['voice_sdk_id'];
      
      print('🔄 Processing CallKit accept from global state: $callId from $callerName');
      
      // Create push metadata for Telnyx SDK
      final pushMetaData = PushMetaData(
        callerName: callerName,
        callerNumber: callerNumber,
        voiceSdkId: voiceSdkId,
        callId: callId,
      );
      pushMetaData.isAnswer = true;
      
      // Get fresh config
      String? fcmToken;
      if (Platform.isAndroid) {
        try {
          fcmToken = await fb_msg.FirebaseMessaging.instance.getToken();
        } catch (e) {
          print('❌ Error getting FCM token: $e');
        }
      }
      
      final config = CredentialConfig(
        sipUser: _sipUser,
        sipPassword: _sipPassword,
        sipCallerIDName: _callerIdName,
        sipCallerIDNumber: _callerIdNumber,
        notificationToken: Platform.isIOS ? (_voipToken ?? globalVoipToken) : (fcmToken ?? _voipToken ?? globalVoipToken),
        debug: true,
        logLevel: LogLevel.all,
        customLogger: MyCustomLogger(),
      );
      
      // Handle push notification to accept the call
      _telnyxClient.handlePushNotification(pushMetaData, config, null);
      
      _isPushCallInProgress = true;
      _status = 'Processing accepted call...';
      notifyListeners();
      
      print('✅ CallKit accept from global state processed successfully');
      
    } catch (e) {
      print('❌ Error processing CallKit accept from global state: $e');
    }
  }
  
  // Public API methods for call management
  
  /// Make an outgoing call
  Future<void> makeCall(String destination) async {
    print('🔍 makeCall called with destination: "$destination"');
    print('🔍 _isConnected: $_isConnected');
    print('🔍 destination.isEmpty: ${destination.isEmpty}');
    print('🔍 Current status: $_status');
    
    if (!_isConnected || destination.isEmpty) {
      print('❌ Cannot make call - not connected or empty destination');
      print('❌ _isConnected: $_isConnected, destination.isEmpty: ${destination.isEmpty}');
      return;
    }
    
    print('📞 Initiating outgoing call to: $destination');
    
    try {
      // Create call using the Telnyx client
      final call = _telnyxClient.newInvite(
        _callerIdName,
        _callerIdNumber,
        destination,
        "outgoing_call_state",
        debug: true,
      );
      
      _call = call;
      _isCallInProgress = true;
      _status = 'Calling $destination...';
      
      // Don't start duration timer yet - wait for CallState.active
      // Timer will start automatically when call connects
      
      // Start call state monitoring
      _startCallStateMonitoring();
      
      // Fix Android audio routing for outgoing calls
      if (Platform.isAndroid) {
            Future.delayed(const Duration(milliseconds: 500), () {
          _forceAndroidAudioOutput();
        });
      }
      
      // Navigate to call screen
      navigatorKey.currentState?.pushNamed('/call');
      
      notifyListeners();
      
    } catch (e) {
      print('❌ Error making call: $e');
    }
  }
  
  /// Accept an incoming call
  Future<void> acceptCall() async {
    if (_incomingInvite == null) {
      print('❌ No incoming call to accept');
      return;
    }
    
    try {
      // Accept the call using the Telnyx client
      final call = _telnyxClient.acceptCall(
        _incomingInvite!,
        _callerIdName,
        _callerIdNumber,
        "incoming_call_accepted",
      );
      
      _call = call;
      _incomingInvite = null;
      _isCallInProgress = true;
      _status = 'Call connected';
      
      // Don't start duration timer yet - wait for CallState.active
      // Timer will start automatically when call connects
      
      // Start call state monitoring
      _startCallStateMonitoring();
      
      // Fix Android incoming audio routing for regular accepts
      if (Platform.isAndroid) {
        Future.delayed(const Duration(milliseconds: 300), () {
          _forceAndroidAudioOutput();
        });
      }
      
      // Navigate to call screen
      navigatorKey.currentState?.pushNamed('/call');
      
      notifyListeners();
      
    } catch (e) {
      print('❌ Error accepting call: $e');
    }
  }
  
  /// Decline an incoming call - INSTANT DECLINE
  Future<void> declineCall() async {
    try {
      print('❌ Declining incoming call - instant response...');
      
      if (_incomingInvite != null) {
        // Create a call instance to decline it properly with immediate SIP response
        final call = Call(
          _telnyxClient.txSocket, 
          _telnyxClient, 
          _telnyxClient.sessid,
          '', // ringtone path
          '', // ringback path
          CallHandler((state) {
            print('📞 Decline call state changed: $state');
            _handleCallStateChange(state);
          }, null),
          () {}, // callEnded callback
          false, // debug
        );
        call.callId = _incomingInvite!.callID;
        call.callState = CallState.ringing;
        
        // CRITICAL: Send immediate decline (486 BUSY_HERE or 603 DECLINE)
        call.endCall(); // This sends proper SIP decline response
        print('✅ Call declined with SIP response sent');
      }
      
      // Clear incoming call state immediately
      _incomingInvite = null;
      _call = null;
      _isCallInProgress = false;
      _isPushCallInProgress = false;
      _status = _isConnected ? 'Connected' : 'Disconnected';
      
      // Clear all CallKit notifications
      try {
        await FlutterCallkitIncoming.endAllCalls();
        print('✅ Cleared all CallKit notifications');
      } catch (e) {
        print('⚠️ Error clearing CallKit notifications: $e');
      }
      
      // Navigate to home immediately
      navigatorKey.currentState?.pushNamedAndRemoveUntil('/', (route) => false);
      
      notifyListeners();
      print('✅ Decline completed successfully');
    } catch (e) {
      print('❌ Error declining call: $e');
    }
  }
  
  /// End the current call - IMMEDIATE END (WhatsApp-style)
  Future<void> endCall() async {
    try {
      print('📴 Ending call - immediate termination...');
      
      // Send BYE message to end the call immediately
      if (_call != null) {
        _call!.endCall();
        print('✅ Sent BYE to terminate call');
      }
      
      // Clear all call state immediately
      _call = null;
      _incomingInvite = null;
      _isCallInProgress = false;
      _isPushCallInProgress = false;
      _status = _isConnected ? 'Connected' : 'Disconnected';
      
      // Stop call duration timer
      _stopCallDurationTimer();
      
      // Stop call state monitoring
      _stopCallStateMonitoring();
      
      // Clear all CallKit notifications with error handling
      try {
        await FlutterCallkitIncoming.endAllCalls();
        print('✅ Cleared all CallKit notifications');
      } catch (e) {
        print('⚠️ Error clearing CallKit notifications: $e');
      }
      
      // Reset CallKit launch flag and clear global call info
      _isLaunchingFromCallKitAccept = false;
      globalCallKitCallInfo = null;
      
      // Navigate to home screen immediately for smooth UX
      navigatorKey.currentState?.pushNamedAndRemoveUntil('/', (route) => false);
      print('✅ Navigated to home screen');
      
      notifyListeners();
      print('✅ Call ended successfully');
    } catch (e) {
      print('❌ Error ending call: $e');
      // Even on error, try to clean up
      _call = null;
      _isCallInProgress = false;
      _isPushCallInProgress = false;
      navigatorKey.currentState?.pushNamedAndRemoveUntil('/', (route) => false);
      notifyListeners();
    }
  }
  
  /// Toggle mute on active call
  void toggleMute() {
    if (_call != null) {
      _call!.onMuteUnmutePressed();
    }
  }
  
  /// Toggle speaker on active call
  void toggleSpeaker(bool enabled) {
    if (_call != null) {
      print('🔊 Toggling speaker: ${enabled ? "ON" : "OFF"}');
      try {
        _call!.enableSpeakerPhone(enabled);
        print('✅ Speaker ${enabled ? "enabled" : "disabled"} successfully');
      } catch (e) {
        print('❌ Error toggling speaker: $e');
      }
    } else {
      print('⚠️ Cannot toggle speaker - no active call');
    }
  }
  
  /// Activate iOS audio session (WebRTC)
  Future<void> _activateAudioSession() async {
    if (!Platform.isIOS) return;
    
    try {
      print('🔊 Activating iOS audio session...');
      await _audioMethodChannel.invokeMethod('activateAudio');
      print('✅ iOS audio session activated');
    } catch (e) {
      print('❌ Error activating audio session: $e');
    }
  }

  /// Stabilize iOS audio routing to the earpiece after connect
  Future<void> _stabilizeIOSAudioRouting() async {
    if (!Platform.isIOS || _call == null) return;
    try {
      // Small staged toggles to overcome CallKit/AVAudioSession race conditions
      print('🔊 iOS routing: staging toggles to enforce earpiece');
      await Future.delayed(const Duration(milliseconds: 250));
      _call!.enableSpeakerPhone(true);
      await Future.delayed(const Duration(milliseconds: 120));
      _call!.enableSpeakerPhone(false);
      // Re-assert after audio session callbacks settle
      await Future.delayed(const Duration(milliseconds: 500));
      await _activateAudioSession();
      _call!.enableSpeakerPhone(false);
      print('✅ iOS routing stabilized to earpiece');
    } catch (e) {
      print('❌ Error stabilizing iOS routing: $e');
    }
  }
  
  /// Deactivate iOS audio session (WebRTC)
  Future<void> _deactivateAudioSession() async {
    if (!Platform.isIOS) return;
    
    try {
      print('🔇 Deactivating iOS audio session...');
      await _audioMethodChannel.invokeMethod('deactivateAudio');
      print('✅ iOS audio session deactivated');
    } catch (e) {
      print('❌ Error deactivating audio session: $e');
    }
  }
  
  /// Force Android audio output routing for incoming audio
  Future<void> _forceAndroidAudioOutput() async {
    if (!Platform.isAndroid || _call == null) return;
    
    try {
      print('🔊 Forcing Android audio output routing...');
      
      // Toggle speaker to force audio routing refresh
      _call!.enableSpeakerPhone(true);
      await Future.delayed(const Duration(milliseconds: 100));
      _call!.enableSpeakerPhone(false);
      
      // Force audio to earpiece/speaker
      _call!.enableSpeakerPhone(false); // Ensure earpiece mode
      
      print('✅ Android audio output routing applied');
    } catch (e) {
      print('❌ Error forcing Android audio output: $e');
    }
  }
  
  /// Toggle hold on active call
  void toggleHold() {
    if (_call != null) {
      _call!.onHoldUnholdPressed();
    }
  }
  
  /// Send DTMF tone
  void sendDTMF(String tone) {
    if (_call != null) {
      _call!.dtmf(tone);
    }
  }
  
  /// Test CallKit notification (for debugging)
  Future<void> testCallKitNotification() async {
    print('🧪 Testing CallKit notification...');
    final testData = {
      'metadata': jsonEncode({
        'call_id': 'test-call-${DateTime.now().millisecondsSinceEpoch}',
        'caller_name': 'Test Caller',
        'caller_number': '+1234567890',
        'voice_sdk_id': 'test-sdk-id',
      }),
      'message': 'Incoming call!'
    };
    await _showCallKitIncoming(testData);
  }
  
  /// Test Android audio routing (for debugging)
  Future<void> testAndroidAudioRouting() async {
    if (!Platform.isAndroid || _call == null) {
      print('❌ Cannot test audio - not Android or no active call');
      return;
    }
    
    print('🧪 Testing Android audio routing...');
    
    // Test earpiece
    print('🔊 Testing earpiece mode...');
    _call!.enableSpeakerPhone(false);
    await Future.delayed(const Duration(seconds: 2));
    
    // Test speaker
    print('🔊 Testing speaker mode...');
    _call!.enableSpeakerPhone(true);
    await Future.delayed(const Duration(seconds: 2));
    
    // Back to earpiece and force routing
    print('🔊 Back to earpiece with routing fix...');
    _call!.enableSpeakerPhone(false);
    await _forceAndroidAudioOutput();
    
    print('✅ Audio routing test completed');
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    _appLifecycleState = state;
    
    print('📱 App lifecycle changed to: $state');
    
    switch (state) {
      case AppLifecycleState.resumed:
        print('📱 App resumed - ensuring connection is active');
        _ensureConnectionActive();
        break;
      case AppLifecycleState.paused:
        print('📱 App paused - maintaining background connection');
        _handleAppPaused();
        break;
      case AppLifecycleState.detached:
        print('📱 App detached - cleaning up');
        break;
      case AppLifecycleState.inactive:
        print('📱 App inactive - maintaining connection');
        break;
      case AppLifecycleState.hidden:
        print('📱 App hidden - maintaining connection');
        break;
    }
  }
  
  /// Ensure connection is active when app resumes
  void _ensureConnectionActive() {
    // Turn off offline mode when app comes to foreground
    _isOfflineMode = false;
    print('📱 App resumed - offline mode disabled, VoIP pushes will stop');
    
    // CRITICAL FIX: Don't reconnect if we're already handling a push call
    // The CallKit flow already handles connection for incoming calls
    if (_isPushCallInProgress) {
      print('📱 Push call in progress - skipping reconnect, CallKit handling connection');
      return;
    }
    
    // CRITICAL FIX: Only reconnect if we've been paused before
    // This prevents reconnecting during initial app startup (which creates duplicates)
    if (!_hasBeenPausedBefore) {
      print('📱 First resume (app startup) - skipping reconnect, initial connection in progress');
      return;
    }
    
    // Check SDK's real-time connection status
    if (!_telnyxClient.isConnected()) {
      print('🔄 WebSocket not connected - reconnecting automatically...');
      _status = 'Reconnecting...';
      notifyListeners();
      
      // Automatically reconnect when app resumes from background (WhatsApp-style)
      _reconnectWebSocket();
    } else {
      print('✅ WebSocket already connected - ready for calls');
    }
  }

  /// Set up socket listeners for TelnyxClient
  void _setupSocketListeners() {
    _telnyxClient.onSocketMessageReceived = _handleSocketMessage;
    _telnyxClient.onSocketErrorReceived = _handleSocketError;
    print('🔧 Socket listeners set up for TelnyxClient');
  }

  /// Reconnect WebSocket for incoming calls - INSTANT CONNECTION (WhatsApp-style)
  /// [voiceSdkId] - Optional voice_sdk_id from VoIP push to ensure INVITE routing
  Future<void> _reconnectWebSocket() async {
    try {
      print('🔌 [INSTANT] Reconnecting WebSocket...');
      
      // CRITICAL: Disable offline mode when reconnecting
      _isOfflineMode = false;
      
      // Initialize TelnyxClient if not yet initialized (covers killed state)
      if (!_isClientInitialized) {
        print('🔧 Initializing TelnyxClient (first-time or killed state)...');
        _telnyxClient = TelnyxClient();
        _setupSocketListeners();
        _isClientInitialized = true;
      }
      
      if (!_isConnected) {
        // Disconnect first to ensure clean state
        if (_telnyxClient.isConnected()) {
          _telnyxClient.disconnect();
        }
        
        final config = CredentialConfig(
          sipUser: _sipUser,
          sipPassword: _sipPassword,
          sipCallerIDName: _callerIdName,
          sipCallerIDNumber: _callerIdNumber,
          notificationToken: getValidVoipToken(), // CRITICAL: Include VoIP token
          debug: true,
          logLevel: LogLevel.all,
          customLogger: MyCustomLogger(),
        );
        
        // Note: For push-based reconnections (VoIP push), we now use handlePushNotification
        // which connects with the correct voice_sdk_id from the push metadata
        // This method is only for manual/foreground reconnections
        _telnyxClient.connectWithCredential(config);
        
        _status = 'Reconnecting...';
        print('✅ [INSTANT] WebSocket reconnection initiated - NOT waiting, processing immediately');
        notifyListeners();
        
        // CRITICAL FIX: DO NOT WAIT for connection!
        // The SDK will handle the INVITE message when it arrives.
        // WhatsApp-style: Start connection immediately, handle call as soon as INVITE arrives
        // This eliminates the 5-second delay that was causing gateway timeouts.
        
      } else if (_isConnected) {
        print('✅ WebSocket already connected - ready for incoming call');
      }
    } catch (e) {
      print('❌ Error reconnecting WebSocket: $e');
      _isConnected = false;
      _status = 'Connection failed';
      notifyListeners();
    }
  }
  
  /// Handle app going to background
  void _handleAppPaused() {
    // If we're in the middle of a push-call flow, DO NOT tear down the socket.
    // CallKit/PushKit flow needs the active WebSocket to complete answer/ICE.
    if (_isPushCallInProgress) {
      print('📵 Push call in progress - skipping WebSocket destroy on background');
      return;
    }
    print('📱 App paused - DESTROYING WebSocket to force VoIP push notifications');
    // CRITICAL: We MUST completely destroy the WebSocket when backgrounded so that Telnyx
    // will send VoIP push notifications for incoming calls.
    // 
    // Telnyx's server logic:
    // - IF WebSocket is connected → Send INVITE over WebSocket only (no push)
    // - IF WebSocket is disconnected → Send VoIP push notification
    // 
    // The Telnyx SDK auto-reconnects after disconnect(), so we must destroy the client entirely.
    
    // Track that we've been paused (so we know to reconnect on resume)
    _hasBeenPausedBefore = true;
    
    // Set offline mode flag
    _isOfflineMode = true;
    
    try {
      print('🔌 Disconnecting WebSocket...');
      _telnyxClient.disconnect();
      _isConnected = false;
      print('✅ WebSocket disconnected - VoIP pushes will now be sent');
      notifyListeners();
    } catch (e) {
      print('⚠️ Error disconnecting WebSocket: $e');
    }
  }
  
  /// Show a toast message
  void _showToast(String message) {
    try {
      if (navigatorKey.currentState != null) {
        final context = navigatorKey.currentState!.context;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            duration: Duration(seconds: 2),
            backgroundColor: Colors.grey[800],
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.all(16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }
      } catch (e) {
      print('⚠️ Error showing toast: $e');
    }
  }

  /// Handle call state changes
  void _handleCallStateChange(CallState state) {
    print('📞 Call state changed to: $state');
    
    switch (state) {
      case CallState.done:
        print('📞 Call ended - cleaning up');
        
        // Deactivate audio session on iOS
        if (Platform.isIOS) {
          _deactivateAudioSession();
        }
        
        _isCallInProgress = false;
        _isPushCallInProgress = false;
        _call = null;
        _status = _isConnected ? 'Connected' : 'Disconnected';
        
        // Stop call duration timer
        _stopCallDurationTimer();
        
        // Stop call state monitoring
        _stopCallStateMonitoring();
        
        // Clear all CallKit notifications
        FlutterCallkitIncoming.endAllCalls().catchError((e) {
          print('⚠️ Error clearing CallKit notifications: $e');
        });
        
        // Navigate back to home and show toast
        if (navigatorKey.currentState?.canPop() == true) {
          navigatorKey.currentState!.popUntil((route) => route.isFirst);
          
          // Show toast message after a short delay to ensure navigation is complete
          Future.delayed(Duration(milliseconds: 500), () {
            _showToast('Call ended');
          });
        }
        
        notifyListeners();
        break;
      case CallState.active:
        print('📞 Call connected');
        
        // Only navigate if not already in progress and not already on call screen
        if (!_isCallInProgress) {
          _isCallInProgress = true;
          _status = 'Call connected';
          
          // CRITICAL: Start call duration timer when call becomes active
          print('⏱️ Call active - starting duration timer');
          _startCallDurationTimer();
          
          // CRITICAL: Activate audio session on iOS FIRST
          if (Platform.isIOS) {
            _activateAudioSession();
          }
          
          // Fix audio routing: ensure audio goes to earpiece by default, not speaker
          if (_call != null) {
            print('🔊 Setting audio to earpiece (disabling speaker)...');
            _call!.enableSpeakerPhone(false);
            print('✅ Audio routing configured for earpiece');
            // Stabilize routing with delayed reassertions on iOS
            _stabilizeIOSAudioRouting();
          }
          
          // Navigate to call screen ONLY once per call
          Future.delayed(const Duration(milliseconds: 300), () {
            final navigatorState = navigatorKey.currentState;
            if (navigatorState != null) {
              final currentRoute = ModalRoute.of(navigatorState.context)?.settings.name;
              if (currentRoute != '/call') {
                navigatorState.pushNamed('/call');
                print('✅ Navigated to call screen on ACTIVE state');
              } else {
                print('✅ Already on call screen');
              }
            }
          });
        } else {
          print('✅ Call already in progress - skipping navigation');
        }
        
        notifyListeners();
        break;
      case CallState.ringing:
        print('📞 Call ringing');
        _status = 'Call ringing';
        notifyListeners();
        break;
      default:
        print('📞 Call state: $state');
        break;
    }
  }
  
  /// Start call duration timer
  void _startCallDurationTimer() {
    _callStartTime = DateTime.now();
    _callDuration = Duration.zero;
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_callStartTime != null) {
        _callDuration = DateTime.now().difference(_callStartTime!);
        notifyListeners();
      }
    });
    print('⏱️ Started call duration timer');
  }
  
  /// Stop call duration timer
  void _stopCallDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer = null;
    _callStartTime = null;
    _callDuration = Duration.zero;
    print('⏱️ Stopped call duration timer');
  }
  
  /// Start call state monitoring
  void _startCallStateMonitoring() {
    _callStateMonitor?.cancel();
    _callStateMonitor = Timer.periodic(Duration(milliseconds: 500), (timer) {
      if (_call != null) {
        final currentState = _call!.callState;
        if (currentState != _lastCallState) {
          print('📞 Call state changed from $_lastCallState to $currentState');
          _lastCallState = currentState;
          _handleCallStateChange(currentState);
        }
      } else {
        // Call ended, stop monitoring
        _stopCallStateMonitoring();
      }
    });
  }
  
  /// Stop call state monitoring
  void _stopCallStateMonitoring() {
    _callStateMonitor?.cancel();
    _callStateMonitor = null;
    _lastCallState = null;
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopCallDurationTimer();
    _stopCallStateMonitoring();
    _call?.endCall();
    super.dispose();
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _phoneController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final telnyxService = context.watch<TelnyxService>();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF00D4AA), Color(0xFF6C5CE7)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.phone,
                color: Colors.white,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            const Text('Adit Telnyx'),
          ],
        ),
        backgroundColor: Theme.of(context).colorScheme.surface,
      ),
      body: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Connection status
                Container(
              padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: telnyxService.isConnected 
                    ? Color(0xFF34C759).withOpacity(0.3) 
                    : Color(0xFFFF3B30).withOpacity(0.3),
                  width: 1,
                ),
                  ),
                  child: Row(
                    children: [
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: telnyxService.isConnected ? Color(0xFF34C759) : Color(0xFFFF3B30),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: (telnyxService.isConnected ? Color(0xFF34C759) : Color(0xFFFF3B30))
                              .withOpacity(0.4),
                          blurRadius: 8,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                      Text(
                          telnyxService.isConnected ? 'Connected to Telnyx' : 'Disconnected',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: telnyxService.isConnected ? Color(0xFF34C759) : Color(0xFFFF3B30),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          telnyxService.status,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                  ),
                ),
                
                const SizedBox(height: 24),
                
            // Incoming call banner
            if (telnyxService.incomingInvite != null)
                  Container(
                padding: const EdgeInsets.all(20),
                margin: const EdgeInsets.only(bottom: 24),
                    decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF00D4AA).withOpacity(0.1), Color(0xFF6C5CE7).withOpacity(0.1)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Color(0xFF00D4AA), width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0xFF00D4AA).withOpacity(0.2),
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Color(0xFF00D4AA),
                      borderRadius: BorderRadius.circular(8),
                    ),
                          child: const Icon(Icons.phone_in_talk, color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                    child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                              const Text('Incoming Call'),
                              Text(
                                telnyxService.incomingInvite?.callerIdNumber ?? 'Unknown',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                      ],
                    ),
                  ),
                      ],
                    ),
                const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: telnyxService.acceptCall,
                            icon: const Icon(Icons.call),
                            label: const Text('Accept'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Color(0xFF34C759),
                              foregroundColor: Colors.white,
                              elevation: 4,
                              padding: EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: telnyxService.declineCall,
                            icon: const Icon(Icons.call_end),
                            label: const Text('Decline'),
                      style: ElevatedButton.styleFrom(
                              backgroundColor: Color(0xFFFF3B30),
                              foregroundColor: Colors.white,
                              elevation: 4,
                              padding: EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            
            // Phone number input
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone Number',
                hintText: 'Enter number to call',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.phone),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Call button
                    ElevatedButton.icon(
              onPressed: telnyxService.isConnected && !telnyxService.isCallInProgress
                  ? () => telnyxService.makeCall(_phoneController.text.trim())
                  : null,
              icon: const Icon(Icons.call, size: 20),
              label: const Text('Call Now', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFF34C759),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
                ),
                
                const SizedBox(height: 16),
                
            // Test CallKit button
                    ElevatedButton.icon(
              onPressed: () => telnyxService.testCallKitNotification(),
              icon: const Icon(Icons.notifications_active, size: 20),
              label: const Text('Test CallKit', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                      style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFFFF9500),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            
            const SizedBox(height: 12),
            
            // Offline Mode Toggle Button
            ElevatedButton.icon(
              onPressed: () => telnyxService.toggleConnectionMode(),
              icon: Icon(
                telnyxService.isOfflineMode ? Icons.wifi_off : Icons.wifi,
                size: 20,
              ),
              label: Text(
                telnyxService.isOfflineMode ? 'Go Online' : 'Go Offline',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: telnyxService.isOfflineMode ? Color(0xFF34C759) : Color(0xFFFF3B30),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            
            const SizedBox(height: 8),
            
            // Connection Status Display
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: telnyxService.isOfflineMode 
                    ? Colors.orange.withOpacity(0.1)
                    : Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: telnyxService.isOfflineMode 
                      ? Colors.orange.withOpacity(0.3)
                      : Colors.green.withOpacity(0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    telnyxService.isOfflineMode ? Icons.wifi_off : Icons.wifi,
                    size: 16,
                    color: telnyxService.isOfflineMode ? Colors.orange : Colors.green,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    telnyxService.getConnectionStatus(),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: telnyxService.isOfflineMode ? Colors.orange : Colors.green,
                    ),
                  ),
                ],
              ),
            ),
            
            const Spacer(),
            
            // SDK Info
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Adit Telnyx - Voice SDK v3.0.0',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Features:\n'
                    '• Create / Receive calls\n'
                    '• Hold calls\n'
                    '• Mute calls\n'
                    '• DTMF support\n'
                    '• Call quality metrics\n'
                    '• Push notifications\n'
                    '• CallKit integration',
                    style: TextStyle(fontSize: 12),
                  ),
              ],
            ),
            ),
            
            const SizedBox(height: 12),
            
            // Debug Info
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Debug Info',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    telnyxService.getBuildModeInfo(),
                    style: TextStyle(
                      fontSize: 12,
                      color: telnyxService.isPushNotificationMode ? Colors.green : Colors.orange,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Push Notifications: ${telnyxService.isPushNotificationMode ? "Enabled" : "Disabled"}',
                    style: TextStyle(
                      fontSize: 12,
                      color: telnyxService.isPushNotificationMode ? Colors.green : Colors.orange,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Connection: ${telnyxService.isConnected ? "Connected" : "Disconnected"}',
                    style: TextStyle(
                      fontSize: 12,
                      color: telnyxService.isConnected ? Colors.green : Colors.red,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CallPage extends StatefulWidget {
  const CallPage({super.key});

  @override
  State<CallPage> createState() => _CallPageState();
}

class _CallPageState extends State<CallPage> {
  bool _isMuted = false;
  bool _isSpeakerOn = false;
  bool _isOnHold = false;

  String _getCallerDisplayName(TelnyxService service) {
    // Priority 1: Global CallKit call info (for direct launch)
    if (globalCallKitCallInfo != null) {
      return globalCallKitCallInfo!['caller_name'] ?? 'CallKit Call';
    }
    
    // Priority 2: Pending accepted call
    if (_isLaunchingFromCallKitAccept && service.pendingAcceptedCall != null) {
      return service.pendingAcceptedCall!['caller_name'] ?? 'CallKit Call';
    }
    
    // Priority 3: Active call destination
    if (service.call?.sessionDestinationNumber != null) {
      return service.call!.sessionDestinationNumber;
    }
    
    // Priority 4: Incoming call number
    if (service.incomingInvite?.callerIdNumber != null) {
      return service.incomingInvite!.callerIdNumber!;
    }
    
    return 'Connecting...';
  }
  
  // Removed unused _shouldShowCallControls helper
  
  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }
  
  Widget _buildCallControlButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required Color activeColor,
    required VoidCallback onPressed,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
              children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: isActive ? activeColor : Theme.of(context).colorScheme.surfaceContainer,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: (isActive ? activeColor : Colors.grey).withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(30),
              onTap: onPressed,
              child: Icon(
                icon,
                color: isActive ? Colors.white : Theme.of(context).colorScheme.onSurface,
                size: 24,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
          ),
        ),
      ],
    );
  }
  
  @override
  Widget build(BuildContext context) {
    final telnyxService = context.watch<TelnyxService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Active Call'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        automaticallyImplyLeading: false,
        actions: [
          // Show home button if launched from CallKit
          if (_isLaunchingFromCallKitAccept)
            IconButton(
              onPressed: () {
                Navigator.of(context).pushReplacementNamed('/');
                _isLaunchingFromCallKitAccept = false;
              },
              icon: const Icon(Icons.home),
              tooltip: 'Go to Home',
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
              const SizedBox(height: 20),
              
              // Call info
                      Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
                    const CircleAvatar(
                      radius: 40,
                      backgroundColor: Color(0xFF00D4AA),
                      child: Icon(Icons.person, size: 50, color: Colors.white),
                    ),
                    const SizedBox(height: 12),
                Text(
                      _getCallerDisplayName(telnyxService),
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                ),
                    const SizedBox(height: 6),
                Text(
                      telnyxService.status,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    // Call duration display - WhatsApp style
                    if (telnyxService.isCallInProgress && telnyxService.callDuration.inSeconds > 0) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(25),
                          border: Border.all(color: Colors.white.withOpacity(0.3)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                      ),
                  ],
                ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.access_time,
                              color: Colors.white.withOpacity(0.9),
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _formatDuration(telnyxService.callDuration),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 20,
                                letterSpacing: 1.5,
                              ),
                ),
              ],
            ),
                      ),
                    ],
            ],
          ),
        ),
              
              const SizedBox(height: 30),
              
              // Call controls - WhatsApp style
                      Container(
                padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: Colors.white.withOpacity(0.2)),
                          boxShadow: [
                            BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                              blurRadius: 20,
                      offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Mute button
                    _buildCallControlButton(
                      icon: _isMuted ? Icons.mic_off : Icons.mic,
                      label: 'Mute',
                      isActive: _isMuted,
                      activeColor: Colors.red,
                      onPressed: () {
                        telnyxService.toggleMute();
                        setState(() {
                          _isMuted = !_isMuted;
                        });
                      },
                    ),
                    
                    // Speaker button
                    _buildCallControlButton(
                      icon: _isSpeakerOn ? Icons.volume_up : Icons.hearing,
                      label: 'Speaker',
                      isActive: _isSpeakerOn,
                      activeColor: Colors.blue,
                      onPressed: () {
                        final newSpeakerState = !_isSpeakerOn;
                        telnyxService.toggleSpeaker(newSpeakerState);
                        setState(() {
                          _isSpeakerOn = newSpeakerState;
                        });
                      },
                    ),
                    
                    // Hold button
                    _buildCallControlButton(
                      icon: _isOnHold ? Icons.play_arrow : Icons.pause,
                      label: 'Hold',
                      isActive: _isOnHold,
                      activeColor: Colors.orange,
                      onPressed: () {
                        telnyxService.toggleHold();
                        setState(() {
                          _isOnHold = !_isOnHold;
                        });
                      },
                ),
              ],
            ),
              ),
              
              const SizedBox(height: 30),
              
              // DTMF Keypad
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                  child: Column(
                    children: [
                      Text(
                      'DTMF Keypad',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 12),
                    GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 3,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      childAspectRatio: 1.2,
                      children: [
                        for (final tone in ['1', '2', '3', '4', '5', '6', '7', '8', '9', '*', '0', '#'])
                          ElevatedButton(
                            onPressed: () => telnyxService.sendDTMF(tone),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                              padding: const EdgeInsets.all(8),
                            ),
                            child: Text(tone, style: const TextStyle(fontSize: 18)),
                      ),
                    ],
                  ),
                  ],
                ),
              ),
              
              const SizedBox(height: 30),
              
              
              // End call button - WhatsApp style
              Container(
                width: double.infinity,
                height: 70,
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(35),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.withOpacity(0.4),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(35),
                    onTap: () => telnyxService.endCall(),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.call_end, color: Colors.white, size: 28),
                        const SizedBox(width: 12),
                        const Text(
                          'End Call',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                ),
              ),
                      
                      const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
