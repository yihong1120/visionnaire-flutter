import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:visionnaire/utils/violation_timestamp.dart';

void main() {
  setUpAll(() => initializeDateFormatting('fr'));

  test('formats equivalent Rust API timestamps in the viewer time zone', () {
    final String display =
        formatViolationTimestamp('2026-11-19T09:30:22.554Z', 'fr');
    final DateTime local = DateTime.utc(2026, 11, 19, 9, 30, 22, 554).toLocal();

    expect(
      formatViolationTimestamp('2026-11-19T09:30:22.554+00:00', 'fr'),
      display,
    );
    expect(
      formatViolationTimestamp('2026-11-19T17:30:22.554+08:00', 'fr'),
      display,
    );
    expect(display, startsWith(DateFormat.yMMMd('fr').format(local)));
    expect(display, contains(DateFormat.Hms('fr').format(local)));
    expect(display, matches(RegExp(r' UTC[+-]\d{2}:\d{2}$')));
  });

  test('keeps empty and unparsed legacy values displayable', () {
    expect(formatViolationTimestamp(null, 'fr'), '');
    expect(formatViolationTimestamp('ancien relevé', 'fr'), 'ancien relevé');
  });
}
