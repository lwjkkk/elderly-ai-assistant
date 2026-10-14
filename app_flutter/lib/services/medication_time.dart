/// 与后端一致，以北京时间判断当天计划是否到点。
DateTime medicationNow([DateTime? now]) =>
    (now ?? DateTime.now()).toUtc().add(const Duration(hours: 8));

bool medicationSlotDue(String slot, {String? date, DateTime? now}) {
  final current = medicationNow(now);
  final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(slot);
  if (match == null) return false;
  final hour = int.parse(match.group(1)!);
  final minute = int.parse(match.group(2)!);
  if (hour > 23 || minute > 59) return false;
  final day = date == null ? current : DateTime.tryParse(date);
  if (day == null) return false;
  final scheduled = DateTime.utc(day.year, day.month, day.day, hour, minute);
  return !scheduled.isAfter(current);
}
