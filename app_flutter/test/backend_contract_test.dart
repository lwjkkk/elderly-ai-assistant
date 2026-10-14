import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:elderly_ai_assistant/services/api.dart';
import 'package:elderly_ai_assistant/pages/tabs/me_tab.dart';
import 'package:elderly_ai_assistant/pages/tabs/report_details.dart';

class _ContractAdapter implements HttpClientAdapter {
  final calls = <RequestOptions>[];
  bool sharing = false;
  bool failPrivacy = false;
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream,
      Future<void>? cancel) async {
    calls.add(options);
    final path = Uri.parse(options.path).path;
    if (path.contains('/image/') || path.contains('/audio/')) {
      return ResponseBody.fromBytes([1, 2, 3], 200,
          headers: {
            Headers.contentTypeHeader: ['application/octet-stream']
          });
    }
    if (path == '/api/privacy') {
      if (options.method == 'PUT') {
        if (failPrivacy)
          return ResponseBody.fromString('{"detail":"服务暂不可用"}', 500, headers: {
            Headers.contentTypeHeader: ['application/json']
          });
        sharing = options.data['sync_summary_to_family'] == true;
      }
      return ResponseBody.fromString(
          jsonEncode({'sync_summary_to_family': sharing}), 200,
          headers: {
            Headers.contentTypeHeader: ['application/json']
          });
    }
    return ResponseBody.fromString(
        path == '/api/vitals' && options.method == 'POST' ? '{}' : '[]', 200,
        headers: {
          Headers.contentTypeHeader: ['application/json']
        });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _ContractAdapter adapter;
  setUp(() {
    adapter = _ContractAdapter();
    ApiService.dio.httpClientAdapter = adapter;
    SharedPreferences.setMockInitialValues(
        {'role': 'elder', 'token': 'test-token', 'sync_to_family': true});
  });
  test('family self and elder view use separate request ownership', () async {
    SharedPreferences.setMockInitialValues(
        {'role': 'family', 'token': 'test-token', 'elder_id': 7});
    await ApiService.vitalsList(mine: true);
    await ApiService.vitalsList(mine: false);
    await ApiService.reportList(mine: true);
    expect(adapter.calls[0].queryParameters.containsKey('elder_id'), false);
    expect(adapter.calls[1].queryParameters['elder_id'], 7);
    expect(adapter.calls[2].queryParameters.containsKey('elder_id'), false);
  });
  test('unbound family cannot silently read own data as elder data', () async {
    SharedPreferences.setMockInitialValues(
        {'role': 'family', 'token': 'test-token'});
    await expectLater(ApiService.vitalsList(), throwsA(isA<StateError>()));
    expect(adapter.calls.any((r) => r.path == '/api/vitals'), false);
  });
  test('protected media sends bearer header, never token in URL', () async {
    expect(await ApiService.reportImageBytes('/api/reports/image/a.png'),
        [1, 2, 3]);
    expect(await ApiService.consultAudioBytes('/api/consults/audio/a.m4a'),
        [1, 2, 3]);
    for (final call in adapter.calls) {
      expect(call.headers['Authorization'], 'Bearer test-token');
      expect(call.path.contains('test-token'), false);
    }
    expect(ApiService.audioMimeType('/api/consults/audio/a.m4a'), 'audio/mp4');
  });
  test('file credentials are not sent to another server', () async {
    await expectLater(
        ApiService.reportImageBytes(
            'https://example.org/api/reports/image/a.png'),
        throwsA(isA<StateError>()));
    expect(adapter.calls, isEmpty);
  });
  test('new vitals constraints reject invalid data before posting', () async {
    await expectLater(
        ApiService.addVital(type: 'bp', systolic: 80, diastolic: 120),
        throwsA(isA<StateError>()));
    await expectLater(ApiService.addVital(type: 'weight', value: 2),
        throwsA(isA<StateError>()));
    await expectLater(ApiService.addVital(type: 'bs', value: double.nan),
        throwsA(isA<StateError>()));
    expect(adapter.calls, isEmpty);
    await ApiService.addVital(type: 'bp', systolic: 120, diastolic: 80);
    expect(adapter.calls.single.path, '/api/vitals');
  });
  testWidgets(
      'report displays backend statuses without inferring normal from advice',
      (tester) async {
    final report = <String, dynamic>{
      'advice_text': '均正常',
      'metrics': [
        {'code': 'TC', 'result': 6.2, 'lo': 2.8, 'hi': 5.2, 'status': 'high'},
        {
          'code': 'GLU',
          'result': 5.1,
          'lo': 3.9,
          'hi': 6.1,
          'status': 'normal'
        },
        {'code': 'ALT', 'result': 20, 'status': 'unparsed'},
      ]
    };
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: ReportMetrics(report: report))));
    expect(find.text('偏高'), findsOneWidget);
    expect(find.text('正常'), findsOneWidget);
    expect(find.text('待核对'), findsOneWidget);
    expect(reportMetricSummary(report), '1 项偏高或偏低，1 项待核对');
    expect(reportMetricSummary({'advice_text': '均正常', 'metrics': []}), '未能核对');
    expect(tester.takeException(), isNull);
  });
  testWidgets('privacy uses backend value and preserves it on failed save',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: MeTab(role: 'elder'))));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final switchFinder = find.byKey(const ValueKey('family-summary-sharing'));
    expect(tester.widget<Switch>(switchFinder).value, true);
    adapter.failPrivacy = true;
    tester.widget<Switch>(switchFinder).onChanged!(false);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.widget<Switch>(switchFinder).value, true);
    adapter.failPrivacy = false;
    tester.widget<Switch>(switchFinder).onChanged!(false);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.widget<Switch>(switchFinder).value, false);
    expect(
        adapter.calls
            .where((r) => r.method == 'PUT')
            .last
            .data['sync_summary_to_family'],
        true);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
