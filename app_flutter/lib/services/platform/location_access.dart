import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

/// 天气和咨询录音共用权限申请，避免启动时同时弹出多个请求。
class LocationAccess {
  static Future<LocationPermission>? _request;
  static Position? _cachedPosition;

  static Future<LocationPermission> ensurePermission() =>
      _request ??= _ensure().whenComplete(() => _request = null);

  static Future<LocationPermission> _ensure() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission;
  }

  static Future<void> onStartup(BuildContext context) async {
    try {
      final permission = await ensurePermission();
      if (!context.mounted) return;
      final blocked = permission == LocationPermission.deniedForever;
      final granted = permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;
      final serviceOff =
          granted && !await Geolocator.isLocationServiceEnabled();
      if (!context.mounted || (!blocked && !serviceOff)) return;
      final open = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('开启定位'),
          content: Text(blocked
              ? '请在应用设置中允许定位，用于当地天气和咨询录音的推荐地址。'
              : '请开启手机定位，用于当地天气和咨询录音的推荐地址。'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('暂不开启')),
            TextButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('去开启')),
          ],
        ),
      );
      if (open == true) {
        if (blocked) {
          await Geolocator.openAppSettings();
        } else {
          await Geolocator.openLocationSettings();
        }
      }
    } catch (_) {
      // 不支持定位的平台仍可正常使用其他功能。
    }
  }

  static Future<String> suggestAddress() async {
    try {
      final permission = await ensurePermission();
      if (permission != LocationPermission.whileInUse &&
          permission != LocationPermission.always) {
        return '请在应用设置中允许定位，或手动填写地址';
      }
      if (!await Geolocator.isLocationServiceEnabled()) {
        return '请开启手机定位，或手动填写地址';
      }
      Position? recent = _cachedPosition;
      try {
        final systemRecent = await Geolocator.getLastKnownPosition()
            .timeout(const Duration(seconds: 2));
        if (systemRecent != null &&
            (recent == null ||
                systemRecent.timestamp.isAfter(recent.timestamp))) {
          recent = systemRecent;
        }
      } catch (_) {}

      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.medium,
            timeLimit: const Duration(seconds: 10));
        _cachedPosition = position;
      } catch (_) {
        if (_isRecent(recent)) position = recent;
      }
      if (position == null) return '定位暂不可用，请手动填写地址';
      final places =
          await placemarkFromCoordinates(position.latitude, position.longitude)
              .timeout(const Duration(seconds: 8));
      if (places.isNotEmpty) {
        final p = places.first;
        final parts = <String>{
          p.administrativeArea ?? '',
          p.locality ?? '',
          p.subLocality ?? '',
          p.street ?? '',
          p.name ?? '',
        }..removeWhere((s) => s.trim().isEmpty);
        if (parts.isNotEmpty) return '推荐地址：${parts.join('')}';
      }
      return '暂未获取到街道地址，请手动填写';
    } catch (_) {
      return '定位暂不可用，请手动填写地址';
    }
  }

  static bool _isRecent(Position? position) {
    if (position == null) return false;
    final age = DateTime.now().difference(position.timestamp);
    return !age.isNegative && age <= const Duration(minutes: 30);
  }
}
