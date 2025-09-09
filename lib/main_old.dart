import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/notification_params.dart';
import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:flutter_callkit_incoming/entities/ios_params.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

// Enhanced UI imports
import 'ui/theme/app_theme.dart';

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

// Custom Logger Implementation
class MyCustomLogger extends CustomLogger {
  @override
  log(LogLevel level, String message) {
    print('[$level] $message');
  }
}

// Background message handler for Firebase
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
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
  } else {
    print('❌ Missing call_id or voice_sdk_id - not showing CallKit');
    print('❌ Available data keys: ${data.keys.toList()}');
  }
}

Future<void> _showCallKitIncoming(Map<String, dynamic> data) async {
  print('📱 Showing CallKit for background push: $data');
  
  try {
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
const MethodChannel _methodChannel = MethodChannel('com.example.telnyx_fresh_app/callkit');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  
  await _requestPermissions();
  
  // Set up method channel listener for CallKit intents
  _methodChannel.setMethodCallHandler(_handleNativeMethodCall);
  
  // Check if app was launched from CallKit accept BEFORE building app
  await _detectCallKitLaunchState();
  
  runApp(
    ChangeNotifierProvider(
      create: (_) => TelnyxService(),
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

// Detect if app was launched from CallKit accept using service callback
Future<void> _detectCallKitLaunchState() async {
  try {
    print('🔍 Checking for CallKit launch state...');
    
    // Set up a callback to detect if we get a quick CallKit event
    bool callKitDetected = false;
    
    // Listen for CallKit events briefly to detect launch state
    final subscription = FlutterCallkitIncoming.onEvent.listen((CallEvent? event) {
      if (event?.event == Event.actionCallAccept) {
        print('🚀 IMMEDIATE CallKit Accept detected - app launched from CallKit!');
        _isLaunchingFromCallKitAccept = true;
        callKitDetected = true;
        
        // Extract call info from event
        final extra = event!.body['extra'];
        if (extra is Map && extra['metadata'] != null) {
          try {
            final metadata = jsonDecode(extra['metadata'] as String);
            globalCallKitCallInfo = {
              'call_id': metadata['call_id'] ?? '',
              'caller_name': metadata['caller_name'] ?? 'Unknown',
              'caller_number': metadata['caller_number'] ?? 'Unknown',
              'voice_sdk_id': metadata['voice_sdk_id'] ?? '',
            };
            print('📞 CallKit launch call info: ${globalCallKitCallInfo!["caller_name"]}');
          } catch (e) {
            print('❌ Error parsing CallKit launch metadata: $e');
          }
        }
      }
    });
    
    // Wait briefly to see if we get an immediate CallKit event (killed state launch)
    await Future.delayed(const Duration(milliseconds: 200));
    
    // Cancel the subscription
    subscription.cancel();
    
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
      title: 'Adit Telnyx',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: AppTheme.darkTheme,
      initialRoute: _isLaunchingFromCallKitAccept ? '/call' : '/',
      routes: {
        '/': (_) => const HomePage(),
        '/call': (_) => const CallPage(),
      },
    );
  }
}

class TelnyxService extends ChangeNotifier {
  late TelnyxClient _telnyxClient;
  Call? _call;
  IncomingInviteParams? _incomingInvite;
  bool _isConnected = false;
  bool _isCallInProgress = false;
  String _status = 'Disconnected';
  
  // Track if we're handling a push call
  bool _isPushCallInProgress = false;
  
  // Store pending CallKit accepted call info
  Map<String, dynamic>? _pendingAcceptedCall;
  
  // Getters
  bool get isConnected => _isConnected;
  bool get isCallInProgress => _isCallInProgress;
  String get status => _status;
  Call? get call => _call;
  IncomingInviteParams? get incomingInvite => _incomingInvite;
  Map<String, dynamic>? get pendingAcceptedCall => _pendingAcceptedCall;
  
  TelnyxService() {
    _initialize();
  }
  
  Future<void> _initialize() async {
    print('🚀 Starting TelnyxService initialization...');
    
    try {
      // Set up Firebase messaging
      _setupFirebaseMessaging();
      
      // Set up CallKit listeners
      _setupCallKitListeners();
      
      // Initialize Telnyx client
      String? fcmToken;
      try {
        fcmToken = await FirebaseMessaging.instance.getToken();
        print('📱 FCM Token obtained: ${fcmToken?.substring(0, 20)}...');
      } catch (e) {
        print('❌ Error getting FCM token: $e');
      }
      
      final config = CredentialConfig(
        sipUser: _sipUser,
        sipPassword: _sipPassword,
        sipCallerIDName: _callerIdName,
        sipCallerIDNumber: _callerIdNumber,
        notificationToken: fcmToken,
        debug: true,
        logLevel: LogLevel.all,
        customLogger: MyCustomLogger(),
      );
      
      _telnyxClient = TelnyxClient();
      
      // Set up event listeners
      _telnyxClient.onSocketMessageReceived = _handleSocketMessage;
      _telnyxClient.onSocketErrorReceived = _handleSocketError;
      
      // Connect
      _status = 'Connecting...';
      notifyListeners();
      
      _telnyxClient.connectWithCredential(config);
      
      print('✅ TelnyxService initialization completed');
      
      // Check if there's a pending CallKit accepted call to process
      if (_pendingAcceptedCall != null) {
        print('🔄 Processing pending CallKit accepted call');
        await _processCallKitAccept();
      }
      
      
    } catch (e) {
      print('❌ TelnyxService initialization error: $e');
      _status = 'Error: $e';
      notifyListeners();
    }
  }
  
  // Handle socket messages from Telnyx client
  Future<void> _handleSocketMessage(TelnyxMessage message) async {
    print('📥 Socket message: ${message.socketMethod}');
    
    switch (message.socketMethod) {
      case SocketMethod.clientReady:
        print('✅ Telnyx client ready');
        _isConnected = true;
        _status = 'Connected';
        
        // Process killed state CallKit accept as soon as client is ready
        if (_isLaunchingFromCallKitAccept && globalCallKitCallInfo != null && !_isPushCallInProgress) {
          print('🔄 Processing CallKit launch state immediately after client ready');
          _isPushCallInProgress = true;
          _status = 'Processing CallKit accepted call...';
          notifyListeners();
          
          // Process immediately without delay
          await _processCallKitAcceptFromGlobalState();
        }
        break;
        
      case SocketMethod.gatewayState:
        print('✅ Gateway state updated');
        break;
        
      case SocketMethod.gatewayState:
        print('✅ Gateway state received');
        break;
        
      case SocketMethod.invite:
        // Handle incoming call invitation
        if (message.message is ReceivedMessage) {
          final receivedMessage = message.message as ReceivedMessage;
          if (receivedMessage.inviteParams != null) {
            if (_isPushCallInProgress) {
              // For CallKit accepted calls, update the call object
              print('📞 CallKit call connected - creating call object');
              _incomingInvite = receivedMessage.inviteParams!;
              
              // Fix Android incoming audio routing
              if (Platform.isAndroid) {
                Future.delayed(const Duration(milliseconds: 500), () {
                  _forceAndroidAudioOutput();
                });
              }
              
              // Don't show incoming call UI, just process the connection
              // Navigate to call screen when CallKit call is established
              _navigateToCallScreen();
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
    
    _incomingInvite = inviteParams;
    _status = 'Incoming call from ${inviteParams.callerIdNumber}';
    
    // Navigate to home page to show incoming call banner
    if (navigatorKey.currentState?.canPop() == true) {
      navigatorKey.currentState!.popUntil((route) => route.isFirst);
    }
    
    notifyListeners();
  }
  
  
  void _setupFirebaseMessaging() {
    // Handle foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('📱 Foreground message received: ${message.data}');
      
      final data = message.data;
      
      // Check if this is an incoming call message
      if (data.containsKey('message') && data['message'] == 'Incoming call!') {
        // Show CallKit for foreground messages too
        _showCallKitIncoming(data);
      }
    });
    
    // Handle app opened from notification
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('📱 App opened from push notification: ${message.data}');
    });
  }
  
  void _setupCallKitListeners() {
    FlutterCallkitIncoming.onEvent.listen((CallEvent? event) async {
      if (event == null) return;
      
      print('📱 CallKit event received in TelnyxService: ${event.event}');
      
      switch (event.event) {
        case Event.actionCallAccept:
          // This handles runtime CallKit accept (when app is already running in background)
          print('🚀 Runtime CallKit Accept - navigating to call screen');
          await _handleCallKitAccept(event);
          // Navigate to call screen immediately
          _navigateToCallScreen();
          break;
        case Event.actionCallDecline:
          await _handleCallKitDecline(event);
          break;
        case Event.actionCallEnded:
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
      // Small delay to ensure the app is fully ready for navigation
      Future.delayed(const Duration(milliseconds: 500), () {
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
      // Extract metadata from the event
      final extra = event.body['extra'];
      final extraMap = extra is Map ? Map<String, dynamic>.from(extra) : null;
      
      if (extraMap != null && extraMap['metadata'] != null) {
        final metadataString = extraMap['metadata'] as String;
        final metadata = jsonDecode(metadataString);
        
        final callId = metadata['call_id'] ?? '';
        final callerName = metadata['caller_name'] ?? 'Unknown';
        final callerNumber = metadata['caller_number'] ?? 'Unknown';
        final voiceSdkId = metadata['voice_sdk_id'] ?? '';
        
        print('✅ Accepting call: $callId from $callerName');
        
        // Store call info globally for direct launch (WhatsApp style)
        globalCallKitCallInfo = {
          'call_id': callId,
          'caller_name': callerName,
          'caller_number': callerNumber,
          'voice_sdk_id': voiceSdkId,
        };
        
        // Also store in service for processing
        _pendingAcceptedCall = globalCallKitCallInfo;
        
        // For runtime accepts, just process the call
        _isPushCallInProgress = true;
        _status = 'Accepting call...';
        
        print('🚀 Runtime CallKit Accept: Processing call');
        
        // Process immediately since app is already connected
        await _processCallKitAccept();
        
        notifyListeners();
      }
    } catch (e) {
      print('❌ Error handling CallKit accept: $e');
    }
  }
  
  // Handle CallKit decline event
  Future<void> _handleCallKitDecline(CallEvent event) async {
    print('❌ CallKit Decline pressed');
    
    try {
      // Clear incoming call state
      _incomingInvite = null;
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
      try {
        fcmToken = await FirebaseMessaging.instance.getToken();
      } catch (e) {
        print('❌ Error getting FCM token: $e');
      }
      
      final config = CredentialConfig(
        sipUser: _sipUser,
        sipPassword: _sipPassword,
        sipCallerIDName: _callerIdName,
        sipCallerIDNumber: _callerIdNumber,
        notificationToken: fcmToken,
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
      try {
        fcmToken = await FirebaseMessaging.instance.getToken();
      } catch (e) {
        print('❌ Error getting FCM token: $e');
      }
      
      final config = CredentialConfig(
        sipUser: _sipUser,
        sipPassword: _sipPassword,
        sipCallerIDName: _callerIdName,
        sipCallerIDNumber: _callerIdNumber,
        notificationToken: fcmToken,
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
  
  /// Decline an incoming call
  Future<void> declineCall() async {
    try {
      if (_incomingInvite != null) {
        // Create a call instance to decline it
        final call = Call(
          _telnyxClient.txSocket, 
          _telnyxClient, 
          _telnyxClient.sessid,
          '', // ringtone path
          '', // ringback path
          CallHandler((state) {}, null),
          () {}, // callEnded callback
          false, // debug
        );
        call.callId = _incomingInvite!.callID;
        call.callState = CallState.ringing;
        call.endCall(); // This will reject with USER_BUSY
      }
      
      _incomingInvite = null;
      _status = _isConnected ? 'Connected' : 'Disconnected';
      
      notifyListeners();
    } catch (e) {
      print('❌ Error declining call: $e');
    }
  }
  
  /// End the current call
  Future<void> endCall() async {
    try {
      if (_call != null) {
        _call!.endCall();
      }
      
      _call = null;
      _isCallInProgress = false;
      _isPushCallInProgress = false;
      _status = _isConnected ? 'Connected' : 'Disconnected';
      
      // Reset CallKit launch flag and clear global call info
      if (_isLaunchingFromCallKitAccept) {
        _isLaunchingFromCallKitAccept = false;
        globalCallKitCallInfo = null; // Clear global call info
        // For CallKit calls, navigate to home instead of popping
        navigatorKey.currentState?.pushNamedAndRemoveUntil('/', (route) => false);
      } else {
        // For regular calls, navigate back to home
        if (navigatorKey.currentState?.canPop() == true) {
          navigatorKey.currentState!.popUntil((route) => route.isFirst);
        }
      }
      
      notifyListeners();
    } catch (e) {
      print('❌ Error ending call: $e');
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
      _call!.enableSpeakerPhone(enabled);
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
  void dispose() {
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
  
  bool _shouldShowCallControls(TelnyxService service) {
    // Show controls if we have an active call or we're in a CallKit call
    return service.isCallInProgress || _isLaunchingFromCallKitAccept || service.call != null;
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
                  ],
                ),
              ),
              
              const SizedBox(height: 30),
              
              // Call controls
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Mute button
                  FloatingActionButton(
                    heroTag: "mute",
                    onPressed: () {
                      telnyxService.toggleMute();
                      setState(() {
                        _isMuted = !_isMuted;
                      });
                    },
                    backgroundColor: _isMuted ? Colors.red : Theme.of(context).colorScheme.surfaceContainer,
                    child: Icon(_isMuted ? Icons.mic_off : Icons.mic),
                  ),
                  
                  // Speaker button
                  FloatingActionButton(
                    heroTag: "speaker",
                    onPressed: () {
                      final newSpeakerState = !_isSpeakerOn;
                      telnyxService.toggleSpeaker(newSpeakerState);
                      setState(() {
                        _isSpeakerOn = newSpeakerState;
                      });
                    },
                    backgroundColor: _isSpeakerOn ? Colors.blue : Theme.of(context).colorScheme.surfaceContainer,
                    child: Icon(_isSpeakerOn ? Icons.volume_up : Icons.hearing),
                  ),
                  
                  // Hold button
                  FloatingActionButton(
                    heroTag: "hold",
                    onPressed: () {
                      telnyxService.toggleHold();
                      setState(() {
                        _isOnHold = !_isOnHold;
                      });
                    },
                    backgroundColor: _isOnHold ? Colors.orange : Theme.of(context).colorScheme.surfaceContainer,
                    child: Icon(_isOnHold ? Icons.play_arrow : Icons.pause),
                  ),
                ],
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
              
              // Test audio button (Android only)
              if (Platform.isAndroid)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: FloatingActionButton.extended(
                    heroTag: "testAudio",
                    onPressed: () => telnyxService.testAndroidAudioRouting(),
                    backgroundColor: Colors.orange,
                    icon: const Icon(Icons.hearing, color: Colors.white),
                    label: const Text('Test Audio', style: TextStyle(color: Colors.white)),
                  ),
                ),
              
              // End call button
              FloatingActionButton.extended(
                heroTag: "endCall",
                onPressed: () => telnyxService.endCall(),
                backgroundColor: Colors.red,
                icon: const Icon(Icons.call_end, color: Colors.white),
                label: const Text('End Call', style: TextStyle(color: Colors.white)),
              ),
              
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
