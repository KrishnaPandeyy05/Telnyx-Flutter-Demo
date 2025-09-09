import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:telnyx_common/telnyx_common.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter/services.dart';

// Enhanced UI imports
import 'ui/theme/app_theme.dart';
import 'ui/screens/login_screen.dart';
import 'ui/screens/enhanced_call_screen.dart';
import 'services/telnyx_voip_service.dart';
import 'services/credential_storage.dart';

// Global navigator key
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// SIP Credentials from your Telnyx account
const String _sipUser = "userkrishnak53562";
const String _sipPassword = "2*Wfe.*P0lE.";
const String _callerIdName = "Telnyx Softphone";

// Key to detect killed state launch mode
bool _isKilledStateLaunch = false;
bool _isInitializing = false;
String? _launchCallId;

// Cached credential config for fast initialization
CredentialConfig? _cachedConfig;

// CallKit notification cleanup manager
class CallKitNotificationManager {
  static Timer? _cleanupTimer;
  static Set<String> _activeNotifications = <String>{};
  
  /// Add a notification to tracking
  static void trackNotification(String callId) {
    _activeNotifications.add(callId);
    debugPrint('🔔 Tracking CallKit notification: $callId');
  }
  
  /// Remove a notification from tracking and clear it
  static Future<void> clearNotification(String callId) async {
    if (_activeNotifications.contains(callId)) {
      _activeNotifications.remove(callId);
      try {
        await FlutterCallkitIncoming.endCall(callId);
        debugPrint('✅ Cleared CallKit notification: $callId');
      } catch (e) {
        debugPrint('❌ Error clearing CallKit notification $callId: $e');
      }
    }
  }
  
  /// Clear all active notifications
  static Future<void> clearAllNotifications() async {
    debugPrint('🧹 Clearing all ${_activeNotifications.length} CallKit notifications');
    final notifications = Set<String>.from(_activeNotifications);
    _activeNotifications.clear();
    
    for (final callId in notifications) {
      try {
        await FlutterCallkitIncoming.endCall(callId);
      } catch (e) {
        debugPrint('❌ Error clearing notification $callId: $e');
      }
    }
    
    // Also try the nuclear option
    try {
      await FlutterCallkitIncoming.endAllCalls();
      debugPrint('💥 Executed endAllCalls() for cleanup');
    } catch (e) {
      debugPrint('❌ Error in endAllCalls(): $e');
    }
  }
  
  /// Start periodic cleanup of stale notifications
  static void startPeriodicCleanup() {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _checkAndClearStaleNotifications();
    });
  }
  
  static Future<void> _checkAndClearStaleNotifications() async {
    try {
      final activeCalls = await FlutterCallkitIncoming.activeCalls();
      if (activeCalls is List) {
        final currentTime = DateTime.now().millisecondsSinceEpoch;
        final staleCallIds = <String>[];
        
        for (final call in activeCalls) {
          final callId = call['id'] as String?;
          final startTime = call['timeStart'] as int? ?? currentTime;
          
          // Consider calls older than 2 minutes as stale
          if (callId != null && currentTime - startTime > 120000) {
            staleCallIds.add(callId);
          }
        }
        
        if (staleCallIds.isNotEmpty) {
          debugPrint('🧹 Found ${staleCallIds.length} stale notifications, clearing...');
          for (final callId in staleCallIds) {
            await clearNotification(callId);
          }
        }
      }
    } catch (e) {
      debugPrint('❌ Error during stale notification cleanup: $e');
    }
  }
  
  static void dispose() {
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
    _activeNotifications.clear();
  }
}

