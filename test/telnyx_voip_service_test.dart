import 'package:flutter_test/flutter_test.dart';
import 'package:telnyx_fresh_app/services/telnyx_voip_service.dart';
import 'package:telnyx_common/telnyx_common.dart';

void main() {
  group('TelnyxVoipService Tests', () {
    test('service initialization', () {
      final service = TelnyxVoipService();
      
      // Test initial state
      expect(service.isConnected, false);
      expect(service.currentCalls, isEmpty);
      expect(service.activeCall, isNull);
      expect(service.connectionState, isA<Disconnected>());
    });
    
    test('connection state detection', () {
      final service = TelnyxVoipService();
      
      // Test disconnected state
      expect(service.connectionState is Disconnected, true);
      expect(service.isConnected, false);
    });
  });
}
