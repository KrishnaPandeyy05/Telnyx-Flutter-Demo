import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:telnyx_webrtc/call.dart';
import 'package:telnyx_webrtc/model/call_state.dart';
import 'package:telnyx_webrtc/model/verto/receive/received_message_body.dart';

import 'call_state_persistence.dart';
import 'navigation_manager.dart';

/// Types of call origins
enum CallOrigin {
  none,
  outgoing,           // User initiated outgoing call
  incomingRegular,    // Regular incoming call (app active)
  incomingPush,       // Push notification incoming call
  pushAccepted,       // CallKit accepted call
}

/// Call phases in order
enum CallPhase {
  idle,          // No call activity
  incoming,      // Incoming call waiting for user decision
  connecting,    // Call being established
  ringing,       // Outgoing call ringing
  active,        // Call is active
  held,          // Call is on hold
  ending,        // Call is ending
}

/// Unified call state manager that handles all call types consistently
class UnifiedCallManager extends ChangeNotifier {
  static final UnifiedCallManager _instance = UnifiedCallManager._internal();
  factory UnifiedCallManager() => _instance;
  UnifiedCallManager._internal();
  
  // Call state
  Call? _activeCall;
  IncomingInviteParams? _incomingInvite;
  CallOrigin _callOrigin = CallOrigin.none;
  CallPhase _currentPhase = CallPhase.idle;
  String _status = 'Ready';
  
  // Navigation manager instance
  final NavigationManager _navigationManager = NavigationManager();
  
  // Getters
  Call? get activeCall => _activeCall;
  IncomingInviteParams? get incomingInvite => _incomingInvite;
  CallOrigin get callOrigin => _callOrigin;
  CallPhase get currentPhase => _currentPhase;
  String get status => _status;
  bool get isCallActive => _currentPhase == CallPhase.active;
  bool get hasIncomingCall => _currentPhase == CallPhase.incoming;
  
  /// Initialize the call manager
  void initialize() {
    print('📞 UnifiedCallManager initialized');
  }
  
  /// Start an outgoing call
  Future<void> startOutgoingCall(Call call, String destination) async {
    print('📞 Starting outgoing call to: $destination');
    
    _reset();
    _activeCall = call;
    _callOrigin = CallOrigin.outgoing;
    _updatePhase(CallPhase.connecting);
    _status = 'Calling $destination...';
    
    _setupCallListeners(call);
    notifyListeners();
  }
  
  /// Handle regular incoming call (when app is active)
  void handleIncomingCall(IncomingInviteParams invite) {
    print('📞 Handling regular incoming call from: ${invite.callerIdNumber}');
    
    _reset();
    _incomingInvite = invite;
    _callOrigin = CallOrigin.incomingRegular;
    _updatePhase(CallPhase.incoming);
    _status = 'Incoming call from ${invite.callerIdNumber ?? "Unknown"}';
    
    notifyListeners();
  }
  
  /// Handle push notification call (when app was backgrounded/killed)
  Future<void> handlePushCall(PendingCallData callData) async {
    print('📞 Handling push call: ${callData.callId} (accepted: ${callData.isAccepted})');
    
    _reset();
    _callOrigin = callData.isAccepted ? CallOrigin.pushAccepted : CallOrigin.incomingPush;
    
    if (callData.isAccepted) {
      _updatePhase(CallPhase.connecting);
      _status = 'Connecting push call...';
    } else {
      _updatePhase(CallPhase.incoming);
      _status = 'Incoming call from ${callData.callerNumber}';
    }
    
    notifyListeners();
  }
  
  /// Accept an incoming call
  Future<void> acceptCall(Call call) async {
    print('✅ Accepting call');
    
    if (_currentPhase != CallPhase.incoming) {
      print('❌ Cannot accept call - not in incoming phase');
      return;
    }
    
    _activeCall = call;
    _updatePhase(CallPhase.connecting);
    _status = 'Connecting...';
    
    _setupCallListeners(call);
    notifyListeners();
  }
  
  /// Decline an incoming call
  Future<void> declineCall() async {
    print('❌ Declining call');
    
    if (_currentPhase != CallPhase.incoming) {
      print('❌ Cannot decline call - not in incoming phase');
      return;
    }
    
    await _endCall();
  }
  
  /// End active call
  Future<void> endCall() async {
    print('📴 Ending call');
    await _endCall();
  }
  
