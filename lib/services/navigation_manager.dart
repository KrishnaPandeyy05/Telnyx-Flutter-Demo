import 'dart:async';
import 'package:flutter/material.dart';

// Import the global navigator key
import '../main.dart' show navigatorKey;

/// Manages robust navigation that waits for Flutter readiness
class NavigationManager {
  static final NavigationManager _instance = NavigationManager._internal();
  factory NavigationManager() => _instance;
  NavigationManager._internal();
  
  // Track Flutter readiness
  bool _isFlutterReady = false;
  bool _isNavigatorReady = false;
  final List<_PendingNavigation> _pendingNavigations = [];
  Timer? _readinessCheckTimer;
  
  /// Initialize the navigation manager
  void initialize() {
    print('🧭 NavigationManager initialized');
    _checkFlutterReadiness();
  }
  
  /// Mark Flutter as ready (call this from your app's build method)
  void markFlutterReady() {
    _isFlutterReady = true;
    print('🧭 Flutter marked as ready');
    _checkNavigatorReadiness();
  }
  
  /// Check if navigator is ready and process pending navigations
  void _checkFlutterReadiness() {
    _readinessCheckTimer?.cancel();
    _readinessCheckTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (_isFlutterReady) {
        _checkNavigatorReadiness();
      }
    });
  }
  
  void _checkNavigatorReadiness() {
    if (navigatorKey.currentState != null && 
        navigatorKey.currentContext != null &&
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      
      if (!_isNavigatorReady) {
        _isNavigatorReady = true;
        print('🧭 Navigator ready - processing ${_pendingNavigations.length} pending navigations');
        
        // Process all pending navigations
        _processPendingNavigations();
        
        _readinessCheckTimer?.cancel();
      }
    }
  }
  
  /// Navigate to a route with robust readiness checking
  Future<void> navigateToRoute(String routeName, {
    Map<String, dynamic>? arguments,
    bool replace = false,
    int maxRetries = 10,
    Duration retryDelay = const Duration(milliseconds: 500),
  }) async {
    final pendingNav = _PendingNavigation(
      routeName: routeName,
      arguments: arguments,
      replace: replace,
      maxRetries: maxRetries,
      retryDelay: retryDelay,
      timestamp: DateTime.now(),
    );
    
    print('🧭 Navigation request: $routeName (replace: $replace)');
    
    if (_isNavigatorReady && _canNavigateNow()) {
      await _executeNavigation(pendingNav);
    } else {
      print('🧭 Navigator not ready - queuing navigation: $routeName');
      _pendingNavigations.add(pendingNav);
      
      // Start checking for readiness if not already doing so
      if (_readinessCheckTimer?.isActive != true) {
        _checkFlutterReadiness();
      }
    }
  }
  
  /// Check if we can navigate right now
  bool _canNavigateNow() {
    return navigatorKey.currentState != null &&
           navigatorKey.currentContext != null &&
           WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  }
  
  /// Execute a navigation with retry logic
  Future<void> _executeNavigation(_PendingNavigation nav) async {
    for (int attempt = 1; attempt <= nav.maxRetries; attempt++) {
      try {
        if (!_canNavigateNow()) {
          print('🧭 Navigator not ready for attempt $attempt/${nav.maxRetries}');
          if (attempt < nav.maxRetries) {
            await Future.delayed(nav.retryDelay);
            continue;
          } else {
            throw Exception('Navigator never became ready');
          }
        }
        
        // Execute the navigation
        if (nav.replace) {
          if (navigatorKey.currentState!.canPop()) {
            await navigatorKey.currentState!.pushReplacementNamed(
              nav.routeName,
              arguments: nav.arguments,
            );
          } else {
            await navigatorKey.currentState!.pushNamed(
              nav.routeName,
              arguments: nav.arguments,
            );
          }
        } else {
          await navigatorKey.currentState!.pushNamed(
            nav.routeName,
            arguments: nav.arguments,
          );
        }
        
        print('✅ Navigation successful: ${nav.routeName} (attempt $attempt)');
        return;
        
      } catch (e) {
        print('❌ Navigation attempt $attempt failed: $e');
        
        if (attempt == nav.maxRetries) {
          print('❌ Navigation permanently failed: ${nav.routeName}');
          rethrow;
        } else {
          await Future.delayed(nav.retryDelay);
        }
      }
    }
  }
  
  /// Process all pending navigations
  void _processPendingNavigations() async {
    final navigationsToProcess = List<_PendingNavigation>.from(_pendingNavigations);
    _pendingNavigations.clear();
    
    for (final nav in navigationsToProcess) {
      // Check if navigation is still valid (not too old)
      if (DateTime.now().difference(nav.timestamp) > const Duration(minutes: 2)) {
        print('🧭 Skipping expired navigation: ${nav.routeName}');
        continue;
      }
      
      try {
        await _executeNavigation(nav);
      } catch (e) {
        print('❌ Failed to execute pending navigation ${nav.routeName}: $e');
      }
    }
  }
  
  /// Navigate to call screen specifically
  Future<void> navigateToCall() async {
    await navigateToRoute('/call', replace: true);
  }
  
  /// Navigate to home screen specifically  
  Future<void> navigateToHome() async {
    await navigateToRoute('/', replace: true);
  }
  
  /// Pop current route if possible
  void popRoute() {
    if (_canNavigateNow() && navigatorKey.currentState!.canPop()) {
      navigatorKey.currentState!.pop();
    }
  }
  
  /// Clear all pending navigations
  void clearPendingNavigations() {
    _pendingNavigations.clear();
    print('🧭 Cleared all pending navigations');
  }
  
  /// Reset navigation manager state
  void reset() {
    _isFlutterReady = false;
    _isNavigatorReady = false;
    _pendingNavigations.clear();
    _readinessCheckTimer?.cancel();
    print('🧭 NavigationManager reset');
  }
  
  /// Dispose resources
  void dispose() {
    _readinessCheckTimer?.cancel();
    _pendingNavigations.clear();
  }
}

/// Internal class to track pending navigations
class _PendingNavigation {
  final String routeName;
  final Map<String, dynamic>? arguments;
  final bool replace;
  final int maxRetries;
  final Duration retryDelay;
  final DateTime timestamp;
  
  _PendingNavigation({
    required this.routeName,
    this.arguments,
    required this.replace,
    required this.maxRetries,
    required this.retryDelay,
    required this.timestamp,
  });
}