/// Background message handler for Firebase push notifications
/// This is called when the app is terminated and receives a push notification
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('🔥 KILLED-STATE: Background Firebase message received!');
  debugPrint('🔥 KILLED-STATE: Message data: ${message.data}');
  debugPrint('🔥 KILLED-STATE: Message notification: ${message.notification?.toMap()}');
  debugPrint('🔥 KILLED-STATE: Message from: ${message.from}');
  debugPrint('🔥 KILLED-STATE: Message messageId: ${message.messageId}');
  
  // Initialize Flutter widgets for background handling
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    // Initialize Firebase if needed
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
      debugPrint('🔥 KILLED-STATE: Firebase initialized in background');
    }
    
    // Let Telnyx SDK handle CallKit - we just log the push message
    await _handleTelnyxPushForCallKit(message);
    debugPrint('🔥 KILLED-STATE: Background push handling complete');
  } catch (e) {
    debugPrint('❌ KILLED-STATE: Background push handling failed: $e');
  }
}

/// Handle Telnyx push notification - let Telnyx SDK do the heavy lifting
Future<void> _handleTelnyxPushForCallKit(RemoteMessage message) async {
  // The Telnyx SDK already handles CallKit notifications automatically
  // We just need to ensure the background handler runs so the SDK can process it
  debugPrint('🔥 KILLED-STATE: Telnyx SDK will handle CallKit notification');
  debugPrint('🔥 KILLED-STATE: Message data keys: ${message.data.keys.toList()}');
}

/// Enhanced CallKit launch detection with multiple strategies
Future<bool> _checkForCallKitLaunch() async {
  try {
    debugPrint('🔍 Checking for CallKit launch...');
    
    // Strategy 1: Check for active CallKit calls
    final callData = await FlutterCallkitIncoming.activeCalls();
    if (callData is List && callData.isNotEmpty) {
      debugPrint('📞 Found ${callData.length} active CallKit calls');
      
      // Look for the most recent call
      Map<String, dynamic>? mostRecentCall;
      int mostRecentTime = 0;
      
      for (final call in callData) {
        if (call is Map<String, dynamic>) {
          final timestamp = call['timeStart'] as int? ?? 0;
          if (timestamp > mostRecentTime) {
            mostRecentTime = timestamp;
            mostRecentCall = call;
          }
        }
      }
      
      if (mostRecentCall != null) {
        final callId = mostRecentCall['id'] as String?;
        final currentTime = DateTime.now().millisecondsSinceEpoch;
        
        // ULTRA-AGGRESSIVE: Consider calls within last 5 minutes as potential launches (killed-state can be slow)
        if (callId != null && currentTime - mostRecentTime < 300000) {
          debugPrint('⚡ DETECTED POTENTIAL CALLKIT LAUNCH: $callId (${currentTime - mostRecentTime}ms ago)');
          
          // Check if this is accepted - only launch fast path for accepted calls
          final isAccepted = mostRecentCall['isAccepted'] as bool? ?? false;
          final isBot = mostRecentCall['isBot'] as bool? ?? false;
          
          if (isAccepted && !isBot) {
            debugPrint('⚡⚡ CONFIRMED CALLKIT ACCEPTED LAUNCH: $callId');
            _launchCallId = callId;
            
            // Track this notification for cleanup
            CallKitNotificationManager.trackNotification(callId);
            
            return true;
          } else {
            debugPrint('🕰 CallKit call not accepted yet: $callId (accepted: $isAccepted, bot: $isBot)');
          }
        } else if (callId != null) {
          debugPrint('🕐 Found very old CallKit call: $callId (${currentTime - mostRecentTime}ms ago), cleaning up');
          // Clean up old notifications
          unawaited(CallKitNotificationManager.clearNotification(callId));
        }
      }
    }
    
    // Strategy 2: Check if app was launched with specific intent (already handled by native code)
    // This will be detected by the method channel handler
    
    debugPrint('📱 No recent CallKit launch detected');
    return false;
  } catch (e) {
    debugPrint('❌ Error checking CallKit launch status: $e');
    return false;
  }
}

