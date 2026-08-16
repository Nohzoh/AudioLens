import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_logger.dart';

/// Secure storage for the Gemini API key (T10).
///
/// The key is kept in the platform's secure storage (Android Keystore /
/// iOS Keychain) via flutter_secure_storage, never in plaintext in
/// SharedPreferences. A one-shot migration from the old SharedPreferences
/// location runs automatically on first access. If secure storage is
/// unavailable (tests, corrupted keystore), it falls back cleanly to
/// SharedPreferences so the user flow never breaks.
class SecureKeyStorage {
  static const String apiKeyKey = 'gemini_api_key';

  static const FlutterSecureStorage _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  /// Reads the API key: first from secure storage, then (one-shot
  /// migration) from the old SharedPreferences. Returns null if absent.
  static Future<String?> readApiKey() async {
    try {
      final secureValue = await _secure.read(key: apiKeyKey);
      if (secureValue != null && secureValue.isNotEmpty) return secureValue;
    } catch (e) {
      AppLogger.error('Secure storage read failed: $e');
    }

    // Migration from the old SharedPreferences storage
    try {
      final prefs = await SharedPreferences.getInstance();
      final legacy = prefs.getString(apiKeyKey);
      if (legacy != null && legacy.isNotEmpty) {
        try {
          await _secure.write(key: apiKeyKey, value: legacy);
          await prefs.remove(apiKeyKey);
          AppLogger.info('API key migrated to secure storage');
        } catch (e) {
          AppLogger.error('API key migration failed: $e');
        }
        return legacy;
      }
    } catch (_) {}
    return null;
  }

  /// Writes the API key to secure storage. An empty value deletes the key
  /// (from secure storage and from the old SharedPreferences).
  static Future<void> writeApiKey(String value) async {
    if (value.isEmpty) {
      await clearApiKey();
      return;
    }
    try {
      await _secure.write(key: apiKeyKey, value: value);
      // Remove any plaintext trace left by an earlier version
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(apiKeyKey);
      } catch (_) {}
      return;
    } catch (e) {
      AppLogger.error('Secure storage write failed: $e');
    }
    // Degraded fallback: secure storage unavailable
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(apiKeyKey, value);
    } catch (_) {}
  }

  /// Deletes the API key everywhere.
  static Future<void> clearApiKey() async {
    try {
      await _secure.delete(key: apiKeyKey);
    } catch (e) {
      AppLogger.error('Secure storage delete failed: $e');
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(apiKeyKey);
    } catch (_) {}
  }
}
