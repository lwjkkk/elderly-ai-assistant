import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// 每个账号独立存储会话；串行写入，离开页面后的回复不会覆盖新会话。
class ChatArchive {
  static Future<void> _pending = Future<void>.value();
  static String _key(String accountKey) => '${accountKey}_sessions_v1';

  static Future<void> _write(Future<void> Function() action) {
    final next = _pending.then((_) => action());
    _pending = next.catchError((Object _) {});
    return next;
  }

  static Future<void> migrate(String accountKey) => _write(() async {
        final prefs = await SharedPreferences.getInstance();
        if (prefs.containsKey(_key(accountKey))) return;
        final legacy = prefs.getString(accountKey);
        final messages =
            legacy == null ? <dynamic>[] : jsonDecode(legacy) as List;
        await prefs.setString(
            _key(accountKey),
            jsonEncode([
              if (messages.isNotEmpty)
                {'id': 'legacy', 'created_at': '', 'messages': messages},
            ]));
      });

  static Future<void> save(String accountKey, String sessionId,
          List<Map<String, String>> messages) =>
      _write(() async {
        if (messages.isEmpty) return;
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString(_key(accountKey));
        final sessions = raw == null ? <dynamic>[] : jsonDecode(raw) as List;
        final index = sessions.indexWhere((s) => s['id'] == sessionId);
        final session = {
          'id': sessionId,
          'created_at': sessionId,
          'messages': messages
        };
        if (index < 0) {
          sessions.add(session);
        } else {
          sessions[index] = session;
        }
        await prefs.setString(_key(accountKey), jsonEncode(sessions));
      });

  static Future<List<Map<String, dynamic>>> load(String accountKey) async {
    await _pending;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(accountKey));
    final sessions = raw == null ? <dynamic>[] : jsonDecode(raw) as List;
    return sessions.reversed
        .map((s) => Map<String, dynamic>.from(s as Map))
        .toList();
  }
}