/// Create the credential config once and cache it
CredentialConfig _getCredentialConfig() {
  if (_cachedConfig != null) return _cachedConfig!;
  
  _cachedConfig = CredentialConfig(
    sipUser: _sipUser,
    sipPassword: _sipPassword,
    sipCallerIDName: _callerIdName,
    sipCallerIDNumber: _sipUser,
    debug: false,
    logLevel: LogLevel.none,
  );
  
  return _cachedConfig!;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // CRITICAL: Register background message handler FIRST for killed-state notifications
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  debugPrint('📱 KILLED-STATE: Background message handler registered');
  
  // Fast-path detection for CallKit killed-state launch
  _isKilledStateLaunch = await _checkForCallKitLaunch();
  _isInitializing = true;
  
  // Create service instances early
  final voipClient = TelnyxVoipClient(
    enableNativeUI: true,
    enableBackgroundHandling: true,
    isBackgroundClient: false,
  );
  
  final voipService = TelnyxVoipService();
  voipService.initializeWithClient(voipClient, fastPath: _isKilledStateLaunch);
  
  // Pre-cache credentials for fast startup (initialize SharedPreferences early)
  await TelnyxVoipService.initializePrefs();
  
  // Start CallKit notification management
  CallKitNotificationManager.startPeriodicCleanup();
  
  // For CallKit-triggered launch, immediately connect to WebSocket before UI setup
  if (_isKilledStateLaunch) {
    debugPrint('⚡ ULTRA-FAST PATH: Connecting IMMEDIATELY for killed-state CallKit launch');
    // Connect synchronously in main thread - highest priority
    await _ultraFastConnectForCallKitLaunch(voipService);
  }

  // Request permissions in parallel but don't wait
  unawaited(_requestPermissions());
  
  // Start the app UI without waiting for Firebase initialization
  runApp(
    ChangeNotifierProvider.value(
      value: voipService,
      child: const TelnyxApp(),
    ),
  );
  
  // Initialize Firebase and TelnyxVoiceApp in the background after UI is shown
  unawaited(_initializeServicesInBackground(voipClient));
}

/// Ultra-fast connection for killed-state CallKit launch - blocks main thread for maximum speed
Future<void> _ultraFastConnectForCallKitLaunch(TelnyxVoipService service) async {
  final stopwatch = Stopwatch()..start();
  try {
    debugPrint('⚡⚡ ULTRA-FAST: Starting killed-state connection at ${DateTime.now()}');
    
    // Skip all cached credential lookup - use direct config for maximum speed
    debugPrint('⚡⚡ ULTRA-FAST: Creating direct credential config (skipping cache lookup)');
    
    final config = CredentialConfig(
      sipUser: _sipUser,
      sipPassword: _sipPassword,
      sipCallerIDName: _callerIdName,
      sipCallerIDNumber: _sipUser,
      debug: false,
      logLevel: LogLevel.none,
    );
    
    // Direct login call - highest priority
    debugPrint('⚡⚡ ULTRA-FAST: Calling login directly');
    await service.directUltraFastLogin(config);
    
    stopwatch.stop();
    debugPrint('⚡⚡ ULTRA-FAST: Connection completed in ${stopwatch.elapsedMilliseconds}ms');
    
  } catch (e) {
    stopwatch.stop();
    debugPrint('❌ ULTRA-FAST: Failed after ${stopwatch.elapsedMilliseconds}ms - Error: $e');
  }
}

/// Original fast connection (kept as fallback)
Future<void> _fastConnectForCallKitLaunch(TelnyxVoipService service) async {
  try {
    // First try cached credentials for fastest possible startup
    debugPrint('⚡ FAST PATH: Attempting login with cached credentials');
    final success = await service.loginWithCachedCredentials();
    
    if (success) {
      debugPrint('⚡ FAST PATH: Login with cached credentials successful!');
    } else {
      // Fallback to creating config (should be rare after first login)
      debugPrint('⚡ FAST PATH: No cached credentials, using fallback config');
      await service.loginWithCredentials(
        username: _sipUser,
        password: _sipPassword,
        callerName: _callerIdName,
      );
    }
  } catch (e) {
    debugPrint('❌ FAST PATH: Error during fast connection: $e');
  }
}

