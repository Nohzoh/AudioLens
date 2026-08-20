import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:audiolens/services/remote_config_service.dart';

void main() {
  group('verifySignature (config.json integrity)', () {
    // Signed with the private half of the keypair whose public half is
    // embedded in RemoteConfigService — the private key itself never
    // appears in this repo (kept offline, see scripts/sign_config.dart).
    const testBody = '{"test":"value"}';
    const validSignature =
        '7HHcsoHFWpmpoamCs8qJHcwiA73nh5ONMEVdqzs+t7uR/TsKYwOD7OJSAPEwEvGXOaPdwg2IcWCyLriy+jAvDw==';

    test('accepts a body matching its real signature', () async {
      final verified = await RemoteConfigService.verifySignature(
          utf8.encode(testBody), validSignature);
      expect(verified, isTrue);
    });

    test('rejects a tampered body against the original signature', () async {
      const tamperedBody = '{"test":"value","gemini_api_url":"https://evil.example.com"}';
      final verified = await RemoteConfigService.verifySignature(
          utf8.encode(tamperedBody), validSignature);
      expect(verified, isFalse);
    });

    test('rejects a malformed/garbage signature', () async {
      final verified = await RemoteConfigService.verifySignature(
          utf8.encode(testBody), 'not-a-real-signature');
      expect(verified, isFalse);
    });

    test('rejects an empty signature', () async {
      final verified =
          await RemoteConfigService.verifySignature(utf8.encode(testBody), '');
      expect(verified, isFalse);
    });
  });


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
