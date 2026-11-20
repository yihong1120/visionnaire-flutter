import 'package:intl/intl.dart';

/// Formats a stored detection instant in the viewer's time zone.
String formatViolationTimestamp(Object? value, String locale) {
  final String raw = value?.toString().trim() ?? '';
  final DateTime? time = DateTime.tryParse(raw)?.toLocal();
  if (time == null) return raw;

  final int offset = time.timeZoneOffset.inMinutes;
  final int minutes = offset.abs();
  final String sign = offset < 0 ? '-' : '+';
  final String hours = (minutes ~/ 60).toString().padLeft(2, '0');
  final String remainder = (minutes % 60).toString().padLeft(2, '0');
  final String display = DateFormat.yMMMd(locale).add_Hms().format(time);
  return '$display UTC$sign$hours:$remainder';
}
