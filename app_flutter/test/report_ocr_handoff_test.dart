import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:elderly_ai_assistant/pages/tabs/report_details.dart';
import 'package:elderly_ai_assistant/services/api.dart';
import 'package:elderly_ai_assistant/services/report_job_tracker.dart';
import 'package:elderly_ai_assistant/services/report_retake.dart';
import 'package:elderly_ai_assistant/widgets/report_job_upload_panel.dart';

const retakePayload = <String, dynamic>{
  'detail': '识别证据不足',
  'code': 'report_retake_required',
  'retake_required': true,
  'retake': {
    'required': true,
    'message': '请摆正报告重新拍摄',
    'requirements': ['请保留表头'],
  },
};

class _ReportAdapter implements HttpClientAdapter {
  int uploadCode = 202;
  Map<String, dynamic> uploadBody = retakePayload;
  Map<String, dynamic> job = {
    'job_id': 'job-retake',
    'status': 'failed',
    ...retakePayload,
    'report': null,
    'metrics': [
      {'code': 'ALT', 'result': null, 'status': 'unparsed'}
    ],
  };
  final calls = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream,
      Future<void>? cancelFuture) async {
    calls.add(options);
    final uploading = options.method == 'POST';
    final body = uploading
        ? uploadCode == 202
            ? {
                'job_id': 'job-retake',
                'status': 'queued',
                'poll_after_ms': 1000
              }
            : uploadBody
        : job;
    return ResponseBody.fromString(
        jsonEncode(body), uploading ? uploadCode : 200,
        headers: {
          Headers.contentTypeHeader: ['application/json']
        });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late _ReportAdapter adapter;
  setUp(() {
    SharedPreferences.setMockInitialValues(
        {'role': 'elder', 'user_id': 3, 'token': 'test-token'});
    adapter = _ReportAdapter();
    ApiService.dio.httpClientAdapter = adapter;
  });

  test('synchronous 422 is typed only for explicit retake metadata', () async {
    adapter.uploadCode = 422;
    await expectLater(
        ApiService.uploadReport([1, 2], 'report.png', mine: true),
        throwsA(isA<ReportRetakeException>()
            .having((e) => e.retake.message, 'message', '请摆正报告重新拍摄')));
    adapter.uploadBody = {'detail': '参数无效'};
    await expectLater(ApiService.uploadReport([1, 2], 'report.png', mine: true),
        throwsA(isA<DioException>()));
    for (final code in [400, 401, 403, 500, 503]) {
      final error = DioException(
          requestOptions: RequestOptions(),
          response: Response(
              requestOptions: RequestOptions(),
              statusCode: code,
              data: retakePayload));
      expect(ReportRetake.fromError(error, 'upload'), isNull);
    }
    expect(
        ReportRetake.fromError(
            DioException.connectionTimeout(
                timeout: const Duration(seconds: 1),
                requestOptions: RequestOptions()),
            'upload'),
        isNull);
  });

  test('submission retake and generic service errors remain distinct',
      () async {
    final tracker = ReportJobTracker(mine: true);
    addTearDown(tracker.dispose);
    adapter.uploadCode = 422;
    await tracker.submit([1], 'a.jpg');
    expect(tracker.retakes.single.message, '请摆正报告重新拍摄');
    expect(tracker.jobs, isEmpty);
    tracker.consumeRetake(tracker.retakes.single);
    adapter.uploadCode = 503;
    adapter.uploadBody = {'detail': '服务暂不可用'};
    await tracker.submit([1], 'a.jpg');
    expect(tracker.retakes, isEmpty);
    expect(tracker.submissionError, '服务暂不可用');
  });

  testWidgets('failed retake wins over success and never calls onReportSaved',
      (tester) async {
    var saved = 0;
    final tracker = ReportJobTracker(mine: true, onReportSaved: () => saved++);
    await tester.runAsync(() => tracker.submit([1], 'a.jpg'));
    // Inconsistent success metadata must not override the explicit retake gate.
    adapter.job = {
      ...adapter.job,
      'status': 'completed',
      'report': {'id': 42}
    };
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1100)));
    expect(tracker.retakes.single.id, 'job-retake');
    expect(saved, 0);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ReportJobStatusCard(
                job: adapter.job, onOpenReport: (_) => saved++))));
    expect(find.text('识别未完成，请重新拍摄'), findsOneWidget);
    expect(find.text('查看已保存报告'), findsNothing);
    expect(find.textContaining('没有生成已保存报告'), findsWidgets);
    expect(find.text('待核对'), findsOneWidget);
    tracker.dispose();
  });

  testWidgets('retake dialog occurs once across rebuild and task restore',
      (tester) async {
    final scope = await ReportJobStore.keyForScope(mine: true);
    await ReportJobStore.add(scope, 'job-retake');
    Widget panel() => const MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: ReportJobUploadPanel(
                    mine: true, primary: Colors.blue, soft: Colors.white))));
    await tester.pumpWidget(panel());
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('重新拍摄'), findsOneWidget);
    expect(find.text('重新选择图片'), findsOneWidget);
    expect(find.textContaining('原件没有的字段无需补造'), findsOneWidget);
    await tester.tap(find.text('稍后处理'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('拍照上传'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(panel());
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(await ReportJobStore.claimRetake(scope, 'job-retake'), isFalse);
    SharedPreferences.setMockInitialValues(
        {'role': 'family', 'user_id': 4, 'elder_id': 7});
    final otherScope = await ReportJobStore.keyForScope(mine: false);
    expect(await ReportJobStore.claimRetake(otherScope, 'job-retake'), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'retake actions return chosen source without opening camera on close',
      (tester) async {
    ImageSource? selected;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () async {
                      selected = await showReportRetakeDialog(context,
                          ReportRetake.fromPayload(retakePayload, 'sync')!);
                    },
                    child: const Text('打开'))))));
    for (final pair in [
      ('重新拍摄', ImageSource.camera),
      ('重新选择图片', ImageSource.gallery)
    ]) {
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(pair.$1));
      await tester.pumpAndSettle();
      expect(selected, pair.$2);
    }
  });

  testWidgets(
      'partial and bound results retain text, units, and server review state',
      (tester) async {
    const report = <String, dynamic>{
      'recognition_status': 'partial',
      'ocr_details': {
        'coverage': {
          'complete_report_verified': false,
          'findings': [
            {'message': '分组留白可能是空行，请核对'}
          ]
        }
      },
      'metrics': [
        {
          'code': 'CRP',
          'result': '<0.2',
          'result_value': null,
          'range_text': '0～10',
          'status': 'normal',
          'comparison_status': 'unverified_bound',
          'verification_reason': '单位尚未核对',
          'unit': 'mg/L',
          'unit_raw': 'mg/l',
          'bound_comparison': {'certain': true, 'note': '数学比较唯一不表示已核对所有字段'}
        },
        {
          'code': '指数',
          'result': '(-)',
          'status': 'unparsed',
          'needs_review': true
        },
        {
          'code': '未知',
          'result': null,
          'result_text': '乱码候选',
          'status': 'unparsed'
        },
        {
          'code': 'LOW',
          'result': '<3',
          'status': 'low',
          'comparison_status': 'certain_low',
          'range_text': '3～6',
          'unit': 'mmol/L'
        },
      ],
    };
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body:
                SingleChildScrollView(child: ReportMetrics(report: report)))));
    expect(find.text('部分项目待核对'), findsOneWidget);
    expect(find.text('CRP  <0.2 mg/L'), findsOneWidget);
    expect(find.text('指数  (-)'), findsOneWidget);
    expect(find.text('未知  —'), findsOneWidget);
    expect(find.text('识别原文，待核对：乱码候选'), findsOneWidget);
    expect(find.text('待核对'), findsNWidgets(3));
    expect(find.text('偏低'), findsOneWidget);
    expect(find.text('正常'), findsNothing);
    expect(find.text('参考范围：未能核对'), findsNWidgets(2));
    expect(find.text('参考范围：0～10 mg/L（待核对）'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('分组留白可能是空行，请核对'), findsOneWidget);
    await tester.tap(find.text('查看解析信息').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('单位识别原文：mg/l'), findsOneWidget);
    expect(find.textContaining('数学比较唯一'), findsOneWidget);
  });

  test('only original image coordinates are accepted for evidence overlays',
      () {
    final blocks = [
      {
        'polygon': [
          [10, 20],
          [100, 20],
          [100, 40],
          [10, 40]
        ]
      }
    ];
    final details = {
      'coordinate_space': 'original_image_pixels',
      'width': 200,
      'height': 300
    };
    expect(reportEvidencePolygons(details, blocks).single.first,
        const Offset(10, 20));
    expect(
        reportEvidencePolygons(
            {...details, 'coordinate_space': 'crop'}, blocks),
        isEmpty);
    expect(reportEvidencePolygons({'version': 'old'}, blocks), isEmpty);
    expect(reportEvidencePolygons({...details, 'width': 0}, blocks), isEmpty);
    expect(
        reportEvidencePolygons(details, [
          {
            'polygon': [
              [-1, 2],
              [3, 4],
              [5, 6]
            ]
          }
        ]),
        isEmpty);
  });
}
