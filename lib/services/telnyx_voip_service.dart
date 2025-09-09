import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:telnyx_common/telnyx_common.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

/// Service that wraps TelnyxVoipClient for simplified usage in the app
/// This replaces the previous manual TelnyxService implementation
/// Includes safeguards for known package issues
class TelnyxVoipService extends ChangeNotifier {
  static final TelnyxVoipService _instance = TelnyxVoipService._internal();
  factory TelnyxVoipService() => _instance;
  TelnyxVoipService._internal();

  TelnyxVoipClient? _voipClient;
  
  // Stream subscriptions for cleanup
  final List<StreamSubscription> _subscriptions = [];
  
  // Event deduplication and error handling
  final Set<String> _processedEvents = <String>{};
  Timer? _eventCleanupTimer;
  bool _isDisposing = false;
  
  // Connection state tracking with debouncing
  TelnyxConnectionState? _lastConnectionState;
  Timer? _connectionDebounceTimer;
  
  // Fast initialization flags
  bool _isFastPath = false;
  static SharedPreferences? _sharedPrefs;
  
  // Cache for fast credential retrieval
  static const String _credentialCacheKey = 'telnyx_cached_credentials';
  static CredentialConfig? _cachedCredentials;
  
  // Track active call IDs to manage CallKit notifications
  final Set<String> _trackedCallIds = <String>{};
  
  /// Handle calls update and manage CallKit notifications accordingly
  void _handleCallsUpdate(List<Call> calls) {
    final currentCallIds = calls.map((call) => call.callId).toSet();
    
    // Find calls that ended (were tracked but no longer in the list)
    final endedCallIds = _trackedCallIds.difference(currentCallIds);
    
    // Clean up notifications for ended calls
    for (final callId in endedCallIds) {
      debugPrint('📤 Call ended, clearing notification: $callId');
      unawaited(_clearCallKitNotification(callId));
    }
    
    // Track new calls
    for (final call in calls) {
      if (!_trackedCallIds.contains(call.callId)) {
        debugPrint('📥 New call detected: ${call.callId}');
        _trackedCallIds.add(call.callId);
        
        // Listen to individual call state changes
        _listenToCallStateChanges(call);
      }
    }
    
    // Update tracked calls
    _trackedCallIds.clear();
    _trackedCallIds.addAll(currentCallIds);
  }
  
  /// Listen to individual call state changes for notification management
  void _listenToCallStateChanges(Call call) {
    if (_isDisposing) return;
    
    late final StreamSubscription subscription;
    subscription = call.callState.listen(
      (state) {
        debugPrint('📞 Call ${call.callId} state: $state');
        
        // Clear notification when call ends
        if (state.isTerminated) {
          debugPrint('🗑️ Call ${call.callId} terminated, clearing notification');
          unawaited(_clearCallKitNotification(call.callId));
          subscription.cancel(); // Clean up this listener
        }
      },
      onError: (error) {
        debugPrint('TelnyxVoipService: Call state error for ${call.callId}: $error');
        subscription.cancel();
      },
    );
    
    _subscriptions.add(subscription);
  }
  
  /// Clear a CallKit notification (import CallKitNotificationManager)
  Future<void> _clearCallKitNotification(String callId) async {
    try {
      // Use the Flutter CallKit plugin to end the call notification
      await FlutterCallkitIncoming.endCall(callId);
      debugPrint('✅ Cleared CallKit notification: $callId');
    } catch (e) {
      debugPrint('❌ Error clearing CallKit notification $callId: $e');
    }
  }
  
  // Expose the current state
  TelnyxConnectionState get connectionState => _voipClient?.currentConnectionState ?? const Disconnected();
  List<Call> get currentCalls => _voipClient?.currentCalls ?? [];
  Call? get activeCall => _voipClient?.currentActiveCall;
  String? get pushToken => _voipClient?.currentPushToken;
  bool get isConnected => connectionState is Connected;
  
