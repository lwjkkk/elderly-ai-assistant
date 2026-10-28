import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:elderly_ai_assistant/pages/chat/chat_history_page.dart';
import 'package:elderly_ai_assistant/pages/tabs/hub_pages.dart';
import 'package:elderly_ai_assistant/services/api.dart';
import 'package:elderly_ai_assistant/services/chat/contest_answer.dart';
import 'package:elderly_ai_assistant/widgets/answer_evidence.dart';

class _FamilyAdapter implements HttpClientAdapter {
  int status = 200;
  List<Map<String, dynamic>> messages = [];
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream,
          Future<void>? cancel) async =>
      ResponseBody.fromString(
          jsonEncode(status == 200 ? messages : {'detail': '无权访问'}), status,
          headers: {
            Headers.contentTypeHeader: ['application/json']
          });
  @override
  void close({bool force = false}) {}
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(
      {'role': 'family', 'user_id': 4, 'token': 'test'}));
  test(
      'new emergency categories use server state without a frontend symptom classifier',
      () {
    for (final type in [
      'severe_headache',
      'severe_allergy',
      'emergency_other'
    ]) {
      expect(
          answerIsEmergency({
            'emergency': true,
            'emergency_types': [type]
          }),
          isTrue);
    }
    expect(
        answerIsEmergency({
          'triage': {'status': 'urgent'}
        }),
        isTrue);
    expect(
        answerNeedsUrgentReview({
          'triage': {'status': 'uncertain'},
          'urgent_review_required': true
        }),
        isTrue);
    expect(
        answerIsEmergency({
          'triage': {'status': 'uncertain'}
        }),
        isFalse);
  });

  testWidgets(
      'both emergency views retain 120 and notification queue is not delivery',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
      child: ChatHistoryAnswer(text: '原文', answerData: {
        'emergency': true,
        'emergency_types': ['severe_allergy'],
        'family_notification_status': 'queued',
        'elder_view': {'next_step': '老人提示：请立即联系身边人并拨打120', 'seek': '请勿等待'},
        'family_view': {'next_step': '家属提示：请立即协助拨打120', 'seek': '由急救人员评估'},
      }),
    ))));
    expect(find.text('立即求助'), findsOneWidget);
    expect(find.textContaining('老人提示'), findsOneWidget);
    expect(find.textContaining('不代表手机已送达'), findsOneWidget);
    await tester.tap(find.text('家属详版'));
    await tester.pumpAndSettle();
    expect(find.textContaining('家属提示：请立即协助拨打120'), findsOneWidget);
    expect(find.text('立即求助'), findsOneWidget);
  });

  testWidgets(
      'uncertain triage retains body and conditional help without green clearance',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: ChatHistoryAnswer(
      text: '无法核定紧急程度，请联系身边人或医生；若突然加重请拨打120。',
      answerData: {
        'answer': '无法核定紧急程度，请联系身边人或医生；若突然加重请拨打120。',
        'triage': {'status': 'uncertain'},
        'urgent_review_required': true
      },
    ))));
    expect(find.byType(AnswerUncertainBanner), findsOneWidget);
    expect(find.textContaining('若突然加重请拨打120'), findsOneWidget);
    expect(find.text('立即求助'), findsNothing);
    expect(find.textContaining('已排除风险'), findsNothing);
  });

  test(
      'family notification explanations cover denied disclosure and unbound users',
      () {
    expect(
        familyNotificationExplanation(
            {'family_notification_status': 'profile_incomplete'}),
        contains('未向家属披露'));
    expect(
        familyNotificationExplanation(
            {'family_notification_status': 'sharing_disabled'}),
        contains('未向家属披露'));
    expect(
        familyNotificationExplanation(
            {'family_notification_status': 'no_recipients'}),
        contains('授权家属'));
    expect(
        familyNotificationExplanation(
            {'family_notification_status': 'future_status'}),
        isEmpty);
  });

  Future<void> ticks(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(
        home: FamConversationPage(
            name: '测试长辈', storeKey: 'test_family', bindingId: 7)));
    await ticks(tester);
  }

  testWidgets(
      'authorized family receives server emergency labels; missed check-ins stay health cards',
      (tester) async {
    final adapter = _FamilyAdapter()
      ..messages = [
        {
          'id': 1,
          'sender_id': 3,
          'kind': 'emergency_alert',
          'content': {
            'emergency_labels': '服务端严重过敏警示',
            'question': '测试者模拟口述',
            'reported_question': '妈妈喘不上气，但没有胸痛，持续约10分钟',
            'advice': '请立即联系并拨打120'
          }
        },
        {
          'id': 2,
          'sender_id': 3,
          'kind': 'health',
          'content': {
            'type': 'medication_missed',
            'title': '用药未打卡提醒',
            'lines': ['超过60分钟未打卡，不代表实际未服药。']
          }
        },
      ];
    ApiService.dio.httpClientAdapter = adapter;
    await open(tester);
    expect(find.text('紧急情况提醒'), findsOneWidget);
    expect(find.textContaining('服务端严重过敏警示'), findsOneWidget);
    expect(find.text('原话：妈妈喘不上气，但没有胸痛，持续约10分钟'), findsOneWidget);
    expect(find.textContaining('老人提到：'), findsNothing);
    expect(find.text('用药未打卡提醒'), findsOneWidget);
    expect(find.textContaining('不代表实际未服药'), findsOneWidget);
    expect(find.textContaining('拨打120'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await ticks(tester);
  });

  testWidgets('revoked family access clears cached emergency health messages',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'role': 'family',
      'user_id': 4,
      'token': 'test',
      'test_family': jsonEncode([
        {
          'isMe': false,
          'kind': 'emergency_alert',
          'title': '私密旧消息',
          'lines': ['旧健康内容']
        }
      ])
    });
    ApiService.dio.httpClientAdapter = _FamilyAdapter()..status = 403;
    await open(tester);
    expect(find.text('私密旧消息'), findsNothing);
    expect(find.text('旧健康内容'), findsNothing);
    expect(find.textContaining('绑定不允许查看'), findsOneWidget);
    expect((await SharedPreferences.getInstance()).getString('test_family'),
        isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await ticks(tester);
  });

  testWidgets('all risk groups keep reported details verbatim in both views',
      (tester) async {
    const cases = [
      ('chest_pain', '胸部不适相关危险信号', '我心脏疼'),
      ('chest_pain', '胸部不适相关危险信号', '我胸闷'),
      ('chest_pain', '胸部不适相关危险信号', '我今天心口像石头压着，但不是胸闷'),
      ('breath', '呼吸相关危险信号', '我妈妈走两步就喘不上气，没有心脏疼'),
      ('consciousness', '意识或晕厥相关危险信号', '刚才晕过去了，现在醒了，持续约10秒'),
      ('stroke', '卒中相关危险信号', '爸爸左胳膊突然抬不起，右边没事'),
      ('bleeding', '出血相关危险信号', '鼻血一直流，不是只有一点血丝'),
      ('choking', '气道梗阻相关危险信号', '吃饭时喉咙卡住了，说不出话'),
      ('severe_headache', '头痛相关危险信号', '这次头疼程度8分，和以前轻微头疼不一样'),
      ('severe_allergy', '过敏相关危险信号', '舌头迅速肿了，吞咽困难，没有皮疹'),
      ('emergency_other', '其他需立即求助的危险信号', '说不上具体位置，但现在越来越难受'),
    ];
    for (final (type, label, question) in cases) {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
        child: ChatHistoryAnswer(
            key: ValueKey(question),
            text: '请立即拨打120',
            answerData: {
              'emergency': true,
              'emergency_types': [type],
              'reported_question': question,
              'emergency_labels': [label],
              'elder_view': const {'next_step': '请立即拨打120', 'seek': '联系身边人协助'},
              'family_view': const {
                'next_step': '请立即协助拨打120',
                'seek': '不要独自驾车'
              },
            }),
      ))));
      expect(find.text('您描述：$question'), findsOneWidget);
      expect(find.text('提醒类别：$label'), findsOneWidget);
      await tester.tap(find.text('家属详版'));
      await tester.pumpAndSettle();
      expect(find.text('您描述：$question'), findsOneWidget);
      expect(find.textContaining('120'), findsWidgets);
      expect(find.textContaining('胸痛胸闷'), findsNothing);
    }
  });
}
