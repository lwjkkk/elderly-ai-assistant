import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:elderly_ai_assistant/services/api.dart';
import 'package:elderly_ai_assistant/services/health/family_alert_content.dart';
import 'package:elderly_ai_assistant/pages/profile/me_tab.dart';

class _PrivacyAgeAdapter implements HttpClientAdapter {
  bool forced = true;
  bool fail = false;
  String tier = 'senior';
  final calls = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream,
      Future<void>? cancel) async {
    calls.add(options);
    final body = options.path == '/api/privacy'
        ? {
            'sync_summary_to_family': true,
            'forced_share': forced,
            'age_tier': tier
          }
        : options.path == '/api/users/profile'
            ? {
                'age': 60,
                'birth_ym': '1966-10',
                'age_tier': tier,
                'forced_share': forced
              }
            : [];
    return ResponseBody.fromString(
        jsonEncode(body), fail && options.path == '/api/privacy' ? 500 : 200,
        headers: {
          Headers.contentTypeHeader: ['application/json']
        });
  }

  @override
  void close({bool force = false}) {}
}

Future<void> _pumpMe(WidgetTester tester) async {
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: MeTab(role: 'elder'))));
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late _PrivacyAgeAdapter adapter;
  setUp(() {
    SharedPreferences.setMockInitialValues(
        {'role': 'elder', 'token': 'test', 'user_id': 7});
    adapter = _PrivacyAgeAdapter();
    ApiService.dio.httpClientAdapter = adapter;
  });

  test('vital alert card keeps the actual event and threshold source', () {
    final card = normalizeFamilyAlertContent({
      'kind': 'health',
      'type': 'vital_alert',
      'vital_type': 'bs',
      'alert_id': 17,
      'level': 'high',
      'message': '复核测量结果',
      'source': '阈值参考A'
    });
    expect(card['kind'], 'health');
    expect(card['title'], '血糖异常提醒');
    expect(card['lines'], contains('事件编号：17'));
    expect(card['lines'], contains('阈值依据：阈值参考A'));
    expect((card['lines'] as List).last, contains('送达状态未提供'));
    expect(normalizeFamilyAlertContent({'kind': 'text', 'text': '你好'}),
        {'kind': 'text', 'text': '你好'});
  });

  testWidgets('server forced sharing removes the unavailable privacy toggle',
      (tester) async {
    await _pumpMe(tester);
    expect(find.byKey(const ValueKey('family-summary-sharing')), findsNothing);
    expect(find.textContaining('强制共享模式'), findsOneWidget);
    expect(adapter.calls.any((r) => r.method == 'PUT'), false);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'unknown age explains missing birth information and keeps server opt-in policy',
      (tester) async {
    adapter.forced = false;
    adapter.tier = 'unknown';
    await _pumpMe(tester);
    final toggle = tester
        .widget<Switch>(find.byKey(const ValueKey('family-summary-sharing')));
    expect(toggle.onChanged, isNotNull);
    expect(toggle.value, false);
    expect(find.textContaining('请先补齐出生年月'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'failed privacy read leaves the switch disabled instead of assuming sharing',
      (tester) async {
    adapter.forced = false;
    adapter.fail = true;
    await _pumpMe(tester);
    final toggle = tester
        .widget<Switch>(find.byKey(const ValueKey('family-summary-sharing')));
    expect(toggle.onChanged, isNull);
    expect(find.textContaining('共享设置读取失败'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
