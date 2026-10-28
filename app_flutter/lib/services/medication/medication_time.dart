/// 与后端一致，以北京时间判断当天计划是否到点。
DateTime medicationNow([DateTime? now]) =>
    (now ?? DateTime.now()).toUtc().add(const Duration(hours: 8));

enum MedicationSlotWindow { invalid, notDue, due, expired }

const medicationCheckinGrace = Duration(hours: 1);

MedicationSlotWindow medicationSlotWindow(String slot,
    {String? date, DateTime? now}) {
  final current = medicationNow(now);
  final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(slot);
  if (match == null) return MedicationSlotWindow.invalid;
  final hour = int.parse(match.group(1)!);
  final minute = int.parse(match.group(2)!);
  if (hour > 23 || minute > 59) return MedicationSlotWindow.invalid;
  final day = date == null ? current : DateTime.tryParse(date);
  if (day == null) return MedicationSlotWindow.invalid;
  final scheduled = DateTime.utc(day.year, day.month, day.day, hour, minute);
  final elapsed = current.difference(scheduled);
  if (elapsed.isNegative) return MedicationSlotWindow.notDue;
  if (elapsed > medicationCheckinGrace) return MedicationSlotWindow.expired;
  return MedicationSlotWindow.due;
}

bool medicationSlotDue(String slot, {String? date, DateTime? now}) {
  return medicationSlotWindow(slot, date: date, now: now) ==
      MedicationSlotWindow.due;
}

bool medicationSlotOverdue(String status, String slot,
    {String? date, DateTime? now}) {
  if (status == 'missed') return true;
  if (status != 'pending') return false;
  return medicationSlotWindow(slot, date: date, now: now) ==
      MedicationSlotWindow.expired;
}
