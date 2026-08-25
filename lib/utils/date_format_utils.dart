import 'package:intl/intl.dart';

/// #129: the shared date+time format used across Settings, About analysis,
/// and the report-content email — was 4 separate hardcoded
/// `DateFormat('dd/MM/yyyy à HH:mm')` copies, including the literal French
/// "à" word baked into the pattern itself (so it wasn't just untranslated,
/// it would have been wrong even after cosmetic string extraction).
/// `DateFormat.yMd(locale).add_Hm()` gives each locale its own idiomatic
/// short date+time format instead of forcing one fixed token order.
String formatLocalDateTime(DateTime dateTime, String locale) =>
    DateFormat.yMd(locale).add_Hm().format(dateTime);
