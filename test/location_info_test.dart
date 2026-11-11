import 'package:flutter_test/flutter_test.dart';
import 'package:audiolens/services/location_service.dart';

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

  // #482 — recorded Nominatim answer for 44.1248726, 4.0804628 (Alès),
  // where a photo of this church was described as the town's cathedral.
  group('place name from reverse geocoding', () {
    Map<String, dynamic> geo({
      String? name = 'Église Saint-Joseph',
      String osmClass = 'amenity',
      String type = 'place_of_worship',
      String road = 'Rue Frédéric Mistral',
    }) =>
        {
          'class': osmClass,
          'type': type,
          'addresstype': osmClass,
          'name': name,
          'address': {
            'amenity': name,
            'road': road,
            'quarter': 'Les Prés Saint-Jean',
            'town': 'Alès',
            'country': 'France',
          },
        };

    test('keeps the name and category of a named place of worship', () {
      final info = LocationInfo.fromGeocode(44.1248726, 4.0804628, geo());

      expect(info.placeName, 'Église Saint-Joseph');
      expect(info.placeCategory, 'amenity=place_of_worship');
      expect(info.road, 'Rue Frédéric Mistral');
      expect(info.city, 'Alès');
    });

    test('reads the class from jsonv2 responses too', () {
      final v2 = geo()..remove('class');
      v2['category'] = 'tourism';
      v2['type'] = 'museum';
      v2['name'] = 'Musée du Colombier';

      expect(LocationInfo.fromGeocode(1, 2, v2).placeName, 'Musée du Colombier');
    });

    test('ignores a road, a house and an everyday amenity', () {
      for (final g in [
        geo(name: 'Rue Frédéric Mistral', osmClass: 'highway', type: 'residential'),
        geo(name: '', osmClass: 'place', type: 'house'),
        geo(name: 'Pharmacie du Centre', osmClass: 'amenity', type: 'pharmacy'),
        geo(name: 'Boulangerie Martin', osmClass: 'shop', type: 'bakery'),
      ]) {
        expect(LocationInfo.fromGeocode(1, 2, g).placeName, isNull);
      }
    });

    test('a failed lookup leaves every address field empty', () {
      final info = LocationInfo.fromGeocode(1, 2, null);

      expect(info.placeName, isNull);
      expect(info.contextForPrompt, 'Localisation GPS : 1.0, 2.0');
    });
  });
}
