import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_logger.dart';

/// Thrown by [SecureKeyStorage.writeApiKey] when the platform's secure
/// storage can't be written to. Deliberately not caught internally (T123
/// follow-up): storing the key in plaintext SharedPreferences instead
/// would silently downgrade its protection, so callers must surface this
/// to the user rather than have it happen invisibly.
class SecureStorageUnavailableException implements Exception {
  final Object cause;
  SecureStorageUnavailableException(this.cause);
  @override
  String toString() => 'SecureStorageUnavailableException: $cause';
}

/// Secure storage for the Gemini API key (T10).
///
/// The key is kept in the platform's secure storage (Android Keystore /
/// iOS Keychain) via flutter_secure_storage, never in plaintext in
/// SharedPreferences. A one-shot migration from the old SharedPreferences
/// location runs automatically on first access (reading a key saved by a
/// version of the app that predates secure storage — not a new insecure
/// write path).
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
  ///
  /// Throws [SecureStorageUnavailableException] if secure storage can't be
  /// written to — deliberately does NOT fall back to plaintext
  /// SharedPreferences (T123 follow-up: that would silently downgrade the
  /// key's protection). Callers must catch this and tell the user their
  /// key wasn't saved, rather than proceeding as if it had been.
  static Future<void> writeApiKey(String value) async {
    if (value.isEmpty) {
      await clearApiKey();
      return;
    }
    try {
      await _secure.write(key: apiKeyKey, value: value);
    } catch (e) {
      AppLogger.error('Secure storage write failed: $e');
      throw SecureStorageUnavailableException(e);
    }
    // Remove any plaintext trace left by an earlier version
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(apiKeyKey);
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
