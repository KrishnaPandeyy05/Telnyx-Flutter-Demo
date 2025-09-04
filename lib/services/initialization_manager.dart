import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:telnyx_webrtc/telnyx_client.dart';
import 'package:telnyx_webrtc/config/telnyx_config.dart';
import 'package:telnyx_webrtc/model/telnyx_message.dart';
import 'package:telnyx_webrtc/model/socket_method.dart';
import 'package:telnyx_webrtc/model/telnyx_socket_error.dart';
import 'package:telnyx_webrtc/utils/logging/log_level.dart';
import 'package:telnyx_webrtc/utils/logging/custom_logger.dart';

import 'call_state_persistence.dart';
import 'navigation_manager.dart';
import 'unified_call_manager.dart';

/// Initialization phases in order
enum InitializationPhase {
  notStarted,
  firebaseInit,
  permissionsRequest,
  navigationSetup,
  callManagerSetup,
  telnyxClientInit,
  webSocketConnecting,
  pendingCallCheck,
  complete,
  failed,
}

/// Manages robust initialization with proper dependency sequencing
class InitializationManager {
  static final InitializationManager _instance = InitializationManager._internal();
  factory InitializationManager() => _instance;
  InitializationManager._internal();
  
  // Dependencies
  late TelnyxClient _telnyxClient;
  final NavigationManager _navigationManager = NavigationManager();
  final UnifiedCallManager _callManager = UnifiedCallManager();
  
  // Initialization state tracking
  InitializationPhase _currentPhase = InitializationPhase.notStarted;
  final List<String> _completedSteps = [];
  final List<String> _failedSteps = [];
  Completer<bool>? _initializationCompleter;
  Timer? _initializationTimeoutTimer;
  
  // Connection state
  bool _isClientReady = false;
  bool _isWebSocketConnected = false;
  String? _fcmToken;
  
  // Callbacks
  Function(TelnyxMessage)? onSocketMessage;
  Function(TelnyxSocketError)? onSocketError;
  
  // Getters
  InitializationPhase get currentPhase => _currentPhase;
  bool get isFullyInitialized => _currentPhase == InitializationPhase.complete;
  bool get isClientReady => _isClientReady;
  bool get isWebSocketConnected => _isWebSocketConnected;
  TelnyxClient get telnyxClient => _telnyxClient;
  List<String> get completedSteps => List.unmodifiable(_completedSteps);
  List<String> get failedSteps => List.unmodifiable(_failedSteps);
  
