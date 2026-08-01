import 'package:flutter_test/flutter_test.dart';
import 'package:audio_guide/models/guide_error.dart';

void main() {
  test('GuideError exposes a clear kind and message', () {
    const error = GuideError(
      GuideErrorKind.network,
      'Connexion impossible. Vérifiez votre réseau.',
    );

    expect(error.kind, GuideErrorKind.network);
    expect(error.message, 'Connexion impossible. Vérifiez votre réseau.');
    expect(error.toString(), 'Connexion impossible. Vérifiez votre réseau.');
  });
}
