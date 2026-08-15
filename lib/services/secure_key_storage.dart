import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_logger.dart';

/// Stockage sécurisé de la clé API Gemini (T10).
///
/// La clé est conservée dans le stockage sécurisé de la plateforme
/// (Android Keystore / iOS Keychain) via flutter_secure_storage, jamais en
/// clair dans SharedPreferences. Une migration one-shot depuis l'ancien
/// emplacement SharedPreferences est effectuée automatiquement au premier
/// accès. En cas d'indisponibilité du stockage sécurisé (tests, keystore
/// corrompu), on retombe proprement sur SharedPreferences pour ne jamais
/// casser le flux utilisateur.
class SecureKeyStorage {
  static const String apiKeyKey = 'gemini_api_key';

  static final FlutterSecureStorage _secure = FlutterSecureStorage(
    aOptions: const AndroidOptions(encryptedSharedPreferences: true),
  );

  /// Lit la clé API : d'abord dans le stockage sécurisé, puis (migration
  /// one-shot) dans l'ancien SharedPreferences. Retourne null si absente.
  static Future<String?> readApiKey() async {
    try {
      final secureValue = await _secure.read(key: apiKeyKey);
      if (secureValue != null && secureValue.isNotEmpty) return secureValue;
    } catch (e) {
      AppLogger.error('Secure storage read failed: $e');
    }

    // Migration depuis l'ancien stockage SharedPreferences
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

  /// Écrit la clé API dans le stockage sécurisé. Une valeur vide supprime la
  /// clé (du stockage sécurisé et de l'ancien SharedPreferences).
  static Future<void> writeApiKey(String value) async {
    if (value.isEmpty) {
      await clearApiKey();
      return;
    }
    try {
      await _secure.write(key: apiKeyKey, value: value);
      // Supprimer toute trace en clair laissée par une version antérieure
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(apiKeyKey);
      } catch (_) {}
      return;
    } catch (e) {
      AppLogger.error('Secure storage write failed: $e');
    }
    // Dégradé : stockage sécurisé indisponible
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(apiKeyKey, value);
    } catch (_) {}
  }

  /// Supprime la clé API partout.
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
