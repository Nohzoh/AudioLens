enum GuideErrorKind {
  network,
  ai,
  tts,
  location,
  unknown,
}

class GuideError implements Exception {
  final GuideErrorKind kind;
  final String message;

  const GuideError(this.kind, this.message);

  @override
  String toString() => message;
}
