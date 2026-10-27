import 'package:flutter_test/flutter_test.dart';

import 'package:chzzk_multiviewer/format.dart';

void main() {
  test('formatCount groups digits by three', () {
    expect(formatCount(0), '0');
    expect(formatCount(999), '999');
    expect(formatCount(1000), '1,000');
    expect(formatCount(19598), '19,598');
    expect(formatCount(1234567), '1,234,567');
  });

  test('formatElapsed shows at most two units', () {
    expect(formatElapsed(const Duration(minutes: 0)), '0분');
    expect(formatElapsed(const Duration(minutes: 45)), '45분');
    expect(formatElapsed(const Duration(hours: 2, minutes: 15)), '2시간 15분');
    expect(formatElapsed(const Duration(hours: 3)), '3시간');
    expect(
      formatElapsed(const Duration(days: 1, hours: 3, minutes: 9)),
      '1일 3시간',
    );
    expect(formatElapsed(const Duration(minutes: -5)), '0분');
  });

  test('parseChzzkDateTime reads Chzzk timestamps as Korean time', () {
    final parsed = parseChzzkDateTime('2026-10-26 08:28:45');
    expect(parsed, DateTime.utc(2026, 10, 25, 23, 28, 45));
    expect(parseChzzkDateTime(null), isNull);
    expect(parseChzzkDateTime('not a date'), isNull);
  });
}
