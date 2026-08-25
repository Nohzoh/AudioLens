import 'date_format_utils.dart';

// #129: kept as a plain sentinel string (not localized) — it's compared
// against by value in formatBuildDate below, and is only ever the literal
// build-time default when BUILD_DATE wasn't set, never shown as-is in a
// context a user would actually read the word in.
const String buildDate = String.fromEnvironment(
  'BUILD_DATE',
  defaultValue: 'unavailable',
);

/// [unavailableLabel] is the localized string to show when [value] is the
/// unset sentinel above — the caller supplies it since this file has no
/// access to AppLocalizations.
String formatBuildDate(String value, String locale, String unavailableLabel) {
  if (value == 'unavailable') return unavailableLabel;

  try {
    final parsed = DateTime.parse(value);
    return formatLocalDateTime(parsed.toLocal(), locale);
  } catch (_) {
    return value;
  }
}
