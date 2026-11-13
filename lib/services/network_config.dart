/// Network constants shared across services (T06 — deduplication).
class NetworkConfig {
  /// #554: where the operators of OpenStreetMap and Wikimedia services can
  /// find out who is calling them — both usage policies ask for an
  /// identifying User-Agent with contact information, and generic ones
  /// are the first to be throttled or blocked.
  static const String contactUrl = 'https://github.com/Nohzoh/AudioLens';

  static String _version = '';

  /// Set once at startup from the installed package version.
  static void setAppVersion(String version) => _version = version.trim();

  /// User-Agent sent on public APIs (Wikipedia, Wikidata, Nominatim,
  /// Overpass, Telegram), e.g. `AudioLens/0.15.13 (+https://github.com/Nohzoh/AudioLens)`.
  static String get userAgent =>
      'AudioLens${_version.isEmpty ? '' : '/$_version'} (+$contactUrl)';
}
