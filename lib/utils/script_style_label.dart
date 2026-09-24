import '../l10n/app_localizations.dart';

/// Script style keys and their localized labels (T75/T48, #425), in the
/// order they're offered. Shared by the history regenerate sheet and the
/// "About this analysis" screen, which used to show the raw key.
List<(String, String)> scriptStyleOptions(AppLocalizations l10n) => [
      ('immersive', l10n.settingsStyleImmersive),
      ('academic', l10n.settingsStyleAcademic),
      ('anecdotal', l10n.settingsStyleAnecdotal),
      ('concise', l10n.settingsStyleConcise),
      ('kids', l10n.settingsStyleKids),
    ];

/// The localized label for [style], or the raw key for an unknown one
/// (e.g. a style removed since that entry was generated).
String scriptStyleLabel(AppLocalizations l10n, String style) {
  for (final (key, label) in scriptStyleOptions(l10n)) {
    if (key == style) return label;
  }
  return style;
}