  // Streams for UI to listen to
  Stream<TelnyxConnectionState>? get connectionStateStream => _voipClient?.connectionState;
  Stream<List<Call>>? get callsStream => _voipClient?.calls;
  Stream<Call?>? get activeCallStream => _voipClient?.activeCall;

  /// Initialize SharedPreferences for fast credential caching
  static Future<void> initializePrefs() async {
    if (_sharedPrefs == null) {
      _sharedPrefs = await SharedPreferences.getInstance();
    }
  }
  
  /// Cache credentials for fast retrieval during killed-state startup
  static Future<void> cacheCredentials(CredentialConfig config) async {
    await initializePrefs();
    _cachedCredentials = config;
    
    // Store serialized version for persistence (optional, for future enhancement)
    final serialized = '${config.sipUser}:${config.sipPassword}:${config.sipCallerIDName}';
    await _sharedPrefs!.setString(_credentialCacheKey, serialized);
    debugPrint('TelnyxVoipService: Credentials cached for fast startup');
  }
  
  /// Get cached credentials for fast initialization
  static Future<CredentialConfig?> getCachedCredentials() async {
    if (_cachedCredentials != null) {
      debugPrint('TelnyxVoipService: Using memory-cached credentials');
      return _cachedCredentials;
    }
    
    await initializePrefs();
    final serialized = _sharedPrefs!.getString(_credentialCacheKey);
    if (serialized != null) {
      final parts = serialized.split(':');
      if (parts.length >= 3) {
        _cachedCredentials = CredentialConfig(
          sipUser: parts[0],
          sipPassword: parts[1],
          sipCallerIDName: parts[2],
          sipCallerIDNumber: parts[0],
          debug: false,
          logLevel: LogLevel.none,
        );
        debugPrint('TelnyxVoipService: Retrieved cached credentials from storage');
        return _cachedCredentials;
      }
    }
    
    return null;
  }

  /// Initialize the service with an external TelnyxVoipClient
  void initializeWithClient(TelnyxVoipClient client, {bool fastPath = false}) {
    if (_voipClient != null) {
      debugPrint('TelnyxVoipService: Already initialized');
      return;
    }

    _isFastPath = fastPath;
    debugPrint('TelnyxVoipService: Initializing with external TelnyxVoipClient${fastPath ? ' (FAST PATH)' : ''}...');
    
    _voipClient = client;

    // Set up stream listeners for state changes
    _setupStreamListeners();
    
    // Only start cleanup timer if not in fast path (defer for performance)
    if (!fastPath) {
      _startEventCleanupTimer();
    }
    
    debugPrint('TelnyxVoipService: Initialization completed');
  }
  