  /// Initialize all systems with proper dependency management
  Future<bool> initialize({
    required String sipUser,
    required String sipPassword,
    required String callerIdName,
    required String callerIdNumber,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (_initializationCompleter != null) {
      print('⚠️ Initialization already in progress');
      return _initializationCompleter!.future;
    }
    
    _initializationCompleter = Completer<bool>();
    _initializationTimeoutTimer = Timer(timeout, () {
      if (!_initializationCompleter!.isCompleted) {
        print('❌ Initialization timeout after ${timeout.inSeconds}s');
        _completeInitialization(false, 'Initialization timeout');
      }
    });
    
    print('🚀 Starting robust initialization...');
    
    try {
      // Phase 1: Navigation setup (must be first for UI readiness)
      _updatePhase(InitializationPhase.navigationSetup);
      await _initializeNavigation();
      
      // Phase 2: Call manager setup
      _updatePhase(InitializationPhase.callManagerSetup);
      await _initializeCallManager();
      
      // Phase 3: Firebase and FCM token
      _updatePhase(InitializationPhase.firebaseInit);
      await _initializeFirebase();
      
      // Phase 4: Telnyx client initialization
      _updatePhase(InitializationPhase.telnyxClientInit);
      await _initializeTelnyxClient(sipUser, sipPassword, callerIdName, callerIdNumber);
      
      // Phase 5: WebSocket connection
      _updatePhase(InitializationPhase.webSocketConnecting);
      await _connectWebSocket();
      
      // Phase 6: Check for pending calls from killed state
      _updatePhase(InitializationPhase.pendingCallCheck);
      await _checkPendingCalls();
      
      // Phase 7: Complete
      _updatePhase(InitializationPhase.complete);
      _completeInitialization(true, 'Initialization successful');
      return true;
      
    } catch (e) {
      print('❌ Initialization failed: $e');
      _updatePhase(InitializationPhase.failed);
      _completeInitialization(false, e.toString());
      return false;
    }
  }
  
  /// Initialize navigation manager
  Future<void> _initializeNavigation() async {
    try {
      print('🧭 Initializing navigation manager...');
      _navigationManager.initialize();
      _markStepCompleted('navigation_setup');
    } catch (e) {
      _markStepFailed('navigation_setup', e);
      rethrow;
    }
  }
  
  /// Initialize call manager
  Future<void> _initializeCallManager() async {
    try {
      print('📞 Initializing call manager...');
      _callManager.initialize();
      _markStepCompleted('call_manager_setup');
    } catch (e) {
      _markStepFailed('call_manager_setup', e);
      rethrow;
    }
  }
  
  /// Initialize Firebase and get FCM token
  Future<void> _initializeFirebase() async {
    try {
      print('🔥 Getting FCM token...');
      _fcmToken = await FirebaseMessaging.instance.getToken();
      print('🔥 FCM Token obtained: ${_fcmToken?.substring(0, 20)}...');
      _markStepCompleted('firebase_fcm_token');
    } catch (e) {
      print('⚠️ FCM token failed, continuing without: $e');
      _fcmToken = null;
      _markStepCompleted('firebase_fcm_token'); // Mark as completed but without token
      // Don't rethrow - FCM token failure shouldn't block initialization
    }
  }
  
  /// Initialize Telnyx client with credentials
  Future<void> _initializeTelnyxClient(String sipUser, String sipPassword, 
      String callerIdName, String callerIdNumber) async {
    try {
      print('📡 Initializing Telnyx client...');
      
      _telnyxClient = TelnyxClient();
      
      // Set up message handler
      _telnyxClient.onSocketMessageReceived = (TelnyxMessage message) {
        _handleSocketMessage(message);
        onSocketMessage?.call(message);
      };
      
      // Set up error handler
      _telnyxClient.onSocketErrorReceived = (TelnyxSocketError error) {
        _handleSocketError(error);
        onSocketError?.call(error);
      };
      
      // Create config
      final config = CredentialConfig(
        sipUser: sipUser,
        sipPassword: sipPassword,
        sipCallerIDName: callerIdName,
        sipCallerIDNumber: callerIdNumber,
        notificationToken: _fcmToken,
        debug: true,
        logLevel: LogLevel.all,
        customLogger: _CustomLogger(),
      );
      
      _markStepCompleted('telnyx_client_init');
      
      // Connect will be handled in the next phase
      _telnyxClient.connectWithCredential(config);
      print('📡 Telnyx client connection initiated...');
      
    } catch (e) {
      _markStepFailed('telnyx_client_init', e);
      rethrow;
    }
  }
  
  /// Wait for WebSocket connection to be established
  Future<void> _connectWebSocket() async {
    final completer = Completer<void>();
    late Timer timeoutTimer;
    
    // Set up timeout
    timeoutTimer = Timer(const Duration(seconds: 15), () {
      if (!completer.isCompleted) {
        completer.completeError('WebSocket connection timeout');
      }
    });
    
    // Listen for client ready
    late StreamSubscription messageSubscription;
    messageSubscription = Stream.periodic(const Duration(milliseconds: 100))
        .listen((_) {
      if (_isClientReady) {
        timeoutTimer.cancel();
        messageSubscription.cancel();
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
    });
    
    try {
      await completer.future;
      _markStepCompleted('websocket_connection');
    } catch (e) {
      _markStepFailed('websocket_connection', e);
      rethrow;
    }
  }
  
  /// Check for pending calls from killed state
  Future<void> _checkPendingCalls() async {
    try {
      print('📱 Checking for pending calls...');
      
      final pendingCall = await CallStatePersistence.getPendingCall();
      if (pendingCall != null) {
        print('📱 Found pending call: ${pendingCall.callId}');
        await _callManager.handlePushCall(pendingCall);
        
        if (pendingCall.isAccepted) {
          // Process the accepted call
          await _processAcceptedPendingCall(pendingCall);
        }
        
        // Clear the pending call data
        await CallStatePersistence.clearPendingCall();
      }
      
      _markStepCompleted('pending_call_check');
    } catch (e) {
      _markStepFailed('pending_call_check', e);
      // Don't rethrow - pending call issues shouldn't block initialization
    }
  }
  
  /// Process an accepted pending call
  Future<void> _processAcceptedPendingCall(PendingCallData callData) async {
    try {
      print('📱 Processing accepted pending call: ${callData.callId}');
      
      // Wait for client to be ready
      if (!_isClientReady) {
        print('⏳ Waiting for client ready before processing accepted call...');
        await _waitForClientReady(timeout: const Duration(seconds: 10));
      }
      
      // Create push metadata and handle with Telnyx SDK
      final pushMetaData = _createPushMetaData(callData);
      pushMetaData.isAnswer = true;
      
      // Get fresh config
      final config = await _getCurrentConfig();
      
      // Handle push notification
      _telnyxClient.handlePushNotification(pushMetaData, config, null);
      
    } catch (e) {
      print('❌ Error processing accepted pending call: $e');
      // Continue without failing initialization
    }
  }
  
  /// Wait for client ready state
  Future<void> _waitForClientReady({Duration timeout = const Duration(seconds: 10)}) async {
    final completer = Completer<void>();
    late Timer timeoutTimer;
    
    timeoutTimer = Timer(timeout, () {
      if (!completer.isCompleted) {
        completer.completeError('Client ready timeout');
      }
    });
    
    late Timer checkTimer;
    checkTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (_isClientReady) {
        timeoutTimer.cancel();
        checkTimer.cancel();
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
    });
    
    return completer.future;
  }
  
  /// Handle socket messages
  void _handleSocketMessage(TelnyxMessage message) {
    print('📥 Socket message: ${message.socketMethod}');
    
    switch (message.socketMethod) {
      case SocketMethod.clientReady:
        _isClientReady = true;
        _isWebSocketConnected = true;
        print('✅ Client ready - WebSocket connected');
        break;
        
      case SocketMethod.login:
        print('✅ Login successful');
        break;
        
      default:
        // Other messages will be handled by the call manager
        break;
    }
  }
  
  /// Handle socket errors
  void _handleSocketError(TelnyxSocketError error) {
    print('❌ Socket error: ${error.errorMessage}');
    _isWebSocketConnected = false;
    
    // Trigger reconnection after delay
    Timer(const Duration(seconds: 3), () {
      if (!_isWebSocketConnected && isFullyInitialized) {
        print('🔄 Attempting reconnection...');
        _reconnect();
      }
    });
  }
  
  /// Reconnect to Telnyx
  Future<void> _reconnect() async {
    try {
      final config = await _getCurrentConfig();
      _telnyxClient.connectWithCredential(config);
    } catch (e) {
      print('❌ Reconnection failed: $e');
    }
  }
  
  /// Get current Telnyx configuration
  Future<CredentialConfig> _getCurrentConfig() async {
    String? fcmToken;
    try {
      fcmToken = await FirebaseMessaging.instance.getToken();
    } catch (e) {
      print('⚠️ Error getting FCM token for config: $e');
      fcmToken = null;
    }
    
    // These should be passed in or stored - for now using the same values
    return CredentialConfig(
      sipUser: "userkrishnak53562", // Should be passed from outside
      sipPassword: "2*Wfe.*P0lE.", // Should be passed from outside  
      sipCallerIDName: "Telnyx Softphone",
      sipCallerIDNumber: "1001",
      notificationToken: fcmToken,
      debug: true,
      logLevel: LogLevel.all,
      customLogger: _CustomLogger(),
    );
  }
  
  /// Create push metadata from pending call data
  dynamic _createPushMetaData(PendingCallData callData) {
    // This should create the proper PushMetaData object
    // Implementation depends on the Telnyx SDK structure
    return {
      'callerName': callData.callerName,
      'callerNumber': callData.callerNumber,
      'voiceSdkId': callData.voiceSdkId,
      'callId': callData.callId,
    };
  }
  
  /// Update initialization phase
  void _updatePhase(InitializationPhase phase) {
    _currentPhase = phase;
    print('🚀 Initialization phase: ${phase.name}');
  }
  
  /// Mark step as completed
  void _markStepCompleted(String step) {
    _completedSteps.add(step);
    print('✅ Completed: $step');
  }
  
  /// Mark step as failed
  void _markStepFailed(String step, dynamic error) {
    _failedSteps.add(step);
    print('❌ Failed: $step - $error');
  }
  
  /// Complete initialization
  void _completeInitialization(bool success, String message) {
    _initializationTimeoutTimer?.cancel();
    
    if (_initializationCompleter != null && !_initializationCompleter!.isCompleted) {
      if (success) {
        print('✅ $message');
        print('✅ Completed steps: $_completedSteps');
        if (_failedSteps.isNotEmpty) {
          print('⚠️ Failed steps: $_failedSteps');
        }
      } else {
        print('❌ $message');
        print('❌ Failed steps: $_failedSteps');
      }
      
      _initializationCompleter!.complete(success);
      _initializationCompleter = null;
    }
  }
  
  /// Reset initialization state
  void reset() {
    _currentPhase = InitializationPhase.notStarted;
    _completedSteps.clear();
    _failedSteps.clear();
    _isClientReady = false;
    _isWebSocketConnected = false;
    _initializationTimeoutTimer?.cancel();
    _initializationCompleter = null;
  }
}

/// Custom logger for Telnyx
class _CustomLogger extends CustomLogger {
  @override
  log(LogLevel level, String message) {
    print('[$level] $message');
  }
}
