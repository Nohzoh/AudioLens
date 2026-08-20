// One-off tool: generates the Ed25519 keypair used to sign config.json.
//
// Run once (or again only if the key is ever compromised and must be
// rotated): `dart run scripts/generate_config_signing_key.dart`
//
// The PRIVATE key is printed for you to save into a password manager
// (Keeper) and to a local-only file — it must never be committed, never
// put in a GitHub secret, never touch CI. Only the PUBLIC key gets baked
// into the app (lib/services/remote_config_service.dart).
import 'dart:convert';
import 'package:cryptography/cryptography.dart';

Future<void> main() async {
  final algorithm = Ed25519();
  final keyPair = await algorithm.newKeyPair();

  final privateKeyBytes = await keyPair.extractPrivateKeyBytes();
  final publicKey = await keyPair.extractPublicKey();

  final privateKeyB64 = base64Encode(privateKeyBytes);
  final publicKeyB64 = base64Encode(publicKey.bytes);

  // ignore: avoid_print
  print('=== PRIVATE KEY (save to Keeper, then delete from this terminal '
      'history — NEVER commit, NEVER put in a GitHub secret) ===');
  // ignore: avoid_print
  print(privateKeyB64);
  // ignore: avoid_print
  print('');
  // ignore: avoid_print
  print('=== PUBLIC KEY (paste into '
      'lib/services/remote_config_service.dart) ===');
  // ignore: avoid_print
  print(publicKeyB64);
}