/// Initialize remaining services in the background
Future<void> _initializeServicesInBackground(TelnyxVoipClient voipClient) async {
  try {
    // For killed-state, delay Firebase initialization even more to prioritize WebSocket connection
    if (_isKilledStateLaunch) {
      // Wait longer before Firebase initialization to ensure WebSocket connects first
      await Future.delayed(const Duration(seconds: 3));
      debugPrint('🔄 DELAYED Firebase initialization for killed-state path');
    } else {
      debugPrint('🔄 Background initialization started');
    }
    
    try {
      // Try minimal Firebase initialization
      await TelnyxVoiceApp.initializeAndCreate(
        voipClient: voipClient,
        backgroundMessageHandler: _firebaseMessagingBackgroundHandler,
        child: Container(), // Dummy child since we already called runApp
        onPushNotificationProcessingStarted: () {
          debugPrint('📱 Push notification processing started');
        },
        onPushNotificationProcessingCompleted: () {
          debugPrint('📱 Push notification processing completed');
        },
        onAppLifecycleStateChanged: (state) {
          debugPrint('📱 App lifecycle state changed to: $state');
        },
      );
      
      debugPrint('✅ Background initialization complete');
    } catch (e) {
      // If Firebase fails, continue anyway - the core VoIP functionality should still work
      debugPrint('⚠️ Firebase initialization failed but continuing: $e');
    }
  } catch (e) {
    debugPrint('❌ Error in background initialization: $e');
  } finally {
    _isInitializing = false;
    
    // If this was a killed-state launch, clean up the flags after full initialization
    if (_isKilledStateLaunch) {
      _isKilledStateLaunch = false; // Reset flag after full startup
      debugPrint('⚡ Killed-state initialization fully complete');
    }
  }
}

/// Optimized permission request that only requests critical permissions immediately
/// and defers non-critical ones
Future<void> _requestPermissions() async {
  // Only for Android platform
  if (!Platform.isAndroid) {
    if (Platform.isIOS) {
      await Permission.microphone.request();
    }
    return;
  }
  
  debugPrint('🔐 Requesting Android permissions...');
  
  // For killed-state fast path, skip permission requests entirely - they're already granted
  if (_isKilledStateLaunch) {
    debugPrint('⚡⚡ ULTRA-FAST: Skipping permission requests for killed-state (assuming already granted)');
    
    // Defer ALL permissions for killed-state to maximize startup speed
    unawaited(Future.delayed(const Duration(seconds: 5), () async {
      await Permission.microphone.request();
      await Permission.phone.request();
      await Permission.notification.request();
      await Permission.systemAlertWindow.request();
      debugPrint('✅ Deferred permission requests completed for killed-state');
    }));
    
    return;
  }
  
  // For normal startup, request all permissions
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
    debugPrint('🔐 Permission $permission: $status');
    
    if (status != PermissionStatus.granted) {
      debugPrint('⚠️ Permission $permission not granted - CallKit may not work properly');
    }
  }
  
  debugPrint('✅ Permission requests completed');
}

class TelnyxApp extends StatefulWidget {
  const TelnyxApp({super.key});

  @override
  State<TelnyxApp> createState() => _TelnyxAppState();
}

