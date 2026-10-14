import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:elderly_ai_assistant/pages/tabs/consult_drug_chat_tab.dart';
import 'package:elderly_ai_assistant/services/api.dart';
import 'package:elderly_ai_assistant/services/drug_question.dart';
import 'package:elderly_ai_assistant/services/medication_time.dart';
import 'package:elderly_ai_assistant/services/answer_speech.dart';

class _Adapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream,
      Future<void>? cancel) async {
    requests.add(options);
    String body = '[]';
    if (options.path == '/api/chat')
      body =
          '{"answer":"第一段说明\\n第二段说明","module":"health","steps":[]}';
    if (options.path.contains('weather')) body = '{"text":"未配置API_KEY"}';
    if (options.path == '/api/vitals/export')
      return ResponseBody.fromString('{"detail":"暂无体征记录，无法导出"}', 400, headers: {
        Headers.contentTypeHeader: ['application/json']
      });
    if (options.path == '/api/consults/upload' ||
        options.path == '/api/reports/upload') body = '{}';
    return ResponseBody.fromString(body, 200, headers: {
      Headers.contentTypeHeader: ['application/json']
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final spoken = <MethodCall>[];
  const channel = MethodChannel('flutter_tts');
  setUp(() {
    spoken.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      spoken.add(call);
      return 1;
    });
    SharedPreferences.setMockInitialValues(
        {'role': 'elder', 'privacy_ok_v1': true});
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('check-in respects Shanghai time and exact boundary', () {
    expect(medicationSlotDue('08:00', now: DateTime.utc(2026, 10, 12, 23, 59)),
        false);
    expect(medicationSlotDue('08:00', now: DateTime.utc(2026, 10, 13, 0, 0)),
        true);
    expect(
        medicationSlotDue('08:00',
            date: '2026-10-14', now: DateTime.utc(2026, 10, 13, 0, 0)),
        false);
    expect(medicationSlotDue('99:00', now: DateTime.utc(2026, 10, 13)), false);
  });
  test('drug queries use names and leave ordinary questions unchanged', () {
    expect(drugQueryName('阿司匹林有什么副作用？'), '阿司匹林');
    expect(drugQueryName('二甲双胍是什么药'), '二甲双胍');
    expect(drugQueryName('查药：测试药品'), '测试药品');
    expect(drugQueryName('微信怎么加好友'), isNull);
    expect(drugQueryName('帮我设置用药提醒'), isNull);
  });
  test('binary PDF errors retain backend detail', () async {
    ApiService.dio.httpClientAdapter = _Adapter();
    try {
      await ApiService.vitalsExportPdf();
      fail('Expected server error');
    } catch (e) {
      expect(ApiService.friendly(e), '暂无体征记录，无法导出');
    }
  });
  test('image and audio multipart types are accepted by backend', () async {
    final adapter = _Adapter();
    ApiService.dio.httpClientAdapter = adapter;
    await ApiService.uploadReport([1, 2, 3], 'report.png');
    await ApiService.uploadConsult([1, 2, 3], 'consult.m4a');
    final image = adapter.requests[0].data as FormData;
    final audio = adapter.requests[1].data as FormData;
    expect(image.files.single.value.contentType.toString(), 'image/png');
    expect(audio.files.single.value.contentType.toString(), 'audio/mp4');
  });
  testWidgets('drug question uses backend chat privacy rules and shows grey speech pause',
      (tester) async {
    final adapter = _Adapter();
    ApiService.dio.httpClientAdapter = adapter;
    await tester.pumpWidget(const MaterialApp(home: ChatTab()));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.enterText(find.byType(TextField), '阿司匹林有什么副作用？');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
        adapter.requests.any((r) => r.path == '/api/chat'), true);
    expect(adapter.requests.any((r) => r.path == '/api/drugs/query-name'), false);
    expect(spoken.any((c) => c.method == 'speak'), true);
    expect(find.byTooltip('暂停语音'), findsOneWidget);
    await tester.tap(find.byTooltip('暂停语音'));
    for (var i = 0; i < 3; i++) {
      await tester.pump();
    }
    expect(spoken.any((c) => c.method == 'pause'), true);
    expect(find.byTooltip('播放语音'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
  test('paragraph narration waits for completion and supports pause', () async {
    final speech = AnswerSpeech();
    await speech.play(5, '第一段\n第二段');
    expect(spoken.where((c) => c.method == 'speak').single.arguments, '第一段');
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
            'flutter_tts',
            const StandardMethodCodec()
                .encodeMethodCall(const MethodCall('speak.onComplete', null)),
            (_) {});
    await Future<void>.delayed(Duration.zero);
    expect(spoken.where((c) => c.method == 'speak').last.arguments, '第二段');
    await speech.toggle(5, '第一段\n第二段');
    expect(speech.paused, true);
    await speech.toggle(5, '第一段\n第二段');
    expect(speech.paused, false);
    await speech.stop();
    expect(speech.messageIndex, isNull);
    speech.dispose();
    await Future<void>.delayed(Duration.zero);
  });

  test('unavailable speech does not leave a false playing state', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => call.method == 'speak' ? 0 : 1);
    String? error;
    final speech = AnswerSpeech(onError: (text) => error = text);
    await speech.play(1, '测试回复');
    expect(speech.messageIndex, isNull);
    expect(error, isNotNull);
    speech.dispose();
    await Future<void>.delayed(Duration.zero);
  });
}