  /// Internal method to end call and cleanup
  Future<void> _endCall() async {
    _updatePhase(CallPhase.ending);
    
    if (_activeCall != null) {
      try {
        _activeCall!.endCall();
      } catch (e) {
        print('❌ Error ending call: $e');
      }
    }
    
    // Navigate back to home
    await _navigationManager.navigateToHome();
    
    _reset();
    notifyListeners();
  }
  
  /// Setup call state listeners for a call object
  void _setupCallListeners(Call call) {
    call.callHandler.onCallStateChanged = (CallState callState) {
      print('📞 Call state changed to: $callState');
      _handleCallStateChange(callState);
    };
  }
  
  /// Handle call state changes from the SDK
  void _handleCallStateChange(CallState callState) {
    switch (callState) {
      case CallState.connecting:
        _updatePhase(CallPhase.connecting);
        _status = 'Connecting...';
        break;
        
      case CallState.ringing:
        if (_callOrigin == CallOrigin.outgoing) {
          _updatePhase(CallPhase.ringing);
          _status = 'Ringing...';
        }
        break;
        
      case CallState.active:
        _updatePhase(CallPhase.active);
        _status = 'Call active';
        
        // Navigate to call screen when call becomes active
        _navigationManager.navigateToCall();
        break;
        
      case CallState.held:
        if (_currentPhase == CallPhase.active) {
          _updatePhase(CallPhase.held);
          _status = _callOrigin == CallOrigin.incomingRegular 
              ? 'Incoming call (tap Accept or Decline)'
              : 'Call on hold';
        }
        break;
        
      case CallState.done:
        print('📞 Call ended - cleaning up');
        _reset();
        _navigationManager.navigateToHome();
        break;
        
      default:
        print('📞 Unhandled call state: $callState');
    }
    
    notifyListeners();
  }
  
  /// Update the current phase and log transition
  void _updatePhase(CallPhase newPhase) {
    if (_currentPhase != newPhase) {
      print('📞 Phase transition: ${_currentPhase.name} → ${newPhase.name}');
      _currentPhase = newPhase;
    }
  }
  
  /// Reset call state
  void _reset() {
    _activeCall = null;
    _incomingInvite = null;
    _callOrigin = CallOrigin.none;
    _currentPhase = CallPhase.idle;
    _status = 'Ready';
  }
  
  /// Toggle mute
  void toggleMute() {
    if (_activeCall == null) return;
    
    try {
      _activeCall!.onMuteUnmutePressed();
      print('🔇 Toggled mute');
    } catch (e) {
      print('❌ Error toggling mute: $e');
    }
  }
  
  /// Toggle speaker
  void toggleSpeaker(bool enabled) {
    if (_activeCall == null) return;
    
    try {
      _activeCall!.enableSpeakerPhone(enabled);
      print('🔊 Speaker ${enabled ? 'enabled' : 'disabled'}');
    } catch (e) {
      print('❌ Error toggling speaker: $e');
    }
  }
  
  /// Toggle hold
  void toggleHold() {
    if (_activeCall == null) return;
    
    try {
      _activeCall!.onHoldUnholdPressed();
      print('⏸️ Toggled hold');
    } catch (e) {
      print('❌ Error toggling hold: $e');
    }
  }
  
  /// Send DTMF tone
  void sendDTMF(String tone) {
    if (_activeCall == null) return;
    
    try {
      _activeCall!.dtmf(tone);
      print('📞 Sent DTMF: $tone');
    } catch (e) {
      print('❌ Error sending DTMF: $e');
    }
  }
  
  /// Get call display number
  String get callDisplayNumber {
    if (_activeCall != null) {
      return _activeCall!.sessionDestinationNumber ?? 'Unknown';
    }
    if (_incomingInvite != null) {
      return _incomingInvite!.callerIdNumber ?? 'Unknown';
    }
    return 'Unknown';
  }
  
  /// Get call display name
  String get callDisplayName {
    if (_incomingInvite != null) {
      return _incomingInvite!.callerIdName ?? _incomingInvite!.callerIdNumber ?? 'Unknown';
    }
    if (_activeCall != null) {
      return _activeCall!.sessionDestinationNumber ?? 'Unknown';
    }
    return 'Unknown';
  }
  
  /// Dispose resources
  void dispose() {
    _reset();
    super.dispose();
  }
}