class _TelnyxAppState extends State<TelnyxApp> with WidgetsBindingObserver {
  bool _isMethodChannelSetup = false;
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // Setup method channel handler for fast native callkit accept events
    _setupMethodChannelHandlers();
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    // If we come to foreground and are in killed-state mode,
    // we need to check if the app is visible to navigate
    if (state == AppLifecycleState.resumed && _isKilledStateLaunch && _launchCallId != null) {
      // Schedule this after the current frame to ensure the UI is ready
      Future.microtask(() {
        _checkAndNavigateToCallScreen(_launchCallId!);
      });
    }
  }
  
  void _setupMethodChannelHandlers() {
    if (_isMethodChannelSetup) return;
    
    // Set up method channel to listen for native CallKit accept events
    const platform = MethodChannel('flutter.native/helper');
    
    platform.setMethodCallHandler((call) async {
      debugPrint('📱 Method channel call: ${call.method}');
      
      if (call.method == 'callkitAcceptLaunched') {
        // This means the app was launched from CallKit accept
        final data = call.arguments as Map<String, dynamic>?;
        if (data != null) {
          final callId = _extractCallIdFromData(data);
          if (callId != null) {
            debugPrint('⚡ METHOD CHANNEL: CallKit accept launch detected for call: $callId');
            _launchCallId = callId;
            _isKilledStateLaunch = true;
            
            // Track the notification
            CallKitNotificationManager.trackNotification(callId);
            
            // Trigger fast connection if not already done
            if (!_isInitializing) {
              final service = Provider.of<TelnyxVoipService>(navigatorKey.currentContext!, listen: false);
              unawaited(_fastConnectForCallKitLaunch(service));
            }
            
            // Navigate to call screen after a short delay
            Future.delayed(const Duration(milliseconds: 500), () {
              _checkAndNavigateToCallScreen(callId);
            });
          }
        }
      }
      
      return null;
    });
    
    _isMethodChannelSetup = true;
  }
  
  /// Extract call ID from method channel data
  String? _extractCallIdFromData(Map<String, dynamic> data) {
    try {
      // Try to find call ID in various possible locations in the data
      if (data['EXTRA_CALLKIT_ID'] != null) {
        return data['EXTRA_CALLKIT_ID'] as String;
      }
      
      if (data['id'] != null) {
        return data['id'] as String;
      }
      
      // Look in nested extra data
      final extra = data['EXTRA_CALLKIT_EXTRA'];
      if (extra is Map<String, dynamic>) {
        final metadata = extra['metadata'];
        if (metadata is String) {
          // Parse JSON metadata
          try {
            final metadataJson = jsonDecode(metadata) as Map<String, dynamic>;
            return metadataJson['call_id'] as String?;
          } catch (e) {
            debugPrint('❌ Error parsing metadata JSON: $e');
          }
        }
      }
      
      debugPrint('⚠️ Could not extract call ID from method channel data');
      return null;
    } catch (e) {
      debugPrint('❌ Error extracting call ID: $e');
      return null;
    }
  }
  
  void _checkAndNavigateToCallScreen(String callId) {
    debugPrint('⚡ Checking navigation for call: $callId');
    if (navigatorKey.currentState != null) {
      debugPrint('⚡ Navigating to call screen for call: $callId');
      navigatorKey.currentState!.pushNamed('/call');
    }
  }
  
  @override
  Widget build(BuildContext context) {
    // Use a minimal theme for fast startup
    final appTheme = _isKilledStateLaunch ? ThemeData.dark() : AppTheme.darkTheme;
    
    return MaterialApp(
      title: 'Telnyx Softphone',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: appTheme,
      initialRoute: '/',
      routes: {
        '/': (_) => const SplashScreen(),
        '/login': (_) => const LoginScreen(),
        '/home': (_) => const HomePage(),
        '/call': (_) => const EnhancedCallScreen(),
        '/old-call': (_) => const CallPage(), // Keep old call page for fallback
      },
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _destinationController = TextEditingController();
  
  @override
  void initState() {
    super.initState();
    
    // Skip auto-login if we're in killed-state mode (already logging in)
    if (!_isKilledStateLaunch) {
      _autoLogin();
    }
    
    // AGGRESSIVE TOKEN REFRESH - Force refresh FCM token on every app start
    // This fixes the "only works once" issue
    _forceTokenRefresh();
  }

  /// Auto login when the home page loads
  Future<void> _autoLogin() async {
    final service = Provider.of<TelnyxVoipService>(context, listen: false);
    
    if (!service.isConnected) {
      debugPrint('🔐 Auto-logging in with credentials...');
      try {
        await service.loginWithCredentials(
          username: _sipUser,
          password: _sipPassword,
          callerName: _callerIdName,
        );
      } catch (e) {
        debugPrint('❌ Auto-login failed: $e');
      }
    }
  }
  
  /// Force refresh FCM token to fix "only works once" issue
  Future<void> _forceTokenRefresh() async {
    try {
      debugPrint('🔄 FORCE REFRESH: Getting fresh FCM token...');
      
      // Delete the old token first
      await FirebaseMessaging.instance.deleteToken();
      debugPrint('🗿 FORCE REFRESH: Old token deleted');
      
      // Wait a bit for the deletion to take effect
      await Future.delayed(const Duration(seconds: 1));
      
      // Get a fresh token
      final newToken = await FirebaseMessaging.instance.getToken();
      debugPrint('🔄 FORCE REFRESH: New FCM token obtained: ${newToken?.substring(0, 20)}...');
      
      if (newToken != null) {
        final service = Provider.of<TelnyxVoipService>(context, listen: false);
        
        // Give the service time to initialize
        await Future.delayed(const Duration(seconds: 2));
        
        // Force refresh the token in the service
        await service.refreshPushToken();
        debugPrint('✅ FORCE REFRESH: Token sent to Telnyx server');
      }
      
    } catch (e) {
      debugPrint('❌ FORCE REFRESH: Token refresh failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Telnyx VoIP Demo'),
        backgroundColor: Colors.blue[900],
      ),
      body: Consumer<TelnyxVoipService>(
        builder: (context, service, child) {
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Connection status
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: service.isConnected ? Colors.green[100] : Colors.red[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        service.isConnected ? Icons.check_circle : Icons.error,
                        color: service.isConnected ? Colors.green : Colors.red,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        service.isConnected ? 'Connected' : 'Disconnected',
                        style: TextStyle(
                          color: service.isConnected ? Colors.green[800] : Colors.red[800],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // Make call section
                TextField(
                  controller: _destinationController,
                  decoration: const InputDecoration(
                    labelText: 'Destination Number',
                    border: OutlineInputBorder(),
                    hintText: 'Enter phone number',
                  ),
                  keyboardType: TextInputType.phone,
                ),
                
                const SizedBox(height: 16),
                
                ElevatedButton.icon(
                  onPressed: service.isConnected ? _makeCall : null,
                  icon: const Icon(Icons.call),
                  label: const Text('Make Call'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    minimumSize: const Size(200, 48),
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // Current calls info
                if (service.currentCalls.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'Active Calls',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        ...service.currentCalls.map((call) => Text(
                          'Call: ${call.callId} - ${call.currentState}',
                        )),
                      ],
                    ),
                  ),
                
                const SizedBox(height: 16),
                
                // Control buttons
                Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton(
                          onPressed: !service.isConnected ? _connect : null,
                          child: const Text('Connect'),
                        ),
                        ElevatedButton(
                          onPressed: service.isConnected ? _disconnect : null,
                          child: const Text('Disconnect'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: _clearCallKitNotifications,
                      icon: const Icon(Icons.clear_all),
                      label: const Text('Clear CallKit'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        minimumSize: const Size(200, 36),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: _checkBatteryOptimization,
                      icon: const Icon(Icons.battery_saver_outlined),
                      label: const Text('Fix Killed-State'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        minimumSize: const Size(200, 36),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: _forceTokenRefresh,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Force Refresh Token'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple,
                        minimumSize: const Size(200, 36),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: _logout,
                      icon: const Icon(Icons.logout),
                      label: const Text('Logout'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey[700],
                        minimumSize: const Size(200, 36),
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 16),
                
                // Debug info
                if (service.pushToken != null)
                  Text(
                    'Push Token: ${service.pushToken!.substring(0, 10)}...',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _makeCall() async {
    final destination = _destinationController.text.trim();
    if (destination.isEmpty) return;
    
    final service = Provider.of<TelnyxVoipService>(context, listen: false);
    debugPrint('📞 Making call to: $destination');
    final call = await service.makeCall(destination: destination);
    
    if (call != null) {
      debugPrint('📞 Call initiated: ${call.callId}');
      debugPrint('📞 Call state: ${call.currentState}');
      
      // Navigate to enhanced call screen immediately
      Navigator.pushNamed(context, '/call');
      
      // Add a small delay then check call state
      Future.delayed(const Duration(seconds: 1), () {
        debugPrint('📞 Call state after 1s: ${call.currentState}');
        debugPrint('📞 Active call in service: ${service.activeCall?.callId}');
        debugPrint('📞 Current calls count: ${service.currentCalls.length}');
      });
    } else {
      debugPrint('❌ Failed to create call');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to make call')),
      );
    }
  }

  Future<void> _connect() async {
    try {
      final credentialStorage = CredentialStorage();
      final credentials = await credentialStorage.getCredentials();
      
      if (credentials != null) {
        final service = Provider.of<TelnyxVoipService>(context, listen: false);
        await service.loginWithCredentials(
          username: credentials['sipId']!,
          password: credentials['password']!,
          callerName: _callerIdName,
        );
      } else {
        // No credentials found, redirect to login
        Navigator.of(context).pushReplacementNamed('/login');
      }
    } catch (e) {
      debugPrint('❌ Error connecting with stored credentials: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connection failed: $e')),
      );
    }
  }

  Future<void> _disconnect() async {
    final service = Provider.of<TelnyxVoipService>(context, listen: false);
    await service.logout();
  }
  
  Future<void> _logout() async {
    try {
      // Disconnect from Telnyx service first
      final service = Provider.of<TelnyxVoipService>(context, listen: false);
      await service.logout();
      
      // Clear stored credentials
      final credentialStorage = CredentialStorage();
      await credentialStorage.clearCredentials();
      
      // Navigate back to login screen
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/login');
      }
    } catch (e) {
      debugPrint('❌ Error during logout: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Logout failed: $e')),
      );
    }
  }
  
  /// Manual CallKit notification cleanup for testing
  Future<void> _clearCallKitNotifications() async {
    debugPrint('🧹 Manual CallKit notification cleanup triggered');
    await CallKitNotificationManager.clearAllNotifications();
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('CallKit notifications cleared'),
        duration: Duration(seconds: 2),
      ),
    );
  }
  
  /// Check and request to disable battery optimization for killed-state notifications
  Future<void> _checkBatteryOptimization() async {
    if (Platform.isAndroid) {
      try {
        // First try to open battery optimization settings directly
        await _requestBatteryOptimizationDisable();
        
        // Show additional guidance
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('CRITICAL: Enable Killed-State Notifications'),
            content: const Text(
              '🚨 YOUR APP IS BEING KILLED BY ANDROID!\n\n'
              'We detected your app process gets killed (signal 9) when backgrounded.\n\n'
              'TO FIX THIS:\n'
              '1. DISABLE battery optimization for this app\n'
              '2. Allow "Display over other apps"\n'
              '3. Set to "Not optimized" in battery settings\n\n'
              'Otherwise push notifications will NEVER work in killed state!'
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await _openBatterySettings();
                },
                child: const Text('Open Settings'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Later'),
              ),
            ],
          ),
        );
      } catch (e) {
        debugPrint('❌ Error checking battery optimization: $e');
      }
    }
  }
  
  Future<void> _requestBatteryOptimizationDisable() async {
    try {
      // Try to open the ignore battery optimization intent
      const intent = 'android.settings.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS';
      await Process.run('adb', [
        'shell', 'am', 'start', '-a', intent,
        '-d', 'package:com.example.telnyx_fresh_app'
      ]);
    } catch (e) {
      debugPrint('❌ Could not open battery optimization settings: $e');
    }
  }
  
  Future<void> _openBatterySettings() async {
    try {
      await Process.run('adb', [
        'shell', 'am', 'start', '-a', 'android.settings.APPLICATION_DETAILS_SETTINGS',
        '-d', 'package:com.example.telnyx_fresh_app'
      ]);
    } catch (e) {
      debugPrint('❌ Could not open app settings: $e');
    }
  }

  @override
  void dispose() {
    _destinationController.dispose();
    super.dispose();
  }
}

