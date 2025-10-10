import 'package:telnyx_webrtc/utils/logging/custom_logger.dart';
import 'package:telnyx_webrtc/utils/logging/log_level.dart';

/// Custom Logger Implementation for Telnyx SDK
class MyCustomLogger extends CustomLogger {
  @override
  void log(LogLevel level, String message) {
    print('📱 Telnyx [$level]: $message');
  }
}


