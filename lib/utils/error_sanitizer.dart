/// Removes API keys and other sensitive fragments from error messages
/// before they're surfaced to the UI or logs (T06 — extracted from
/// AudioGuideService so TtsOrchestrator can share the same logic).
String sanitizeError(String error) {
  return error
      .replaceAll('Exception: ', '')
      .replaceAll(RegExp(r'key=[A-Za-z0-9_\-]{20,}'), 'key=***')
      .replaceAll(RegExp(r'AIza[A-Za-z0-9_\-]{30,}'), '***')
      .replaceAll(RegExp(r'\?key=[^&\s"]+'), '?key=***');
}