class CallPage extends StatefulWidget {
  const CallPage({super.key});

  @override
  State<CallPage> createState() => _CallPageState();
}

class _CallPageState extends State<CallPage> {
  
  /// Hang up call and ensure CallKit notification is cleared
  Future<void> _hangupCall(Call call) async {
    try {
      await call.hangup();
      debugPrint('📞 Hanging up call: ${call.callId}');
      
      // Also clear the CallKit notification
      await CallKitNotificationManager.clearNotification(call.callId);
    } catch (e) {
      debugPrint('❌ Error hanging up call: $e');
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Call Screen'),
        backgroundColor: Colors.red[900],
      ),
      body: Consumer<TelnyxVoipService>(
        builder: (context, service, child) {
          final activeCall = service.activeCall;
          
          if (activeCall == null) {
            return const Center(
              child: Text('No active call'),
            );
          }
          
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Call: ${activeCall.callId}',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Text(
                  'State: ${activeCall.currentState}',
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 32),
                
                // Call control buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    if (activeCall.currentState.canAnswer)
                      FloatingActionButton(
                        onPressed: () => activeCall.answer(),
                        backgroundColor: Colors.green,
                        child: const Icon(Icons.call),
                      ),
                    
                    if (activeCall.currentState.canHangup)
                      FloatingActionButton(
                        onPressed: () => _hangupCall(activeCall),
                        backgroundColor: Colors.red,
                        child: const Icon(Icons.call_end),
                      ),
                  ],
                ),
                
