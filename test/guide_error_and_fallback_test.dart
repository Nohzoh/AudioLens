import 'package:flutter_test/flutter_test.dart';
import 'package:audiolens/models/guide_error.dart';

void main() {
  test('GuideError preserves its kind and user-facing message', () {
    const error = GuideError(
      GuideErrorKind.network,
      'Connexion impossible. Vérifiez votre réseau.',
    );

    expect(error.kind, GuideErrorKind.network);
    expect(error.message, 'Connexion impossible. Vérifiez votre réseau.');
    expect(error.toString(), 'Connexion impossible. Vérifiez votre réseau.');
  });

  test('GuideErrorKind values cover the main failure families', () {
    expect(GuideErrorKind.values, containsAll([
      GuideErrorKind.network,
      GuideErrorKind.ai,
      GuideErrorKind.tts,
      GuideErrorKind.location,
      GuideErrorKind.unknown,
    ]));
  });
}
