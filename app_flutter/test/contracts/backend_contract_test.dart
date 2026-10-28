import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:elderly_ai_assistant/services/api.dart';
import 'package:elderly_ai_assistant/pages/profile/me_tab.dart';
import 'package:elderly_ai_assistant/pages/health/report_details.dart';
import 'package:elderly_ai_assistant/services/reports/report_job_tracker.dart';

class _ContractAdapter implements HttpClientAdapter {
  final calls = <RequestOptions>[];
  bool sharing = false;
  bool failPrivacy = false;
  int uploadStatusCode = 202;
  String uploadDetail = '报告任务较多';
  String? retryAfter;
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
    if (path == '/api/reports/jobs' && options.method == 'POST') {
      if (uploadStatusCode != 202) {
        return ResponseBody.fromString(
            jsonEncode({'detail': uploadDetail}), uploadStatusCode,
            headers: {
              Headers.contentTypeHeader: ['application/json'],
              if (retryAfter != null) 'retry-after': [retryAfter!],
            });
      }
      return ResponseBody.fromString(
          jsonEncode(
              {'job_id': 'job-1', 'status': 'queued', 'poll_after_ms': 1500}),
          202,
          headers: {
            Headers.contentTypeHeader: ['application/json']
          });
    }
    if (path == '/api/reports/jobs/job-1') {
      return ResponseBody.fromString(
          jsonEncode(
              {'job_id': 'job-1', 'status': 'explaining', 'metrics': []}),
          200,
          headers: {
            Headers.contentTypeHeader: ['application/json']
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
  test('report jobs upload original multipart with correct elder scope',
      () async {
    SharedPreferences.setMockInitialValues(
        {'role': 'family', 'token': 'test-token', 'user_id': 3, 'elder_id': 7});
    final created =
        await ApiService.createReportJob([0xff, 0xd8, 0xff, 0xd9], 'check.jpg');
    final status = await ApiService.reportJobStatus('job-1');
    expect(created['job_id'], 'job-1');
    expect(status['status'], 'explaining');
    expect(adapter.calls.map((r) => '${r.method} ${r.path}'), [
      'POST /api/reports/jobs',
      'GET /api/reports/jobs/job-1',
    ]);
    final form = adapter.calls.first.data as FormData;
    expect(form.files.any((entry) => entry.key == 'file'), isTrue);
    expect(
        form.fields
            .any((entry) => entry.key == 'elder_id' && entry.value == '7'),
        isTrue);
    expect(adapter.calls.first.headers[Headers.contentTypeHeader],
        startsWith('multipart/form-data; boundary='));
  });
  test('report upload displays backend detail and Retry-After guidance',
      () async {
    SharedPreferences.setMockInitialValues(
        {'role': 'elder', 'token': 'test-token', 'user_id': 3});
    final tracker = ReportJobTracker(mine: true);
    adapter.uploadStatusCode = 400;
    adapter.uploadDetail = '报告图片格式不支持';
    await tracker.submit([1, 2, 3], 'report.jpg');
    expect(tracker.submissionError, '报告图片格式不支持');

    adapter.uploadStatusCode = 429;
    adapter.retryAfter = '17';
    await tracker.submit([1, 2, 3], 'report.jpg');
    expect(tracker.submissionError, contains('17 秒后'));
    tracker.dispose();
  });
  test('unfinished report jobs are stored separately by user and elder',
      () async {
    SharedPreferences.setMockInitialValues(
        {'role': 'family', 'user_id': 3, 'elder_id': 7});
    final self = await ReportJobStore.keyForScope(mine: true);
    final elder7 = await ReportJobStore.keyForScope(mine: false);
    await ApiService.setElderId(8);
    final elder8 = await ReportJobStore.keyForScope(mine: false);
    expect({self, elder7, elder8}.length, 3);
    expect(self, contains('_3_self'));
    expect(elder7, contains('_3_7'));
    expect(elder8, contains('_3_8'));
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
        {
          'code': 'ALT',
          'result': 20,
          'unit': 'U/L',
          'status': 'unparsed',
          'evidence_text': 'ALT 20 U/L',
          'verification_reason': '无法可靠识别参考范围',
          'parser_version': '2.2.0',
          'source_line': 7,
        },
      ]
    };
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: ReportMetrics(report: report))));
    expect(find.text('偏高'), findsOneWidget);
    expect(find.text('正常'), findsOneWidget);
    expect(find.text('待核对'), findsOneWidget);
    expect(find.text('ALT  20 U/L'), findsOneWidget);
    expect(find.text('查看原文依据'), findsOneWidget);
    await tester.tap(find.text('查看原文依据'));
    await tester.pumpAndSettle();
    expect(find.text('ALT的原文依据'), findsOneWidget);
    expect(find.textContaining('ALT 20 U/L'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(AlertDialog),
            matching: find.textContaining('核对说明：无法可靠识别参考范围')),
        findsOneWidget);
    expect(find.textContaining('解析版本：2.2.0'), findsOneWidget);
    expect(find.textContaining('原文行号：7'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(reportMetricSummary(report), '1 项偏高或偏低，1 项待核对');
    expect(reportMetricSummary({'advice_text': '均正常', 'metrics': []}), '未能核对');
    expect(tester.takeException(), isNull);
  });
  testWidgets('needs_review overrides a normal status and OCR warnings show',
      (tester) async {
    final report = <String, dynamic>{
      'ocr_details': {
        'warnings': ['图片偏暗，请核对小数点和数字'],
        'width': 1200,
        'height': 1600,
      },
      'metrics': [
        {
          'code': 'GLU',
          'result': 5.1,
          'status': 'normal',
          'needs_review': true,
          'ocr_confidence': 0.41,
          'verification_reason': '局部重识别与原始识别不一致',
        }
      ],
    };
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: ReportMetrics(report: report))));
    expect(find.text('待核对'), findsOneWidget);
    expect(find.text('正常'), findsNothing);
    expect(find.textContaining('图片偏暗'), findsOneWidget);
    expect(reportMetricSummary(report), '1 项待核对');
    expect(reportMetricColor(report), const Color(0xFF6B7280));
    await tester.tap(find.text('查看解析信息'));
    await tester.pumpAndSettle();
    expect(find.textContaining('OCR文字置信度：41%（不是医学准确率）'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(AlertDialog),
            matching: find.textContaining('局部重识别与原始识别不一致')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('failed report task labels partial metrics as unsaved',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: ReportJobStatusCard(job: {
      'job_id': 'job-1',
      'status': 'failed',
      'error': 'AI 解读失败',
      'metrics': [
        {'code': 'ALT', 'status': 'unparsed', 'needs_review': true}
      ],
    }))));
    expect(find.text('处理失败'), findsOneWidget);
    expect(find.textContaining('没有生成已保存报告'), findsOneWidget);
    expect(find.text('待核对'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('completed report task opens the saved report by report id',
      (tester) async {
    Map<String, dynamic>? opened;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ReportJobStatusCard(
      job: {
        'job_id': 'job-1',
        'status': 'completed',
        'report': {
          'id': 42,
          'created_at': '2026-10-24T10:00:00',
          'metrics': [],
          'ocr_text': '检查项目',
          'advice_text': '建议复查',
        },
      },
      onOpenReport: (report) => opened = report,
    ))));
    await tester.tap(find.text('查看已保存报告'));
    expect(opened?['id'], 42);
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
