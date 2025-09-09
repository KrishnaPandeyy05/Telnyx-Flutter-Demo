import 'dart:async';
import 'package:flutter/foundation.dart';

/// Service to enhance call reliability by working around known package issues
class CallReliabilityEnhancer {
  static final CallReliabilityEnhancer _instance = CallReliabilityEnhancer._internal();
  factory CallReliabilityEnhancer() => _instance;
  CallReliabilityEnhancer._internal();

  // Track app lifecycle for better background handling
  bool _isInBackground = false;
  bool _hasActiveCalls = false;
  Timer? _backgroundGraceTimer;
  
  // Event tracking to prevent duplicate processing
  final Map<String, DateTime> _recentEvents = {};
  Timer? _eventCleanupTimer;
  
  // Connection stability tracking
  int _consecutiveFailures = 0;
  Timer? _reconnectTimer;
  
  void initialize() {
    debugPrint('CallReliabilityEnhancer: Initializing...');
    
    // Start event cleanup timer
    _eventCleanupTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      _cleanupOldEvents();
    });
  }
  
  /// Check if an event should be processed (deduplication)
  bool shouldProcessEvent(String eventId) {
    final now = DateTime.now();
    final recentEvent = _recentEvents[eventId];
    
    if (recentEvent != null) {
      final timeDiff = now.difference(recentEvent);
      if (timeDiff.inSeconds < 5) { // 5-second deduplication window
        debugPrint('CallReliabilityEnhancer: Skipping duplicate event: $eventId');
        return false;
      }
    }
    
    _recentEvents[eventId] = now;
    return true;
  }
  
  /// Handle app going to background
  void onAppBackground() {
    _isInBackground = true;
    
    if (_hasActiveCalls) {
      debugPrint('CallReliabilityEnhancer: App backgrounded with active calls - preventing disconnection');
      // Give a grace period before allowing disconnection
      _backgroundGraceTimer?.cancel();
      _backgroundGraceTimer = Timer(const Duration(seconds: 10), () {
        debugPrint('CallReliabilityEnhancer: Background grace period expired');
      });
    }
  }
  
  /// Handle app coming to foreground
  void onAppForeground() {
    _isInBackground = false;
    _backgroundGraceTimer?.cancel();
    
    debugPrint('CallReliabilityEnhancer: App foregrounded');
  }
  
  /// Update active call status
  void updateActiveCallStatus(bool hasActiveCalls) {
    final wasChanged = _hasActiveCalls != hasActiveCalls;
    _hasActiveCalls = hasActiveCalls;
    
    if (wasChanged) {
      debugPrint('CallReliabilityEnhancer: Active call status changed to: $hasActiveCalls');
    }
  }
  
  /// Check if disconnection should be prevented
  bool shouldPreventDisconnection() {
    if (_hasActiveCalls) {
      debugPrint('CallReliabilityEnhancer: Preventing disconnection - has active calls');
      return true;
    }
    
    if (_backgroundGraceTimer?.isActive == true) {
      debugPrint('CallReliabilityEnhancer: Preventing disconnection - in grace period');
      return true;
    }
    
    return false;
  }
  
  /// Handle connection failure
  void onConnectionFailure() {
    _consecutiveFailures++;
    debugPrint('CallReliabilityEnhancer: Connection failure #$_consecutiveFailures');
    
    if (_consecutiveFailures >= 3) {
      // Reset failure count after multiple failures
      debugPrint('CallReliabilityEnhancer: Multiple failures detected - implementing backoff');
      _consecutiveFailures = 0;
      
      // Implement exponential backoff for reconnection
      final backoffDelay = Duration(seconds: 2 << (_consecutiveFailures.clamp(0, 4)));
      debugPrint('CallReliabilityEnhancer: Waiting ${backoffDelay.inSeconds}s before next attempt');
    }
  }
  
  /// Handle successful connection
  void onConnectionSuccess() {
    if (_consecutiveFailures > 0) {
      debugPrint('CallReliabilityEnhancer: Connection recovered after $_consecutiveFailures failures');
      _consecutiveFailures = 0;
    }
  }
  
  /// Clean up old events to prevent memory leaks
  void _cleanupOldEvents() {
    final now = DateTime.now();
    final oldEvents = <String>[];
    
    _recentEvents.forEach((eventId, timestamp) {
      if (now.difference(timestamp).inMinutes > 5) {
        oldEvents.add(eventId);
      }
    });
    
    for (final eventId in oldEvents) {
      _recentEvents.remove(eventId);
    }
    
    if (oldEvents.isNotEmpty) {
      debugPrint('CallReliabilityEnhancer: Cleaned up ${oldEvents.length} old events');
    }
  }
  
  /// Get recommendations for app configuration
  Map<String, dynamic> getOptimizedConfig() {
    return {
      'background_disconnect_delay': const Duration(seconds: 30),
      'push_handling_timeout': const Duration(seconds: 15),
      'connection_retry_delay': const Duration(seconds: 5),
      'event_deduplication_window': const Duration(seconds: 5),
    };
  }
  
  void dispose() {
    debugPrint('CallReliabilityEnhancer: Disposing...');
    
    _eventCleanupTimer?.cancel();
    _backgroundGraceTimer?.cancel();
    _reconnectTimer?.cancel();
    
    _recentEvents.clear();
  }
}
