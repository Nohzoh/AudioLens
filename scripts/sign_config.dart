// Signs config.json with the Ed25519 private key so the app can verify
// its integrity at fetch time (see RemoteConfigService). Run this locally
// every time config.json changes, then commit config.json AND
// config.json.sig together — never sign in CI, the whole point is that
// the private key never touches it.
//
// #384: also mirrors both files into docs/ so the GitHub Pages site
// serves the exact same bytes (that's where current app builds fetch
// from; the repo-root copies stay for builds shipped before #384, which
// still hit raw.githubusercontent.com). A drift test in
// test/remote_config_service_test.dart fails CI if the two pairs ever
// diverge.
//
// Usage: dart run scripts/sign_config.dart <base64_private_key>
// (get the private key from Keeper — never pass it inline in shell
// history-visible form if you can avoid it; prefer pasting at a prompt.)
import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';

Future<void> main(List<String> args) async {
  String? privateKeyB64 = args.isNotEmpty ? args.first : null;
  if (privateKeyB64 == null) {
    stdout.write('Private key (base64, from Keeper): ');
    privateKeyB64 = stdin.readLineSync()?.trim();
  }
  if (privateKeyB64 == null || privateKeyB64.isEmpty) {
    stderr.writeln('No private key provided.');
    exit(1);
  }

  final configFile = File('config.json');
  if (!configFile.existsSync()) {
    stderr.writeln('config.json not found — run this from the repo root.');
    exit(1);
  }

  final algorithm = Ed25519();
  final keyPair = await algorithm.newKeyPairFromSeed(base64Decode(privateKeyB64));
  final bytes = await configFile.readAsBytes();
  final signature = await algorithm.sign(bytes, keyPair: keyPair);

  final sigB64 = base64Encode(signature.bytes);
  File('config.json.sig').writeAsStringSync(sigB64);

  // #384: keep the GitHub Pages copies byte-identical to the root ones.
  Directory('docs').createSync(recursive: true);
  File('docs/config.json').writeAsBytesSync(bytes);
  File('docs/config.json.sig').writeAsStringSync(sigB64);

  // ignore: avoid_print
  print('Wrote config.json.sig + docs/config.json{,.sig} — commit them '
      'together with config.json.');
}
