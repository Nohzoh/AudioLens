import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audiolens/services/remote_config_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Same signed fixture used by the verifySignature group below — a real
  // signature for this exact body, produced by the actual (offline)
  // private key.
  const validBody = '{"test":"value"}';
  const validSignature =
      '7HHcsoHFWpmpoamCs8qJHcwiA73nh5ONMEVdqzs+t7uR/TsKYwOD7OJSAPEwEvGXOaPdwg2IcWCyLriy+jAvDw==';

  http.Client workingClient() => MockClient((request) async {
        if (request.url.path.endsWith('.sig')) {
          return http.Response(validSignature, 200);
        }
        return http.Response(validBody, 200);
      });

  http.Client failingClient() =>
      MockClient((request) async => http.Response('', 500));

  // #135 — load() previously wrote a cache on every successful fetch but
  // never read it back on failure, making the cache pure dead weight.
  // Declared first: the only test here that cares about
  // RemoteConfigService's static state *not* already having been set by
  // an earlier successful load in this same test isolate (later tests
  // are self-contained — each does its own populate-then-assert within
  // itself — but this one specifically wants a clean slate).
  test('load() falls back to hardcoded defaults with no cache and a failing network',
      () async {
    SharedPreferences.setMockInitialValues({});

    await RemoteConfigService.load(client: failingClient());

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('remote_config_cache'), isNull);
  });

  test('load() caches the verified config body/signature/timestamp on a successful fetch',
      () async {
    SharedPreferences.setMockInitialValues({});

    await RemoteConfigService.load(client: workingClient());

    expect(RemoteConfigService.loadedFromRemote, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('remote_config_cache'), validBody);
    expect(prefs.getString('remote_config_cache_sig'), validSignature);
    expect(prefs.getString('remote_config_cache_loaded_at'), isNotNull);
  });

  test('load() falls back to the last verified cached config when a later fetch fails',
      () async {
    SharedPreferences.setMockInitialValues({});

    await RemoteConfigService.load(client: workingClient());
    final firstLoadedAt = RemoteConfigService.loadedAt;
    expect(firstLoadedAt, isNotNull);

    await RemoteConfigService.load(client: failingClient());

    expect(RemoteConfigService.loadedFromRemote, isTrue);
    // The cached fetch's own original timestamp, not "now" — an offline
    // user should be able to tell this isn't a fresh fetch.
    expect(RemoteConfigService.loadedAt, firstLoadedAt);
  });

  test('load() does not apply a cached config whose signature no longer verifies',
      () async {
    // A body/signature pair that don't match each other (the signature
    // is valid, but for a *different* body) — simulates SharedPreferences
    // having been tampered with directly, bypassing the app's own
    // cache-write path.
    const tamperedBody = '{"test":"value","gemini_api_url":"https://evil.example.com"}';
    SharedPreferences.setMockInitialValues({
      'remote_config_cache': tamperedBody,
      'remote_config_cache_sig': validSignature,
      'remote_config_cache_loaded_at': DateTime.now().toIso8601String(),
    });

    await RemoteConfigService.load(client: failingClient());

    expect(RemoteConfigService.current.geminiApiUrl, isNot('https://evil.example.com'));
  });

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