                const SizedBox(height: 32),
                
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Back to Home'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Splash screen that checks login status and routes accordingly
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    
    // Setup animations
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );
    
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
    ));
    
    _scaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
    ));
    
    // Start animation and check login status
    _animationController.forward();
    _checkLoginAndNavigate();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _checkLoginAndNavigate() async {
    try {
      // Wait for minimum splash duration
      await Future.delayed(const Duration(milliseconds: 1500));
      
      final credentialStorage = CredentialStorage();
      final isLoggedIn = await credentialStorage.isLoggedIn();
      final hasValidCredentials = await credentialStorage.validateStoredCredentials();
      
      if (mounted) {
        if (isLoggedIn && hasValidCredentials) {
          // Check if this is a killed-state launch
          if (_isKilledStateLaunch && _launchCallId != null) {
            debugPrint('⚡ Killed-state launch detected, going to call screen');
            Navigator.of(context).pushReplacementNamed('/call');
          } else {
            // Normal launch - go to home
            Navigator.of(context).pushReplacementNamed('/home');
          }
        } else {
          // Not logged in or invalid credentials - go to login
          Navigator.of(context).pushReplacementNamed('/login');
        }
      }
    } catch (e) {
      debugPrint('❌ Error checking login status: $e');
      // On error, default to login screen
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/login');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppTheme.primaryTelnyx,
              AppTheme.primaryTelnyxDark,
              AppTheme.secondaryTelnyx,
            ],
          ),
        ),
        child: Center(
          child: AnimatedBuilder(
            animation: _animationController,
            builder: (context, child) {
              return FadeTransition(
                opacity: _fadeAnimation,
                child: ScaleTransition(
                  scale: _scaleAnimation,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Telnyx Logo
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.phone,
                          color: Colors.white,
                          size: 60,
                        ),
                      ),
                      
                      const SizedBox(height: 32),
                      
                      // App Title
                      Text(
                        'Telnyx',
                        style: AppTheme.callNameStyle.copyWith(
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      
                      const SizedBox(height: 8),
                      
                      Text(
                        'Softphone',
                        style: AppTheme.callStatusStyle.copyWith(
                          fontSize: 18,
                          letterSpacing: 2,
                        ),
                      ),
                      
                      const SizedBox(height: 60),
                      
                      // Loading indicator
                      const SizedBox(
                        width: 30,
                        height: 30,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                      
                      const SizedBox(height: 20),
                      
                      Text(
                        'Initializing...',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
