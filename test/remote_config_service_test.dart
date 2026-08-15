import 'package:flutter_test/flutter_test.dart';
import 'package:audiolens/services/remote_config_service.dart';

void main() {
  group('isAllowedApiUrl (T81)', () {
    test('accepts the real Gemini API host', () {
      expect(
        RemoteConfigService.isAllowedApiUrl(
            'https://generativelanguage.googleapis.com/v1'),
        isTrue,
      );
      expect(
        RemoteConfigService.isAllowedApiUrl(
            'https://generativelanguage.googleapis.com/v1beta'),
        isTrue,
      );
    });

    test('rejects an attacker-controlled host', () {
      expect(
        RemoteConfigService.isAllowedApiUrl('https://evil.example.com/steal'),
        isFalse,
      );
    });

    test('rejects a lookalike host', () {
      expect(
        RemoteConfigService.isAllowedApiUrl(
            'https://generativelanguage.googleapis.com.evil.com/v1'),
        isFalse,
      );
    });

    test('rejects malformed input', () {
      expect(RemoteConfigService.isAllowedApiUrl('not a url'), isFalse);
      expect(RemoteConfigService.isAllowedApiUrl(''), isFalse);
    });
  });
}
