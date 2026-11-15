import 'dart:math' as math;
import 'wikipedia_service.dart';

/// #614: a label as read on the photo, with the spelling of the lines an
/// encyclopedia article confirmed, and what those articles say.
class ResolvedLabel {
  final String labelText;
  final String? facts;
  const ResolvedLabel(this.labelText, [this.facts]);
}

typedef LabelSearch = Future<List<WikipediaResult>> Function(String query);

Future<List<WikipediaResult>> _wikipediaSearch(String query) =>
    WikipediaService.searchByName(query: query, limit: 3, extractChars: 320);

const _techniqueStart = [
  'huile', 'acrylique', 'aquarelle', 'gouache', 'pastel', 'encre', 'fusain',
  'bronze', 'marbre', 'platre', 'bois', 'technique', 'oil', 'inv', 'don', 'depot',
];

const _artWords = [
  'peintre', 'sculpt', 'artiste', 'dessinat', 'graveur', 'photograph',
  'plasticien', 'painter', 'artist', 'illustrat', 'céramiste', 'ceramiste',
];

/// Lower case, no accents, no disambiguation suffix, single spaces.
String normalizeLabelName(String s) {
  const accents = {
    'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a', 'ç': 'c', 'é': 'e', 'è': 'e',
    'ê': 'e', 'ë': 'e', 'î': 'i', 'ï': 'i', 'í': 'i', 'ô': 'o', 'ö': 'o',
    'ó': 'o', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ú': 'u', 'ÿ': 'y', 'œ': 'oe', 'ñ': 'n',
  };
  final lower = s
      .replaceAll(RegExp(r'\s*\(.*\)\s*$'), '')
      .toLowerCase()
      .split('')
      .map((c) => accents[c] ?? c)
      .join();
  return lower.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
}

int editDistance(String a, String b) {
  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      cur[j] = math.min(math.min(cur[j - 1] + 1, prev[j] + 1), prev[j - 1] + cost);
    }
    prev = cur;
  }
  return prev[b.length];
}

/// True when [articleTitle] is [line] give or take a few misread
/// letters: text recognition on a small label reads « Lais Alvarcz » for
/// « Luis Alvarez ». One letter in six may differ; short names must
/// match exactly.
bool labelLineMatches(String line, String articleTitle) {
  final a = normalizeLabelName(line);
  final b = normalizeLabelName(articleTitle);
  if (a.isEmpty || b.isEmpty) return false;
  final allowed = a.length >= 8 ? a.length ~/ 6 : 0;
  if ((a.length - b.length).abs() > allowed) return false;
  return editDistance(a, b) <= allowed;
}

bool _usableArticle(WikipediaResult r) {
  final extract = r.extract.toLowerCase();
  if (extract.trim().length < 40) return false;
  // A disambiguation page says nothing about this work.
  if (RegExp(r'peut désigner|peuvent désigner|may refer to|homonymie').hasMatch(extract)) {
    return false;
  }
  // A biography that is not an artist's is a namesake (the physicist
  // Luis Alvarez for the painter): never offered as the author.
  final biography = RegExp(r'\bn[ée]e? (le|en|à)\b|\bborn\b').hasMatch(extract);
  if (biography && !_artWords.any(extract.contains)) return false;
  return true;
}

/// Looks up the first lines of [labelText] (lines joined by " / ") and
/// returns the label with confirmed spellings plus the matching facts.
/// Any failure leaves the label as read, without facts.
Future<ResolvedLabel> resolveLabel(String labelText, {LabelSearch? search}) async {
  final find = search ?? _wikipediaSearch;
  final lines = labelText.split(' / ');
  final facts = <int, String>{};
  Future<void> resolve(int i) async {
    final norm = normalizeLabelName(lines[i]);
    if (norm.length < 6 || RegExp(r'^[0-9 ]+$').hasMatch(norm)) return;
    if (_techniqueStart.contains(norm.split(' ').first)) return;
    try {
      final results = await find(lines[i]).timeout(const Duration(seconds: 6));
      for (final r in results) {
        if (!labelLineMatches(lines[i], r.title) || !_usableArticle(r)) continue;
        lines[i] = r.title.replaceAll(RegExp(r'\s*\(.*\)\s*$'), '');
        facts[i] = '« ${r.title} » : ${r.extract.trim()}';
        return;
      }
    } catch (_) {
      // No network, slow answer: the line stays as read.
    }
  }

  await Future.wait([for (var i = 0; i < lines.length && i < 3; i++) resolve(i)]);
  return ResolvedLabel(lines.join(' / '), facts.isEmpty ? null : ([...facts.keys]..sort()).take(2).map((i) => facts[i]).join(' '));
}
