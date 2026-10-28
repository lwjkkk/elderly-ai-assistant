import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:elderly_ai_assistant/pages/tabs/vital_draft_page.dart';
import 'package:elderly_ai_assistant/services/api.dart';
import 'package:elderly_ai_assistant/widgets/answer_evidence.dart';

const _readyDraft = <String, dynamic>{
  'session_id': 19,
  'elder_id': 3,
  'subject_label': '本人',
  'subject_confirmed': true,
  'version': 1,
  'status': 'ready',
  'can_confirm': true,
  'question': '信息已齐全，请确认保存。',
  'draft': {
    'type': 'bp',
    'systolic': 130,
    'diastolic': 80,
    'unit': 'mmHg',
    'measured_at': '2026-10-22T08:00:00Z',
    'raw_text': '今天八点血压130/80',
  },
};

class _DraftAdapter implements HttpClientAdapter {
  final calls = <RequestOptions>[];
  bool failConfirm = false;
  bool failRestore = false;
  int patchStatus = 200;
  Map<String, dynamic> response = _readyDraft;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream,
      Future<void>? cancel) async {
    calls.add(options);
    if (options.method == 'PATCH') {
      final body = options.data is Map
          ? Map<String, dynamic>.from(options.data as Map)
          : Map<String, dynamic>.from(jsonDecode(options.data as String));
      final result = Map<String, dynamic>.from(response);
      result['version'] = ((body['version'] as num?)?.toInt() ?? 0) + 1;
      for (final key in ['subject_confirmed', 'subject_label']) {
        if (body.containsKey(key)) result[key] = body[key];
      }
      final draft = Map<String, dynamic>.from(result['draft'] as Map);
      for (final key in [
        'type',
        'systolic',
        'diastolic',
        'value',
        'measurement_context',
        'measured_at'
      ]) {
        if (body.containsKey(key)) draft[key] = body[key];
      }
      result['draft'] = draft;
      return ResponseBody.fromString(jsonEncode(result), patchStatus, headers: {
        Headers.contentTypeHeader: ['application/json']
      });
    }
    if ((failConfirm && options.path.endsWith('/confirm')) ||
        (failRestore &&
            options.method == 'GET' &&
            options.path.contains('/draft-conversations/'))) {
      return ResponseBody.fromString('{"detail":"服务暂不可用"}', 500, headers: {
        Headers.contentTypeHeader: ['application/json']
      });
    }
    final data = options.path.endsWith('/confirm')
        ? {
            'session_id': 19,
            'status': 'confirmed',
            'confirmed_vital_id': 71,
            'notification_status': 'recorded',
          }
        : options.path.endsWith('/draft-conversations') ||
                options.path.endsWith('/draft-conversations/19')
            ? response
            : {'id': 100};
    return ResponseBody.fromString(jsonEncode(data), 200, headers: {
      Headers.contentTypeHeader: ['application/json']
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _DraftAdapter adapter;
  setUp(() {
    adapter = _DraftAdapter();
    ApiService.dio.httpClientAdapter = adapter;
    SharedPreferences.setMockInitialValues({'role': 'elder', 'user_id': 3});
  });

  Future<void> size(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> openDraft(WidgetTester tester) async {
    await size(tester);
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                              builder: (_) => const VitalDraftPage(
                                  initialText: '今天八点血压130/80'))),
                      child: const Text('打开草稿')),
                ))));
    await tester.tap(find.text('打开草稿'));
    await tester.pumpAndSettle();
  }

  testWidgets('draft opens without saving and can be resumed after leaving',
      (tester) async {
    await openDraft(tester);
    expect(find.text('信息已齐全，请确认保存。'), findsOneWidget);
    expect(find.text('测量时间：2026-10-22 16:00:00'), findsOneWidget);
    expect(
        adapter.calls
            .any((r) => r.path.endsWith('/confirm') || r.path == '/api/vitals'),
        isFalse);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开草稿'));
    await tester.pumpAndSettle();
    expect((adapter.calls.last.data as Map)['session_id'], 19);
    expect(
        adapter.calls.any((r) =>
            r.method == 'GET' &&
            r.path == '/api/vitals/draft-conversations/19'),
        isTrue);
    expect(adapter.calls.any((r) => r.path.endsWith('/confirm')), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed confirm retains draft and a later retry clears it',
      (tester) async {
    await openDraft(tester);
    adapter.failConfirm = true;
    await tester.tap(find.text('核对无误，确认保存'));
    await tester.pumpAndSettle();
    expect(find.byType(VitalDraftPage), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('vital_draft_elder_3_3'), isNotNull);
    adapter.failConfirm = false;
    await tester.tap(find.text('核对无误，确认保存'));
    await tester.pumpAndSettle();
    expect(find.text('提醒已在服务端记录，尚未确认手机送达。'), findsOneWidget);
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    expect(find.byType(VitalDraftPage), findsNothing);
    expect(prefs.getString('vital_draft_elder_3_3'), isNull);
    expect(adapter.calls.where((r) => r.path.endsWith('/confirm')).length, 2);
  });

  testWidgets(
      'cancel uses server cancellation and clears only the current draft',
      (tester) async {
    await openDraft(tester);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('vital_draft_elder_8_8', 'other-account');
    await tester.tap(find.text('取消并丢弃草稿'));
    await tester.pumpAndSettle();
    expect(adapter.calls.last.method, 'DELETE');
    expect(adapter.calls.last.path, '/api/vitals/draft-conversations/19');
    expect(prefs.getString('vital_draft_elder_3_3'), isNull);
    expect(prefs.getString('vital_draft_elder_8_8'), 'other-account');
    expect(adapter.calls.any((r) => r.path.endsWith('/confirm')), isFalse);
  });

  testWidgets(
      'unsynchronized cached draft cannot be confirmed after restore fails',
      (tester) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('vital_draft_elder_3_3', jsonEncode(_readyDraft));
    adapter.failRestore = true;
    await size(tester);
    await tester.pumpWidget(const MaterialApp(home: VitalDraftPage()));
    await tester.pumpAndSettle();
    final button = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, '核对无误，确认保存'));
    expect(button.onPressed, isNull);
    expect(prefs.getString('vital_draft_elder_3_3'), isNotNull);
    expect(adapter.calls.any((r) => r.path.endsWith('/confirm')), isFalse);
  });

  testWidgets('evidence displays exact returned document and excerpt',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: AnswerEvidence(data: {
      'sources': [
        {
          'title': '血压测量指导',
          'source': 'health/bp.txt',
          'document_id': 'bp-guide-v2',
          'chunk_id': 'bp:2',
          'document_version': '2.1',
          'source_url': 'https://example.org/bp-guide',
          'updated_at': '2026-10-20',
          'region': '中国大陆',
          'excerpt': '测量前安静休息。'
        }
      ],
    }))));
    await tester.tap(find.text('查看知识库依据'));
    await tester.pumpAndSettle();
    expect(find.text('血压测量指导'), findsOneWidget);
    expect(find.textContaining('文档：health/bp.txt'), findsNothing);
    expect(find.textContaining('段落：bp:2'), findsNothing);
    expect(find.textContaining('测量前安静休息。'), findsOneWidget);
    expect(find.textContaining('文档编号：bp-guide-v2'), findsNothing);
    expect(find.textContaining('文档版本：2.1'), findsNothing);
    expect(find.textContaining('适用地区：中国大陆'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '查看原始来源'), findsOneWidget);
    expect(find.textContaining('更新时间：2026-10-20'), findsOneWidget);
  });

  testWidgets('unsupported time editing keeps the dialog open without saving',
      (tester) async {
    await openDraft(tester);
    adapter.patchStatus = 405;
    await tester.tap(find.text('修改数值和时间'));
    await tester.pumpAndSettle();
    final fields = find.descendant(
        of: find.byType(AlertDialog), matching: find.byType(TextField));
    await tester.enterText(fields.last, '2026-10-22 09:30:00');
    await tester.tap(find.text('校验修改'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('暂不支持'), findsOneWidget);
    expect(adapter.calls.where((r) => r.method == 'PATCH').length, 1);
    expect(
        adapter.calls
            .where((r) => r.path.endsWith('/draft-conversations'))
            .length,
        1);
    expect(adapter.calls.any((r) => r.path.endsWith('/confirm')), isFalse);
    await tester.tap(find.text('返回'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty evidence keeps safety guidance without a fake source card',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: AnswerEvidence(data: {
      'sources': [],
      'answer_footer': {
        'references': {'visible': false, 'items': []},
        'safety_notice': '健康科普参考，不能替代医生面诊。',
      },
    }))));
    expect(find.text('健康科普参考，不能替代医生面诊。'), findsOneWidget);
    expect(find.text('未找到可核验的知识库依据'), findsNothing);
    expect(find.text('查看知识库依据'), findsNothing);
    expect(find.byType(ExpansionTile), findsNothing);
    expect(find.byType(TextButton), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ambiguous subject must be explicitly confirmed before saving',
      (tester) async {
    adapter.response = {
      ..._readyDraft,
      'version': 4,
      'subject_confirmed': false,
      'subject_label': '妈妈',
    };
    await openDraft(tester);
    var confirm = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, '核对无误，确认保存'));
    expect(confirm.onPressed, isNull);
    expect(find.text('口述识别对象：妈妈'), findsOneWidget);
    await tester.tap(find.textContaining('我已确认这条记录属于本人'));
    await tester.pumpAndSettle();
    final patch = adapter.calls.last;
    expect(patch.method, 'PATCH');
    expect((patch.data as Map)['version'], 4);
    expect((patch.data as Map)['subject_confirmed'], isTrue);
    confirm = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, '核对无误，确认保存'));
    expect(confirm.onPressed, isNotNull);
  });

  testWidgets('choosing now sends UTC time and an IANA timezone',
      (tester) async {
    await openDraft(tester);
    await tester.tap(find.text('修改数值和时间'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('测量时间就是现在'));
    await tester.tap(find.text('校验修改'));
    await tester.pumpAndSettle();
    final patch = adapter.calls.last;
    final body = Map<String, dynamic>.from(patch.data as Map);
    expect(body['timezone'], 'UTC');
    expect(body['measured_at'], endsWith('Z'));
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
