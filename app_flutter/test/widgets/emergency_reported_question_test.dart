import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:elderly_ai_assistant/pages/tabs/consult_drug_chat_tab.dart';
import 'package:elderly_ai_assistant/services/api.dart';

class _Adapter implements HttpClientAdapter {
  final calls = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream,
      Future<void>? cancelFuture) async {
    calls.add(options);
    final dynamic data = options.path == '/api/chat/tiered'
        ? {
            'answer': '请立即拨打120',
            'emergency': true,
            'emergency_types': ['chest_pain'],
            // Simulate an old server that incorrectly substitutes a symptom.
            'reported_question': '我胸闷',
            'elder_view': {'next_step': '请立即拨打120'},
            'family_view': {'next_step': '请立即联系身边人并拨打120'},
          }
        : options.path == '/api/symptom-check' && options.method == 'POST'
            ? {'input_text': '我胸闷', 'advice_text': '请立即拨打120', 'risk': 'red'}
            : [];
    return ResponseBody.fromString(jsonEncode(data), 200, headers: {
      Headers.contentTypeHeader: ['application/json']
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late _Adapter adapter;
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'token': 'test-token',
      'user_id': 3,
      'role': 'elder',
      'privacy_ok_v1': true
    });
    adapter = _Adapter();
    ApiService.dio.httpClientAdapter = adapter;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('flutter_tts'), (_) async => 1);
  });

  Future<void> open(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: page));
    await tester.pumpAndSettle();
  }

  testWidgets('chat quotes actual submitted text despite a stale server echo',
      (tester) async {
    await open(tester, const ChatTab());
    const question = '我心脏疼，没有胸闷，刚才开始的';
    await tester.enterText(find.byType(TextField), question);
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();
    expect(adapter.calls.singleWhere((r) => r.path == '/api/chat/tiered').data,
        {'question': question});
    expect(find.text('您描述：$question'), findsOneWidget);
    expect(find.text('您描述：我胸闷'), findsNothing);
    expect(find.text('提醒类别：胸部不适相关危险信号'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('symptom check preserves submitted details and negation',
      (tester) async {
    await open(tester, const Scaffold(body: SymptomTab()));
    const question = '妈妈左胳膊突然抬不起，右边没事，开始约10分钟';
    await tester.enterText(find.byType(TextField), question);
    await tester.tap(find.text('提交自查'));
    await tester.pumpAndSettle();
    expect(
        adapter.calls.singleWhere((r) => r.method == 'POST').data['input_text'],
        question);
    expect(find.text('您描述：$question'), findsOneWidget);
    expect(find.text('您描述：我胸闷'), findsNothing);
    expect(find.textContaining('120'), findsWidgets);
  });
}
