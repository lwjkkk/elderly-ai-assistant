import 'package:flutter_test/flutter_test.dart';

import 'package:elderly_ai_assistant/services/medication_time.dart';

void main() {
  test('one-hour check-in boundary is inclusive', () {
    expect(
      medicationSlotWindow('08:00', now: DateTime.utc(2026, 10, 13, 0, 59, 59)),
      MedicationSlotWindow.due,
    );
    expect(
      medicationSlotWindow('08:00', now: DateTime.utc(2026, 10, 13, 1, 0)),
      MedicationSlotWindow.due,
    );
    expect(
      medicationSlotWindow('08:00', now: DateTime.utc(2026, 10, 13, 1, 0, 1)),
      MedicationSlotWindow.expired,
    );
    expect(
      medicationSlotWindow('09:00', now: DateTime.utc(2026, 10, 13, 0, 59, 59)),
      MedicationSlotWindow.notDue,
    );
  });

  test('completed slots are not counted as overdue', () {
    final afterGrace = DateTime.utc(2026, 10, 13, 1, 0, 1);
    expect(
      medicationSlotOverdue('taken', '08:00', now: afterGrace),
      isFalse,
    );
    expect(
      medicationSlotOverdue('pending', '08:00', now: afterGrace),
      isTrue,
    );
    expect(
      medicationSlotOverdue('missed', '08:00',
          now: DateTime.utc(2026, 10, 13, 0, 0)),
      isTrue,
    );
  });
}
