import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Types of app launches
enum LaunchType {
  normal,
  callKitAccept,
  callKitDecline,
  pushNotification,
}

/// Persisted call data structure
class PendingCallData {
  final String callId;
  final String callerName;
  final String callerNumber;
  final String voiceSdkId;
  final bool isAccepted;
  final DateTime timestamp;
  final LaunchType launchType;
  
  PendingCallData({
    required this.callId,
    required this.callerName,
    required this.callerNumber,
    required this.voiceSdkId,
    required this.isAccepted,
    required this.timestamp,
    required this.launchType,
  });
  
  Map<String, dynamic> toJson() => {
    'callId': callId,
    'callerName': callerName,
    'callerNumber': callerNumber,
    'voiceSdkId': voiceSdkId,
    'isAccepted': isAccepted,
    'timestamp': timestamp.millisecondsSinceEpoch,
    'launchType': launchType.name,
  };
  
  factory PendingCallData.fromJson(Map<String, dynamic> json) => PendingCallData(
    callId: json['callId'] ?? '',
    callerName: json['callerName'] ?? 'Unknown',
    callerNumber: json['callerNumber'] ?? 'Unknown',
    voiceSdkId: json['voiceSdkId'] ?? '',
    isAccepted: json['isAccepted'] ?? false,
    timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] ?? 0),
    launchType: LaunchType.values.firstWhere(
      (e) => e.name == json['launchType'],
      orElse: () => LaunchType.normal,
    ),
  );
  
  /// Check if the pending call data is still valid (not too old)
  bool get isValid {
    final now = DateTime.now();
    final maxAge = const Duration(minutes: 2); // Calls older than 2 minutes are invalid
    return now.difference(timestamp) <= maxAge;
  }
}

/// Manages call state persistence across app kills and cold starts
class CallStatePersistence {
  static const String _pendingCallKey = 'pending_call_data';
  static const String _appLaunchTypeKey = 'app_launch_type';
  
  /// Save pending call data when CallKit action occurs
  static Future<void> savePendingCall(PendingCallData callData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(callData.toJson());
      await prefs.setString(_pendingCallKey, json);
      await prefs.setString(_appLaunchTypeKey, callData.launchType.name);
      print('📱 Saved pending call data: ${callData.callId}');
    } catch (e) {
      print('❌ Error saving pending call data: $e');
    }
  }
  
  /// Get pending call data on app launch
  static Future<PendingCallData?> getPendingCall() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_pendingCallKey);
      
      if (jsonString != null) {
        final json = jsonDecode(jsonString);
        final callData = PendingCallData.fromJson(json);
        
        if (callData.isValid) {
          print('📱 Retrieved valid pending call data: ${callData.callId}');
          return callData;
        } else {
          print('📱 Pending call data expired, clearing...');
          await clearPendingCall();
        }
      }
    } catch (e) {
      print('❌ Error getting pending call data: $e');
      await clearPendingCall(); // Clear corrupted data
    }
    return null;
  }
  
  /// Clear pending call data after processing
  static Future<void> clearPendingCall() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_pendingCallKey);
      await prefs.remove(_appLaunchTypeKey);
      print('📱 Cleared pending call data');
    } catch (e) {
      print('❌ Error clearing pending call data: $e');
    }
  }
  
  /// Get the type of app launch
  static Future<LaunchType> getLaunchType() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final launchTypeString = prefs.getString(_appLaunchTypeKey);
      
      if (launchTypeString != null) {
        return LaunchType.values.firstWhere(
          (e) => e.name == launchTypeString,
          orElse: () => LaunchType.normal,
        );
      }
    } catch (e) {
      print('❌ Error getting launch type: $e');
    }
    return LaunchType.normal;
  }
  
  /// Mark that we've handled the launch
  static Future<void> markLaunchHandled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_appLaunchTypeKey);
    } catch (e) {
      print('❌ Error marking launch handled: $e');
    }
  }
}
