import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';

class CredentialStorage {
  static const String _credentialsKey = 'telnyx_credentials';
  static const String _isLoggedInKey = 'is_logged_in';
  
  /// Save SIP credentials securely
  Future<void> saveCredentials({
    required String sipId,
    required String password,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Create credentials map
      final credentials = {
        'sipId': sipId,
        'password': _encryptPassword(password),
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      
      // Save credentials as JSON string
      final credentialsJson = jsonEncode(credentials);
      await prefs.setString(_credentialsKey, credentialsJson);
      await prefs.setBool(_isLoggedInKey, true);
      
      print('✅ Credentials saved successfully');
    } catch (e) {
      print('❌ Error saving credentials: $e');
      rethrow;
    }
  }
  
  /// Retrieve stored credentials
  Future<Map<String, String>?> getCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final credentialsJson = prefs.getString(_credentialsKey);
      
      if (credentialsJson == null) {
        return null;
      }
      
      final credentialsMap = jsonDecode(credentialsJson) as Map<String, dynamic>;
      
      // Decrypt password
      final decryptedPassword = _decryptPassword(credentialsMap['password'] as String);
      
      return {
        'sipId': credentialsMap['sipId'] as String,
        'password': decryptedPassword,
      };
    } catch (e) {
      print('❌ Error retrieving credentials: $e');
      return null;
    }
  }
  
  /// Check if user is logged in
  Future<bool> isLoggedIn() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_isLoggedInKey) ?? false;
    } catch (e) {
      print('❌ Error checking login status: $e');
      return false;
    }
  }
  
  /// Clear stored credentials
  Future<void> clearCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_credentialsKey);
      await prefs.setBool(_isLoggedInKey, false);
      
      print('✅ Credentials cleared');
    } catch (e) {
      print('❌ Error clearing credentials: $e');
      rethrow;
    }
  }
  
  /// Update login status
  Future<void> setLoginStatus(bool isLoggedIn) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_isLoggedInKey, isLoggedIn);
    } catch (e) {
      print('❌ Error updating login status: $e');
      rethrow;
    }
  }
  
  /// Simple encryption for password storage
  /// Note: For production use, consider using flutter_secure_storage
  /// or more robust encryption methods
  String _encryptPassword(String password) {
    // Simple base64 encoding with salt
    const salt = 'telnyx_salt_2024';
    final combined = '$salt:$password';
    final bytes = utf8.encode(combined);
    final encoded = base64.encode(bytes);
    return encoded;
  }
  
  /// Simple decryption for password retrieval
  String _decryptPassword(String encryptedPassword) {
    try {
      final bytes = base64.decode(encryptedPassword);
      final combined = utf8.decode(bytes);
      
      // Remove salt prefix
      const salt = 'telnyx_salt_2024:';
      if (combined.startsWith(salt)) {
        return combined.substring(salt.length);
      }
      
      return combined;
    } catch (e) {
      print('❌ Error decrypting password: $e');
      return '';
    }
  }
  
  /// Get credential expiry status
  Future<bool> areCredentialsExpired({int expiryDays = 30}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final credentialsJson = prefs.getString(_credentialsKey);
      
      if (credentialsJson == null) {
        return true;
      }
      
      final credentialsMap = jsonDecode(credentialsJson) as Map<String, dynamic>;
      final timestamp = credentialsMap['timestamp'] as int?;
      
      if (timestamp == null) {
        return true;
      }
      
      final savedDate = DateTime.fromMillisecondsSinceEpoch(timestamp);
      final expiryDate = savedDate.add(Duration(days: expiryDays));
      
      return DateTime.now().isAfter(expiryDate);
    } catch (e) {
      print('❌ Error checking credential expiry: $e');
      return true;
    }
  }
  
  /// Validate stored credentials format
  Future<bool> validateStoredCredentials() async {
    try {
      final credentials = await getCredentials();
      
      if (credentials == null) {
        return false;
      }
      
      final sipId = credentials['sipId']?.trim();
      final password = credentials['password']?.trim();
      
      // Basic validation
      if (sipId == null || sipId.isEmpty || !sipId.contains('@')) {
        return false;
      }
      
      if (password == null || password.isEmpty || password.length < 6) {
        return false;
      }
      
      return true;
    } catch (e) {
      print('❌ Error validating credentials: $e');
      return false;
    }
  }
}
