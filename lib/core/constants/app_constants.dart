import 'package:flutter/material.dart';

/// SIP Credentials from Telnyx account
class SipCredentials {
  static const String user = "userkrishnak53562";
  static const String password = "2*Wfe.*P0lE.";
  static const String callerIdName = "Telnyx Softphone";
  static const String callerIdNumber = "1001";
}

/// Global app state
class AppGlobals {
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  static bool isLaunchingFromCallKitAccept = false;
  static Map<String, String>? globalCallKitCallInfo;
  static String? globalVoipToken;
}

/// Route names
class AppRoutes {
  static const String home = '/';
  static const String call = '/call';
}