  /// Starts a timer to periodically clean up old processed events
  void _startEventCleanupTimer() {
    _eventCleanupTimer?.cancel();
    _eventCleanupTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (_processedEvents.isNotEmpty) {
        debugPrint('TelnyxVoipService: Cleaning up ${_processedEvents.length} processed events');
        _processedEvents.clear();
      }
    });
  }
  
  /// Initialize the VoIP client with native UI and push handling enabled (for standalone use)
  Future<void> initialize() async {
    if (_voipClient != null) {
      debugPrint('TelnyxVoipService: Already initialized');
      return;
    }

    debugPrint('TelnyxVoipService: Initializing TelnyxVoipClient...');
    
    _voipClient = TelnyxVoipClient(
      enableNativeUI: true,
      enableBackgroundHandling: true,
      isBackgroundClient: false,
    );

    // Set up stream listeners for state changes
    _setupStreamListeners();
    
    // Try to auto-login with stored credentials
    final loginSuccess = await _voipClient!.loginFromStoredConfig();
    if (loginSuccess) {
      debugPrint('TelnyxVoipService: Auto-login initiated with stored config');
    } else {
      debugPrint('TelnyxVoipService: No stored config found, manual login required');
    }
  }

  /// Set up stream listeners for state changes with error handling and debouncing
  void _setupStreamListeners() {
    if (_voipClient == null) return;

    // Listen to connection state changes with debouncing
    _subscriptions.add(
      _voipClient!.connectionState.listen(
        (state) => _handleConnectionStateChange(state),
        onError: (error) {
          debugPrint('TelnyxVoipService: Connection state stream error: $error');
        },
      ),
    );

    // Listen to calls changes with error handling and CallKit notification management
    _subscriptions.add(
      _voipClient!.calls.listen(
        (calls) {
          if (_isDisposing) return;
          try {
            debugPrint('TelnyxVoipService: Calls updated, count: ${calls.length}');
            _handleCallsUpdate(calls);
            notifyListeners();
          } catch (e) {
            debugPrint('TelnyxVoipService: Error handling calls update: $e');
          }
        },
        onError: (error) {
          debugPrint('TelnyxVoipService: Calls stream error: $error');
        },
      ),
    );

    // Listen to active call changes with error handling
    _subscriptions.add(
      _voipClient!.activeCall.listen(
        (activeCall) {
          if (_isDisposing) return;
          try {
            debugPrint('TelnyxVoipService: Active call changed: ${activeCall?.callId ?? 'none'}');
            notifyListeners();
          } catch (e) {
            debugPrint('TelnyxVoipService: Error handling active call change: $e');
          }
        },
        onError: (error) {
          debugPrint('TelnyxVoipService: Active call stream error: $error');
        },
      ),
    );
  }
  
  /// Handle connection state changes with debouncing to prevent rapid state changes
  void _handleConnectionStateChange(TelnyxConnectionState state) {
    if (_isDisposing) return;
    
    // Skip if same state
    if (_lastConnectionState?.runtimeType == state.runtimeType) {
      return;
    }
    
    _connectionDebounceTimer?.cancel();
    _connectionDebounceTimer = Timer(const Duration(milliseconds: 500), () {
      if (_isDisposing) return;
      
      try {
        _lastConnectionState = state;
        debugPrint('TelnyxVoipService: Connection state changed to $state');
        notifyListeners();
      } catch (e) {
        debugPrint('TelnyxVoipService: Error handling connection state change: $e');
      }
    });
  }

  /// Fast login using cached credentials (for killed-state startup)
  Future<bool> loginWithCachedCredentials() async {
    if (_voipClient == null) {
      throw StateError('TelnyxVoipService not initialized. Call initialize() first.');
    }
    
    final cached = await getCachedCredentials();
    if (cached != null) {
      debugPrint('TelnyxVoipService: Fast login with cached credentials...');
      await _voipClient!.login(cached);
      return true;
    }
    
    debugPrint('TelnyxVoipService: No cached credentials available for fast login');
    return false;
  }

  /// Ultra-fast direct login for killed-state scenarios - skips all caching and validation
  Future<void> directUltraFastLogin(CredentialConfig config) async {
    if (_voipClient == null) {
      throw StateError('TelnyxVoipService not initialized. Call initialize() first.');
    }

    debugPrint('TelnyxVoipService: ULTRA-FAST direct login...');
    
    // Skip credential caching for maximum speed
    // Skip all validation and error handling for maximum speed
    await _voipClient!.login(config);
    
    debugPrint('TelnyxVoipService: ULTRA-FAST login call completed');
  }

  /// Login with username and password
  Future<void> loginWithCredentials({
    required String username,
    required String password,
    String? callerName,
  }) async {
    if (_voipClient == null) {
      throw StateError('TelnyxVoipService not initialized. Call initialize() first.');
    }

    debugPrint('TelnyxVoipService: Logging in with credentials...');
    
    final config = CredentialConfig(
      sipUser: username,
      sipPassword: password,
      sipCallerIDName: callerName ?? username,
      sipCallerIDNumber: username, // Required parameter
      debug: false, // Required parameter
      logLevel: LogLevel.none, // Required parameter
    );

    // Cache credentials for future fast startup
    await cacheCredentials(config);
    
    await _voipClient!.login(config);
  }

  /// Login with token
  Future<void> loginWithToken({required String token}) async {
    if (_voipClient == null) {
      throw StateError('TelnyxVoipService not initialized. Call initialize() first.');
    }

    debugPrint('TelnyxVoipService: Logging in with token...');
    
    final config = TokenConfig(
      sipToken: token,
      sipCallerIDName: 'Token User', // Required parameter
      sipCallerIDNumber: 'Token User', // Required parameter
      debug: false, // Required parameter
      logLevel: LogLevel.none, // Required parameter
    );

    await _voipClient!.loginWithToken(config);
  }

  /// Logout and disconnect with error handling
  Future<void> logout() async {
    if (_voipClient == null) return;

    debugPrint('TelnyxVoipService: Logging out...');
    try {
      await _voipClient!.logout();
    } catch (e) {
      debugPrint('TelnyxVoipService: Error during logout (ignoring): $e');
      // Don't rethrow - logout should be best effort
    }
  }

  /// Make an outgoing call
  Future<Call?> makeCall({
    required String destination,
    bool enableCallMetrics = false,
  }) async {
    if (_voipClient == null || !isConnected) {
      debugPrint('TelnyxVoipService: Cannot make call - client not connected');
      return null;
    }

    try {
      debugPrint('TelnyxVoipService: Making call to $destination');
      final call = await _voipClient!.newCall(
        destination: destination,
        debug: enableCallMetrics,
      );
      debugPrint('TelnyxVoipService: Call created with ID: ${call.callId}');
      return call;
    } catch (e) {
      debugPrint('TelnyxVoipService: Error making call: $e');
      return null;
    }
  }

  /// Handle push notification
  Future<void> handlePushNotification(Map<String, dynamic> payload) async {
    if (_voipClient == null) {
      debugPrint('TelnyxVoipService: VoipClient not initialized for push handling');
      return;
    }

    debugPrint('TelnyxVoipService: Handling push notification: ${payload.keys.toList()}');
    await _voipClient!.handlePushNotification(payload);
  }

  /// Refresh push token
  Future<String?> refreshPushToken() async {
    if (_voipClient == null) return null;
    
    debugPrint('TelnyxVoipService: Refreshing push token...');
    return await _voipClient!.refreshPushToken();
  }

  /// Get iOS VoIP push token
  Future<String?> getIOSPushToken() async {
    if (_voipClient == null) return null;
    
    return await _voipClient!.getiOSPushToken();
  }

  /// End all active calls with error handling for concurrent modification issues
  Future<void> endAllCalls() async {
    if (_voipClient == null) return;
    
    debugPrint('TelnyxVoipService: Ending all calls...');
    try {
      await _voipClient!.endAllCalls();
    } catch (e) {
      debugPrint('TelnyxVoipService: Error ending calls (known package issue): $e');
      // This is likely the concurrent modification exception - ignore it
      // The calls will be cleaned up by the package eventually
    }
  }

  /// Disable push notifications
  void disablePushNotifications() {
    if (_voipClient == null) return;
    
    debugPrint('TelnyxVoipService: Disabling push notifications...');
    _voipClient!.disablePushNotifications();
  }

  /// Get session ID
  String? get sessionId => _voipClient?.sessionId;

  /// Dispose and cleanup with proper error handling
  @override
  void dispose() {
    if (_isDisposing) return;
    _isDisposing = true;
    
    debugPrint('TelnyxVoipService: Disposing...');
    
    // Cancel timers first
    _eventCleanupTimer?.cancel();
    _eventCleanupTimer = null;
    
    _connectionDebounceTimer?.cancel();
    _connectionDebounceTimer = null;
    
    // Cancel all stream subscriptions
    for (final subscription in _subscriptions) {
      try {
        subscription.cancel();
      } catch (e) {
        debugPrint('TelnyxVoipService: Error canceling subscription: $e');
      }
    }
    _subscriptions.clear();
    
    // Clear processed events
    _processedEvents.clear();

    // Dispose the VoIP client
    try {
      _voipClient?.dispose();
    } catch (e) {
      debugPrint('TelnyxVoipService: Error disposing VoIP client: $e');
    }
    _voipClient = null;
    
    super.dispose();
  }
}
