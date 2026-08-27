import 'dart:convert';
import 'package:http/http.dart' as http;
import 'network_config.dart';

/// A short label + description pulled from a Wikidata entity (#276).
class WikidataInfo {
  final String label;
  final String? description;

  const WikidataInfo({required this.label, this.description});

  /// A single line combining label and description, ready to drop into
  /// a prompt context — e.g. "Stolperstein à la mémoire d'Umberto
  /// Chignoli (stolperstein à Fontenay-sous-Bois, France)".
  String get summary =>
      description != null && description!.isNotEmpty ? '$label ($description)' : label;
}

/// Fetches a short label/description for a Wikidata entity (#276) — for
/// POIs [PoiService] finds a `wikidata` tag on. Fills a real gap
/// [WikipediaService] alone can't: many small, specific things (a
/// personal memorial, a minor artwork) have a structured Wikidata entry
/// with no full Wikipedia article at all, so a name-based Wikipedia
/// search comes back empty even though real, curated identification data
/// exists.
class WikidataService {
  /// [client] allows injecting a mock HTTP client in tests. [language]
  /// tries first, falling back to English if that label/description is
  /// missing (mirrors [WikipediaService.searchByName]'s fr-then-en
  /// fallback).
  static Future<WikidataInfo?> fetchInfo(
    String qid, {
    String language = 'fr',
    http.Client? client,
  }) async {
    if (qid.isEmpty) return null;
    try {
      final uri = Uri.parse(
        'https://www.wikidata.org/w/api.php'
        '?action=wbgetentities'
        '&ids=$qid'
        '&props=labels|descriptions'
        '&languages=$language|en'
        '&format=json'
        '&origin=*',
      );
      final c = client ?? http.Client();
      final response = await c
          .get(uri, headers: {'User-Agent': NetworkConfig.userAgent})
          .timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final entity = data['entities']?[qid] as Map<String, dynamic>?;
      if (entity == null) return null;

      final labels = entity['labels'] as Map<String, dynamic>? ?? {};
      final descriptions = entity['descriptions'] as Map<String, dynamic>? ?? {};

      final label = (labels[language]?['value'] ?? labels['en']?['value']) as String?;
      if (label == null || label.isEmpty) return null;
      final description =
          (descriptions[language]?['value'] ?? descriptions['en']?['value']) as String?;

      return WikidataInfo(label: label, description: description);
    } catch (_) {
      return null;
    }
  }
}
