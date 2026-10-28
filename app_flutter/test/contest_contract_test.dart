import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:elderly_ai_assistant/services/api.dart';
import 'package:elderly_ai_assistant/services/contest_answer.dart';
import 'package:elderly_ai_assistant/widgets/answer_evidence.dart';

class _ContestAdapter implements HttpClientAdapter {
  final calls = <RequestOptions>[];
  int tieredStatus = 200;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream,
      Future<void>? cancel) async {
    calls.add(options);
    var status = 200;
    Object data = <String, dynamic>{};
    if (options.path == '/api/chat/tiered') {
      status = tieredStatus;
      data = status == 200
          ? {
              'parts': {'conclusion': '关注测量趋势'},
              'view': {'conclusion': '关注测量趋势'}
            }
          : {'detail': '模拟服务错误'};
    } else if (options.path == '/api/chat') {
      data = {'answer': '旧版本回答', 'sources': []};
    } else if (options.path == '/api/vitals/alerts') {
      data = [];
    } else if (options.path == '/api/vitals/draft-conversations') {
      data = {'session_id': 19, 'status': 'collecting', 'can_confirm': false};
    }
    return ResponseBody.fromString(jsonEncode(data), status, headers: {
      Headers.contentTypeHeader: ['application/json']
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _ContestAdapter adapter;
  setUp(() {
    adapter = _ContestAdapter();
    ApiService.dio.httpClientAdapter = adapter;
    SharedPreferences.setMockInitialValues({
      'role': 'family',
      'token': 'test-token',
      'user_id': 3,
      'elder_id': 7,
    });
  });

  test('spoken drafts and alerts preserve explicit self versus elder ownership',
      () async {
    await ApiService.spokenVitalTurn('血压130/80', mine: true);
    await ApiService.spokenVitalTurn('今天上午八点', sessionId: 19, mine: false);
    await ApiService.vitalAlerts(mine: true);
    await ApiService.vitalAlerts(mine: false);
    expect(adapter.calls[0].data, {'text': '血压130/80'});
    expect(adapter.calls[1].data,
        {'text': '今天上午八点', 'session_id': 19, 'elder_id': 7});
    expect(adapter.calls[2].queryParameters.containsKey('elder_id'), isFalse);
    expect(adapter.calls[3].queryParameters['elder_id'], 7);
    expect(adapter.calls.where((r) => r.path == '/api/vitals'), isEmpty);
  });

  test('confirm and cancel target only their draft session endpoints',
      () async {
    await ApiService.confirmVitalDraft(19);
    await ApiService.cancelVitalDraft(20);
    expect(adapter.calls.map((r) => '${r.method} ${r.path}'), [
      'POST /api/vitals/draft-conversations/19/confirm',
      'DELETE /api/vitals/draft-conversations/20',
    ]);
    expect(adapter.calls.first.headers['Idempotency-Key'],
        'vital-draft-confirm-19');
  });

  test('structured edits use draft PATCH without posting a saved vital',
      () async {
    const fields = <String, dynamic>{
      'version': 4,
      'type': 'bs',
      'value': 6.2,
      'unit': 'mmol/L',
      'measured_at': '2026-10-22 08:30:00',
      'measurement_context': 'fasting',
      'timezone': 'Asia/Shanghai',
    };
    await ApiService.updateVitalDraft(19, fields);
    expect(adapter.calls.single.method, 'PATCH');
    expect(adapter.calls.single.path, '/api/vitals/draft-conversations/19');
    expect(adapter.calls.single.data, fields);
  });

  test('unbound elder mode cannot silently post to family self', () async {
    SharedPreferences.setMockInitialValues({'role': 'family', 'user_id': 3});
    await expectLater(ApiService.spokenVitalTurn('血压130/80', mine: false),
        throwsA(isA<StateError>()));
    expect(
        adapter.calls.any((r) => r.path == '/api/vitals/draft-conversations'),
        isFalse);
  });

  test('tiered endpoint only falls back for an unavailable endpoint', () async {
    adapter.tieredStatus = 404;
    final answer = await ApiService.tieredChat('血压记录怎样查看');
    expect(answer['answer'], '旧版本回答');
    expect(adapter.calls.map((r) => r.path), ['/api/chat/tiered', '/api/chat']);
    adapter.calls.clear();
    adapter.tieredStatus = 500;
    await expectLater(
        ApiService.tieredChat('血压记录怎样查看'), throwsA(isA<DioException>()));
    expect(adapter.calls.map((r) => r.path), ['/api/chat/tiered']);
  });

  test('vital measurement routing leaves questions in health Q and A', () {
    expect(looksLikeVitalRecord('今天八点血压130/80'), isTrue);
    expect(looksLikeVitalRecord('我的空腹血糖6.2'), isTrue);
    expect(looksLikeVitalRecord('我的血压130/80正常吗？'), isFalse);
    expect(looksLikeVitalRecord('如何记录血压'), isFalse);
    expect(looksLikeVitalRecord('微信怎么加好友'), isFalse);
  });

  test('answer format preserves supplied urgent care and old response text',
      () {
    const parts = {'conclusion': '重点', 'advice': '行动', 'seek': '立即拨打120'};
    final result = answerText({'view': parts, 'parts': parts});
    expect(result, contains('立即拨打120'));
    expect(result, contains('关注什么'));
    expect(answerText({'answer': '旧版回答'}), '旧版回答');
    expect(answerSources({'sources': null}), isEmpty);
    expect(decodeAnswer('不是 JSON'), isEmpty);
  });

  test('tiered parts keep original answer without duplicated legacy steps', () {
    final text = answerText({
      'elder_view': {
        'concern': '关注血压变化',
        'meaning': '目前需要结合连续测量判断',
        'next_step': '安静休息后复测',
        'seek': '出现胸痛时及时就医',
      },
      'family_view': {
        'concern': '详版关注点',
        'meaning': '详版解释',
        'next_step': '详版下一步',
        'seek': '详版就医提醒',
      },
      'answer': '完整回答原文',
      'steps': ['先休息', '再复测'],
      'disclaimer': '仅供健康参考',
    });
    expect(text, contains('关注什么\n关注血压变化'));
    expect(text, contains('下一步怎么办\n安静休息后复测'));
    expect(text, isNot(contains('步骤：')));
    expect(text, isNot(contains('先休息')));
    expect(text, isNot(contains('仅供健康参考')));
    expect(answerOriginalText({'answer': '完整回答原文'}), '完整回答原文');
    expect(
        answerText({
          'family_view': {'concern': '详版关注点'}
        }, detailed: true),
        contains('详版关注点'));
  });

  test('new answer safety fields map to plain language without enum leakage',
      () {
    expect(answerFallbackLabel({'fallback_reason': 'medication_boundary'}),
        '个人用药决策需医生或药师确认');
    expect(answerFallbackLabel({'fallback_reason': 'future_reason'}), '');
    expect(answerOriginLabel({'answer_origin': 'safety_rule'}), '安全规则提示');
    final sections = answerEmergencySections({
      'elder_view': {'next_step': '立即拨打120', 'seek': '不要等待，请立即急诊'},
      'family_view': {'next_step': '家属陪同拨打120', 'seek': '马上急诊'},
      'emergency_types': ['choking', 'future_signal'],
    });
    expect(sections['action'], '立即拨打120');
    expect(sections['seek'], '不要等待，请立即急诊');
    expect(
        answerEmergencyTypeLabels({
          'emergency_types': ['choking', 'future_signal']
        }),
        ['气道梗阻相关危险信号', '紧急情况']);
  });

  testWidgets(
      'evidence shows excerpts without diagnostic prose or unsafe links',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: AnswerEvidence(data: {
      'evidence_status': 'insufficient',
      'evidence_notice': '这项资料尚未完成复核。',
      'fallback_reason': 'no_relevant_chunks',
      'sources': [
        {
          'title': '血压测量参考',
          'evidence_role': 'retrieved_reference',
          'verification_status': 'unverified',
          'source_url': 'javascript:alert(1)',
          'vector_score': 0.97,
          'excerpt': '安静休息后复测。',
          'platform': 'Android',
          'region': '全国',
        }
      ],
    }))));
    expect(find.text('查看知识库依据'), findsOneWidget);
    expect(find.text('参考资料尚待核验'), findsNothing);
    expect(find.text('这项资料尚未完成复核。'), findsNothing);
    expect(find.text('补充说明：未找到直接相关片段'), findsNothing);
    await tester.tap(find.text('查看知识库依据'));
    await tester.pumpAndSettle();
    expect(find.text('血压测量参考'), findsOneWidget);
    expect(find.text('安静休息后复测。'), findsOneWidget);
    expect(find.textContaining('尚未完成复核'), findsNothing);
    expect(find.textContaining('适用平台：Android'), findsOneWidget);
    expect(find.textContaining('0.97'), findsNothing);
    expect(find.text('查看原始来源'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('emergency banner keeps full action and seek visible',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: AnswerEmergencyBanner(
      data: {
        'answer': '完整回答包含紧急下一步和其他说明。',
        'elder_view': {
          'next_step': '停止进食并立即联系急救人员，保持呼吸道通畅。',
          'seek': '立即拨打120，不要等待症状自行缓解。',
        },
        'emergency_types': ['choking'],
      },
      fallbackText: '紧急情况',
    ))));
    expect(find.text('立即求助'), findsOneWidget);
    expect(find.textContaining('提醒类别：气道梗阻相关危险信号'), findsOneWidget);
    expect(find.textContaining('保持呼吸道通畅'), findsOneWidget);
    expect(find.textContaining('不要等待症状自行缓解'), findsOneWidget);
    expect(find.text('查看完整回答原文'), findsOneWidget);
    await tester.tap(find.text('查看完整回答原文'));
    await tester.pumpAndSettle();
    expect(find.text('完整回答包含紧急下一步和其他说明。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
