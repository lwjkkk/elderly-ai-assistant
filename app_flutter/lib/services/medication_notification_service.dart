/// 用药本地通知服务（Android）：
/// - App 启动/恢复时调 [syncWithServer] 拉取后端用药计划并与本机通知对账；
/// - 通知 id 直接用 medication.id，跨设备对账时另一台设备拉不到这条就取消对应通知；
/// - 手机重启后 flutter_local_notifications 会自动恢复已排程的通知。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import '../services/api.dart';

class MedicationNotificationService {
  MedicationNotificationService._();
  static final MedicationNotificationService instance =
      MedicationNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool _exactAlarmsAllowed = false;
  Future<void>? _syncing;
  bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'medication_reminder',
    '用药提醒',
    description: '按药品时间点推送服药提醒',
    importance: Importance.high,
  );

  Future<void> init() async {
    if (!_supported || _initialized) return;
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    await _plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (resp) {
        debugPrint('notification tapped: ${resp.payload}');
      },
    );
    if (_supported) {
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_channel);
    }
    _initialized = true;
  }

  /// 检查并请求通知权限；未开启时返回 false，由调用方弹窗引导去设置。
  Future<bool> ensurePermission(BuildContext? context) async {
    if (!_supported) return false;
    var status = await Permission.notification.status;
    if (!status.isGranted) {
      status = await Permission.notification.request();
    }
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    _exactAlarmsAllowed =
        await android?.canScheduleExactNotifications() ?? true;
    if (!_exactAlarmsAllowed) {
      _exactAlarmsAllowed =
          await android?.requestExactAlarmsPermission() ?? false;
    }
    return status.isGranted;
  }

  Future<void> activateForSession(BuildContext? context) async {
    if (!_supported) return;
    try {
      await init();
      final allowed = await ensurePermission(context);
      await syncWithServer();
      final needsSettings = !allowed || !_exactAlarmsAllowed;
      if (needsSettings && context != null && context.mounted) {
        final message = !allowed ? '请在系统设置中允许通知，才能收到用药提醒' : '精确闹钟未开启，用药提醒可能延迟';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            action: SnackBarAction(
              label: '去设置',
              onPressed: openAppSettings,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('初始化用药通知失败：$e');
    }
  }

  /// 从后端拉用药计划，与本机通知对账：
  /// - id 在后端列表里：按最新 times 重建通知（旧的先取消再排）；
  /// - id 不在后端列表里（已删除/跨端删除）：取消对应通知。
  Future<void> syncWithServer() {
    if (!_supported) return Future<void>.value();
    return _syncing ??= _sync().whenComplete(() => _syncing = null);
  }

  Future<void> _sync() async {
    try {
      await init();
      if (await ApiService.getToken() == null) {
        await _plugin.cancelAll();
        return;
      }
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      _exactAlarmsAllowed =
          await android?.canScheduleExactNotifications() ?? true;
      List meds;
      try {
        meds = await ApiService.medsList(mine: true);
      } catch (e) {
        debugPrint('sync meds failed: $e');
        return;
      }
      final serverIds = <int>{};
      for (final m in meds) {
        final id = (m['id'] as num).toInt();
        final name = (m['name'] ?? '').toString();
        final dosage = (m['dosage'] ?? '').toString();
        final times =
            (m['times'] as List? ?? const []).map((e) => e.toString()).toList();
        for (final t in times.toSet()) {
          if (!RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(t)) continue;
          serverIds.add(medicationNotificationId(id, t));
          await _scheduleDaily(id, t, name, dosage,
              startDate: m['start_date']?.toString());
        }
      }
      final pending = await _plugin.pendingNotificationRequests();
      for (final r in pending) {
        if (!serverIds.contains(r.id)) {
          await _plugin.cancel(r.id);
        }
      }
    } catch (e) {
      debugPrint('用药通知同步未完成：$e');
    }
  }

  Future<void> _scheduleDaily(int medId, String hm, String name, String dosage,
      {String? startDate}) async {
    final reminder = nextMedicationReminder(hm, startDate: startDate);
    if (reminder == null) return;
    final androidDetails = AndroidNotificationDetails(
      _channel.id,
      _channel.name,
      channelDescription: _channel.description,
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
    );
    final details = NotificationDetails(android: androidDetails);
    await _plugin.zonedSchedule(
      medicationNotificationId(medId, hm),
      '该服药了：$name',
      '$dosage，请按医嘱服用',
      reminder,
      details,
      androidScheduleMode: _exactAlarmsAllowed
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: 'medication:$medId',
    );
  }

  /// 取消所有通知（登出/清空时用）
  Future<void> cancelAll() async {
    if (!_supported) return;
    try {
      await init();
      await _plugin.cancelAll();
    } catch (e) {
      debugPrint('取消通知失败：$e');
    }
  }
}

int medicationNotificationId(int medId, String slot) {
  final parts = slot.split(':');
  return (medId * 1440 + int.parse(parts[0]) * 60 + int.parse(parts[1])) &
      0x7fffffff;
}

tz.TZDateTime? nextMedicationReminder(String slot,
    {String? startDate, DateTime? now}) {
  final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(slot);
  if (match == null) return null;
  final h = int.parse(match[1]!), m = int.parse(match[2]!);
  if (h > 23 || m > 59) return null;
  final zone = tz.getLocation('Asia/Shanghai');
  final current = tz.TZDateTime.from(now ?? DateTime.now(), zone);
  var next =
      tz.TZDateTime(zone, current.year, current.month, current.day, h, m);
  if (!next.isAfter(current))
    next =
        tz.TZDateTime(zone, current.year, current.month, current.day + 1, h, m);
  final start = startDate == null ? null : DateTime.tryParse(startDate);
  if (start != null) {
    final first = tz.TZDateTime(zone, start.year, start.month, start.day, h, m);
    if (first.isAfter(next)) next = first;
  }
  return next;
}
