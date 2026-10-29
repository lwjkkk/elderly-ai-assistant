/// Source-specific handling for timestamps that have no explicit timezone.
enum NaiveDateTimeZone { utc, deviceLocal, beijing }

const _beijingOffset = Duration(hours: 8);
final _dateOnlyPattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');
final _explicitZonePattern = RegExp(r'(?:[zZ]|[+-]\d{2}:?\d{2})$');
final _timePattern = RegExp(r'[T ]\d{2}:\d{2}');

DateTime? parseBeijingDateTime(
  Object? value, {
  NaiveDateTimeZone naiveTimeZone = NaiveDateTimeZone.utc,
}) {
  if (value is DateTime) return value.toUtc().add(_beijingOffset);

  final raw = value?.toString().trim() ?? '';
  if (raw.isEmpty || !_timePattern.hasMatch(raw)) return null;
  final normalized = raw.replaceFirst(' ', 'T');
  final hasExplicitZone = _explicitZonePattern.hasMatch(normalized);
  final input =
      hasExplicitZone || naiveTimeZone == NaiveDateTimeZone.deviceLocal
          ? normalized
          : '${normalized}Z';
  final parsed = DateTime.tryParse(input);
  if (parsed == null) return null;

  final instant = naiveTimeZone == NaiveDateTimeZone.beijing && !hasExplicitZone
      ? parsed.subtract(_beijingOffset)
      : parsed;
  return instant.toUtc().add(_beijingOffset);
}

String formatBeijingDateTime(
  Object? value, {
  NaiveDateTimeZone naiveTimeZone = NaiveDateTimeZone.utc,
  String unknownText = '时间未知',
}) {
  final date = parseBeijingDateTime(value, naiveTimeZone: naiveTimeZone);
  if (date == null) return unknownText;
  return '${_four(date.year)}-${_two(date.month)}-${_two(date.day)} '
      '${_two(date.hour)}:${_two(date.minute)}:${_two(date.second)}';
}

String formatBeijingDate(
  Object? value, {
  NaiveDateTimeZone naiveTimeZone = NaiveDateTimeZone.utc,
  String unknownText = '日期未知',
}) {
  if (value is DateTime) {
    final date = value.toUtc().add(_beijingOffset);
    return _dateText(date);
  }

  final raw = value?.toString().trim() ?? '';
  if (raw.isEmpty) return unknownText;
  if (_dateOnlyPattern.hasMatch(raw)) {
    final date = DateTime.tryParse(raw);
    return date == null ? unknownText : _dateText(date);
  }

  final date = parseBeijingDateTime(raw, naiveTimeZone: naiveTimeZone);
  return date == null ? unknownText : _dateText(date);
}

String _dateText(DateTime date) =>
    '${_four(date.year)}-${_two(date.month)}-${_two(date.day)}';

String _four(int value) => value.toString().padLeft(4, '0');
String _two(int value) => value.toString().padLeft(2, '0');
