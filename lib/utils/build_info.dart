import 'package:intl/intl.dart';

const String buildDate = String.fromEnvironment(
  'BUILD_DATE',
  defaultValue: 'non disponible',
);

String formatBuildDate(String value) {
  if (value == 'non disponible') return value;

  try {
    final parsed = DateTime.parse(value);
    return DateFormat('dd/MM/yyyy à HH:mm').format(parsed.toLocal());
  } catch (_) {
    return value;
  }
}
