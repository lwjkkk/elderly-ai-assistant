import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:elderly_ai_assistant/services/api.dart';
import 'package:elderly_ai_assistant/services/voice_transcription.dart';
import 'package:elderly_ai_assistant/pages/tabs/consult_drug_chat_tab.dart';
import 'package:elderly_ai_assistant/pages/tabs/vital_draft_page.dart';

class _Capture implements VoiceAudioCapture {
  bool wav = true;
  bool active = false;
  bool disposed = false;
  int starts = 0;
  int stops = 0;
  String? path;
  Completer<void>? starting;
  @override
  Future<bool> supportsWav() async => wav;
  @override
  Future<void> start(String path, {required bool wav}) async {
    starts++;
    this.path = path;
    if (starting != null) await starting!.future;
    active = true;
  }

  @override
  Future<String?> stop() async {
    stops++;
    active = false;
    return path;
  }

  @override
  Future<void> cancel() async {
    active = false;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    active = false;
  }
}

class _Adapter implements HttpClientAdapter {
  final calls = <RequestOptions>[];
  int status = 200;
  dynamic response = {
    'transcript': '高压145，低压90',
    'requires_confirmation': true
  };
  Completer<void>? pending;
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream,
      Future<void>? cancelFuture) async {
    calls.add(options);
    if (options.path == '/api/speech/capabilities') {
      return ResponseBody.fromString(
          jsonEncode({
            'provider_configured': true,
            'provider_probe': 'not_performed',
            'max_bytes': voiceTranscriptionMaxBytes
          }),
          200,
          headers: {
            Headers.contentTypeHeader: ['application/json']
          });
    }
    if (options.path == '/api/speech/transcribe') {
      if (pending != null) await pending!.future;
      return ResponseBody.fromString(jsonEncode(response), status, headers: {
        Headers.contentTypeHeader: ['application/json'],
        'retry-after': ['3']
      });
    }
    return ResponseBody.fromString(
        jsonEncode(options.path.contains('/draft-conversations')
            ? {
                'session_id': 9,
                'elder_id': 3,
                'can_confirm': false,
                'question': '请核对测量时间',
                'draft': {'type': 'bp', 'systolic': 145, 'diastolic': 90},
              }
            : options.path == '/api/chat/tiered'
                ? {
                    'answer': '请核对信息',
                    'emergency': false,
                  }
                : []),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json']
        });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Adapter adapter;
  late _Capture capture;
  late List<String> removed;
  VoiceTranscriptionRecorder recorder(
          {int size = 10, Future<void> Function()? permission}) =>
      VoiceTranscriptionRecorder(
          capture: capture,
          permission: permission ?? () async {},
          temporaryPath: (name) async => '/private-temp/$name',
          readBytes: (_) async => Uint8List(size),
          removeFile: (path) async {
            removed.add(path);
          });
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'token': 'test-token',
      'user_id': 3,
      'role': 'elder',
      'privacy_ok_v1': true
    });
    adapter = _Adapter();
    capture = _Capture();
    removed = [];
    ApiService.dio.httpClientAdapter = adapter;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('flutter_tts'), (_) async => 1);
  });

  test(
      'transcription sends authenticated multipart without elder/account fields',
      () async {
    SharedPreferences.setMockInitialValues(
        {'token': 'test-token', 'role': 'family', 'elder_id': 42});
    expect(
        await ApiService.transcribeAudio([1, 2], 'voice.wav',
            purpose: 'vitals'),
        '高压145，低压90');
    final call = adapter.calls.single;
    expect(call.path, '/api/speech/transcribe');
    expect(call.headers['Authorization'], 'Bearer test-token');
    expect(call.headers[Headers.contentTypeHeader],
        startsWith('multipart/form-data; boundary='));
    final form = call.data as FormData;
    expect(Map.fromEntries(form.fields), {'purpose': 'vitals'});
    expect(form.files.single.value.filename, 'voice.wav');
    expect(form.files.single.value.contentType.toString(), 'audio/wav');
    expect(call.sendTimeout, const Duration(seconds: 60));
    expect(call.receiveTimeout, const Duration(seconds: 60));
  });

  test(
      'unlogged, changed session, empty, oversize, and invalid purpose never upload',
      () async {
    SharedPreferences.setMockInitialValues({});
    await expectLater(ApiService.transcribeAudio([1], 'x.wav', purpose: 'chat'),
        throwsStateError);
    SharedPreferences.setMockInitialValues({'token': 'new-token'});
    await expectLater(
        ApiService.transcribeAudio([1], 'x.wav',
            purpose: 'chat', expectedToken: 'old-token'),
        throwsStateError);
    await expectLater(ApiService.transcribeAudio([], 'x.wav', purpose: 'chat'),
        throwsStateError);
    await expectLater(
        ApiService.transcribeAudio(
            Uint8List(voiceTranscriptionMaxBytes + 1), 'x.wav',
            purpose: 'chat'),
        throwsStateError);
    await expectLater(
        ApiService.transcribeAudio([1], 'x.wav', purpose: 'other'),
        throwsArgumentError);
    expect(adapter.calls, isEmpty);
  });

  test('response requires explicit confirmation and nonempty text', () async {
    for (final value in [
      {'transcript': 'text'},
      {'transcript': '', 'requires_confirmation': true},
      [],
      {'transcript': 145, 'requires_confirmation': true}
    ]) {
      adapter.response = value;
      await expectLater(
          ApiService.transcribeAudio([1], 'x.wav', purpose: 'chat'),
          throwsStateError);
    }
  });

  test('capability configuration is returned without an ASR probe', () async {
    final data = await ApiService.speechCapabilities();
    expect(data['provider_probe'], 'not_performed');
    expect(adapter.calls.map((r) => r.path), ['/api/speech/capabilities']);
  });

  test(
      'capture stops before upload, uses real format suffix, and cleans success',
      () async {
    capture.wav = false;
    final audio = recorder();
    await audio.start();
    expect(capture.path, endsWith('.m4a'));
    final text = await audio.stopAndTranscribe(purpose: 'chat');
    expect(text, contains('145'));
    expect(capture.active, isFalse);
    expect(capture.stops, 1);
    expect((adapter.calls.single.data as FormData).files.single.value.filename,
        endsWith('.m4a'));
    expect(removed, contains(capture.path));
    await audio.dispose();
    expect(capture.disposed, isTrue);
  });

  test('failure has no automatic retry and deletes temporary audio', () async {
    adapter.status = 429;
    adapter.response = {'detail': '服务正忙'};
    final audio = recorder();
    await audio.start();
    await expectLater(
        audio.stopAndTranscribe(purpose: 'chat'), throwsA(isA<DioException>()));
    expect(adapter.calls.length, 1);
    expect(removed, contains(capture.path));
    await audio.dispose();
  });

  test('cancel while permission/start pending releases recorder without upload',
      () async {
    final permission = Completer<void>();
    final audio = recorder(permission: () => permission.future);
    final starting = audio.start();
    await Future<void>.delayed(Duration.zero);
    final cancelled = audio.cancel();
    permission.complete();
    await starting;
    await cancelled;
    expect(capture.active, isFalse);
    expect(capture.starts, 0);
    expect(adapter.calls, isEmpty);
    await audio.dispose();
  });

  test('cancel and logout discard late result and delete audio', () async {
    adapter.pending = Completer<void>();
    final audio = recorder();
    await audio.start();
    final result = audio.stopAndTranscribe(purpose: 'chat');
    final check = expectLater(result, throwsA(anything));
    for (var i = 0; i < 10 && adapter.calls.isEmpty; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    await ApiService.clearAuth();
    await audio.cancel();
    adapter.pending!.complete();
    await check;
    expect(capture.active, isFalse);
    expect(removed, contains(capture.path));
    await audio.dispose();
  });

  test(
      'business failures preserve readable guidance, validation arrays never leak',
      () {
    for (final status in [400, 401, 413, 415, 422, 429, 502, 503, 504]) {
      final e = DioException(
          requestOptions: RequestOptions(),
          response: Response(
              requestOptions: RequestOptions(),
              statusCode: status,
              data: {'detail': '可读错误'},
              headers: Headers.fromMap({
                'retry-after': ['3']
              })));
      final message = voiceTranscriptionError(e);
      expect(message, isNotEmpty);
      if (status == 503) expect(message, isNot(contains('登录')));
      if (status == 429) expect(message, contains('3 秒后手动重试'));
    }
    final e = DioException(
        requestOptions: RequestOptions(),
        response:
            Response(requestOptions: RequestOptions(), statusCode: 422, data: {
          'detail': [
            {
              'loc': ['file'],
              'msg': 'missing'
            }
          ]
        }));
    expect(voiceTranscriptionError(e), isNot(contains('loc')));
  });

  Future<void> tick(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
  }

  Future<void> large(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> stopAndReview(WidgetTester tester) async {
    await tick(tester);
    await tester.tap(find.text('停止并识别'));
    await tick(tester);
    expect(find.byKey(const ValueKey('voice-transcript')), findsOneWidget);
    expect(capture.active, isFalse);
  }

  testWidgets('chat uses editable confirmed text and sends only on user send',
      (tester) async {
    await large(tester);
    await tester
        .pumpWidget(MaterialApp(home: ChatTab(voiceRecorderFactory: recorder)));
    await tick(tester);
    await tester.tap(find.byIcon(Icons.mic_none));
    await stopAndReview(tester);
    expect(adapter.calls.where((r) => r.path.contains('/chat')), isEmpty);
    await tester.enterText(
        find.byKey(const ValueKey('voice-transcript')), '微信怎么加好友');
    await tester.tap(find.text('使用核对后的文字'));
    await tick(tester);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '微信怎么加好友');
    expect(adapter.calls.where((r) => r.path.contains('/chat')), isEmpty);
    await tester.tap(find.byType(TextField));
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tick(tester);
    final chats =
        adapter.calls.where((r) => r.path == '/api/chat/tiered').toList();
    expect(chats.length, 1);
    expect(chats.single.data['question'], '微信怎么加好友');
    await tester.pumpWidget(const SizedBox.shrink());
    await tick(tester);
    expect(capture.disposed, isTrue);
  });

  testWidgets(
      'vitals requires editing/confirming text before draft parsing and no final save',
      (tester) async {
    await large(tester);
    await tester.pumpWidget(
        MaterialApp(home: VitalDraftPage(voiceRecorderFactory: recorder)));
    await tick(tester);
    await tester.tap(find.text('录音补充'));
    await stopAndReview(tester);
    expect(adapter.calls.where((r) => r.path.contains('/vitals')), isEmpty);
    await tester.enterText(
        find.byKey(const ValueKey('voice-transcript')), '今天八点血压145/90');
    await tester.tap(find.text('使用核对后的文字'));
    await tick(tester);
    expect(adapter.calls.where((r) => r.path.contains('/vitals')), isEmpty);
    await tester.tap(find.text('更新草稿'));
    await tick(tester);
    final drafts = adapter.calls
        .where((r) => r.path.contains('/draft-conversations'))
        .toList();
    expect(drafts.length, 1);
    expect(drafts.single.data['text'], '今天八点血压145/90');
    expect(
        adapter.calls
            .any((r) => r.path.endsWith('/confirm') || r.path == '/api/vitals'),
        isFalse);
    expect(Map.fromEntries((adapter.calls.first.data as FormData).fields),
        {'purpose': 'vitals'});
    await tester.pumpWidget(const SizedBox.shrink());
    await tick(tester);
  });

  testWidgets(
      '60 seconds auto-stops once and cancel during ASR never fills input',
      (tester) async {
    await large(tester);
    adapter.pending = Completer<void>();
    await tester
        .pumpWidget(MaterialApp(home: ChatTab(voiceRecorderFactory: recorder)));
    await tick(tester);
    await tester.tap(find.byIcon(Icons.mic_none));
    await tick(tester);
    await tester.pump(const Duration(seconds: 60));
    await tick(tester);
    expect(capture.stops, 1);
    expect(capture.active, isFalse);
    expect(find.textContaining('正在识别'), findsOneWidget);
    await tester.tap(find.text('取消，使用文字输入'));
    await tick(tester);
    await tester.enterText(find.byType(TextField), '后来输入的文字');
    adapter.pending!.complete();
    await tick(tester);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '后来输入的文字');
    expect(adapter.calls.where((r) => r.path.contains('/chat')), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await tick(tester);
  });

  testWidgets('background and route removal release microphone without upload',
      (tester) async {
    await large(tester);
    await tester
        .pumpWidget(MaterialApp(home: ChatTab(voiceRecorderFactory: recorder)));
    await tick(tester);
    await tester.tap(find.byIcon(Icons.mic_none));
    await tick(tester);
    expect(capture.active, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tick(tester);
    expect(capture.active, isFalse);
    expect(adapter.calls.where((r) => r.method == 'POST'), isEmpty);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox.shrink());
    await tick(tester);
  });

  testWidgets(
      'permission rejection offers text input and permanent rejection settings',
      (tester) async {
    await large(tester);
    VoiceTranscriptionRecorder denied() => recorder(permission: () async {
          throw const VoicePermissionException(permanentlyDenied: true);
        });
    await tester
        .pumpWidget(MaterialApp(home: ChatTab(voiceRecorderFactory: denied)));
    await tick(tester);
    await tester.tap(find.byIcon(Icons.mic_none));
    await tick(tester);
    expect(find.text('打开麦克风设置'), findsOneWidget);
    expect(capture.starts, 0);
    await tester.tap(find.text('取消，使用文字输入'));
    await tick(tester);
    await tester.enterText(find.byType(TextField), '仍可打字');
    expect(adapter.calls.where((r) => r.method == 'POST'), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await tick(tester);
  });

  testWidgets(
      'navigation during recording releases microphone and preserves new route',
      (tester) async {
    await large(tester);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
        navigatorKey: navigator,
        home: ChatTab(voiceRecorderFactory: recorder)));
    await tick(tester);
    await tester.tap(find.byIcon(Icons.mic_none));
    await tick(tester);
    expect(capture.active, isTrue);
    unawaited(navigator.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('新页面')))));
    await tick(tester);
    expect(capture.active, isFalse);
    await tester.pumpAndSettle();
    expect(capture.disposed, isTrue);
    expect(find.text('新页面'), findsOneWidget);
    expect(adapter.calls.where((r) => r.method == 'POST'), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await tick(tester);
  });
}
