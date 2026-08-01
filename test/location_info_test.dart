import 'package:flutter_test/flutter_test.dart';
import 'package:audio_guide/services/location_service.dart';

void main() {
  test('LocationInfo.contextForPrompt includes available address parts', () {
    const info = LocationInfo(
      latitude: 48.8566,
      longitude: 2.3522,
      road: 'Rue de Rivoli',
      city: 'Paris',
      country: 'France',
    );

    expect(
      info.contextForPrompt,
      'Localisation GPS : 48.8566, 2.3522 (Rue de Rivoli, Paris, France)',
    );
  });

  test('LocationInfo.contextForPrompt falls back to coordinates when address is empty', () {
    const info = LocationInfo(latitude: 12.34, longitude: 56.78);

    expect(info.contextForPrompt, 'Localisation GPS : 12.34, 56.78');
  });
}
