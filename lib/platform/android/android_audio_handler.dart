import 'dart:io';
import 'package:telnyx_webrtc/call.dart';

/// Android-specific audio routing handler
class AndroidAudioHandler {
  /// Force Android audio output routing for incoming audio
  /// This fixes the common issue where incoming audio doesn't route properly
  static Future<void> forceAudioOutput(Call? call) async {
    if (!Platform.isAndroid || call == null) return;
    
    try {
      print('🔊 Android: Forcing audio output routing...');
      
      // Toggle speaker to force audio routing refresh
      call.enableSpeakerPhone(true);
      await Future.delayed(const Duration(milliseconds: 100));
      call.enableSpeakerPhone(false);
      
      // Force audio to earpiece mode
      call.enableSpeakerPhone(false);
      
      print('✅ Android: Audio output routing applied');
    } catch (e) {
      print('❌ Android: Error forcing audio output: $e');
    }
  }

  /// Test Android audio routing (for debugging)
  static Future<void> testAudioRouting(Call? call) async {
    if (!Platform.isAndroid || call == null) {
      print('❌ Android: Cannot test audio - no active call');
      return;
    }
    
    print('🧪 Android: Testing audio routing...');
    
    // Test earpiece
    print('🔊 Android: Testing earpiece mode...');
    call.enableSpeakerPhone(false);
    await Future.delayed(const Duration(seconds: 2));
    
    // Test speaker
    print('🔊 Android: Testing speaker mode...');
    call.enableSpeakerPhone(true);
    await Future.delayed(const Duration(seconds: 2));
    
    // Back to earpiece and force routing
    print('🔊 Android: Back to earpiece with routing fix...');
    call.enableSpeakerPhone(false);
    await forceAudioOutput(call);
    
    print('✅ Android: Audio routing test completed');
  }

  /// Apply audio routing fix after call connection (Android-specific)
  static Future<void> applyAudioRoutingFix(Call? call, {int delayMs = 500}) async {
    if (!Platform.isAndroid) return;
    
    Future.delayed(Duration(milliseconds: delayMs), () {
      forceAudioOutput(call);
    });
  }
}



