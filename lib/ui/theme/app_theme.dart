import 'package:flutter/material.dart';
import 'dart:ui';

class AppTheme {
  // Primary colors
  static const Color primaryTelnyx = Color(0xFF00D4AA);
  static const Color primaryTelnyxDark = Color(0xFF00B894);
  static const Color secondaryTelnyx = Color(0xFF6C5CE7);
  static const Color backgroundDark = Color(0xFF0A0A0B);
  static const Color surfaceDark = Color(0xFF1C1C1E);
  static const Color cardDark = Color(0xFF2C2C2E);
  
  // Call-specific colors
  static const Color acceptGreen = Color(0xFF34C759);
  static const Color declineRed = Color(0xFFFF3B30);
  static const Color warningOrange = Color(0xFFFF9500);
  static const Color mutedGray = Color(0xFF8E8E93);
  
  // Gradient colors
  static const List<Color> callGradient = [
    Color(0xFF667eea),
    Color(0xFF764ba2),
  ];
  
  static const List<Color> incomingCallGradient = [
    Color(0xFF00D4AA),
    Color(0xFF6C5CE7),
  ];
  
  static const List<Color> activeCallGradient = [
    Color(0xFF34C759),
    Color(0xFF00D4AA),
  ];

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryTelnyx,
        brightness: Brightness.light,
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 2,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        elevation: 4,
        shape: CircleBorder(),
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryTelnyx,
        brightness: Brightness.dark,
        surface: surfaceDark,
        background: backgroundDark,
      ),
      scaffoldBackgroundColor: backgroundDark,
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        elevation: 8,
        color: cardDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 2,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        elevation: 6,
        shape: CircleBorder(),
      ),
    );
  }

  // Custom gradient decorations
  static BoxDecoration get callScreenDecoration => BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: callGradient,
    ),
  );

  static BoxDecoration get incomingCallDecoration => BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: incomingCallGradient,
    ),
  );

  static BoxDecoration get activeCallDecoration => BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: activeCallGradient,
    ),
  );

  // Text styles
  static const TextStyle callNameStyle = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w600,
    color: Colors.white,
  );

  static const TextStyle callStatusStyle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: Colors.white70,
  );

  static const TextStyle callTimerStyle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w500,
    color: Colors.white,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}
