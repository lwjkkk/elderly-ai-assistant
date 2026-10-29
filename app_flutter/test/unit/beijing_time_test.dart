import 'package:flutter_test/flutter_test.dart';
import 'package:elderly_ai_assistant/services/beijing_time.dart';

void main() {
  test('formats offset timestamps as Beijing time to whole seconds', () {
    expect(
      formatBeijingDateTime('2026-10-29T15:34:19.296260+08:00'),
      '2026-10-29 15:34:19',
    );
    expect(
      formatBeijingDateTime('2026-10-29T07:34:19.296260Z'),
      '2026-10-29 15:34:19',
    );
    expect(
      formatBeijingDateTime('2026-10-29T15:34:19+08:00'),
      '2026-10-29 15:34:19',
    );
  });

  test('uses source-specific rules for timestamps without a timezone', () {
    expect(
      formatBeijingDateTime('2026-10-29T07:34:19'),
      '2026-10-29 15:34:19',
    );
    expect(
      formatBeijingDateTime(
        '2026-10-29T15:34:19',
        naiveTimeZone: NaiveDateTimeZone.beijing,
      ),
      '2026-10-29 15:34:19',
    );
    final local = DateTime(2026, 10, 29, 15, 34, 19);
    expect(
      formatBeijingDateTime(
        '2026-10-29T15:34:19',
        naiveTimeZone: NaiveDateTimeZone.deviceLocal,
      ),
      formatBeijingDateTime(local),
    );
  });

  test('preserves date-only values and formats timestamps before taking date',
      () {
    expect(formatBeijingDate('2026-10-29'), '2026-10-29');
    expect(
      formatBeijingDate('2026-10-28T16:05:00Z'),
      '2026-10-29',
    );
  });

  test('shows stable fallback text for empty or invalid input', () {
    expect(formatBeijingDateTime(null), '时间未知');
    expect(formatBeijingDateTime('not-a-time'), '时间未知');
    expect(formatBeijingDate(''), '日期未知');
  });
}
