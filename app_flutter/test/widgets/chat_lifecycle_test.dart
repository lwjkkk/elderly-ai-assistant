import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:elderly_ai_assistant/main.dart';
import 'package:elderly_ai_assistant/services/api.dart';
import 'package:elderly_ai_assistant/pages/tabs/hub_pages.dart';

class _PreviewAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream, Future<void>? cancel) async {
    return ResponseBody.fromString(options.path.contains('weather') ? '{"text":"未配置API_KEY"}' : '[]', 200,
      headers: {Headers.contentTypeHeader: ['application/json']});
  }
  @override
  void close({bool force = false}) {}
}

void main() {
  testWidgets('AI page survives restored font size and tab switching', (tester) async {
    SharedPreferences.setMockInitialValues({'token': 'preview', 'role': 'elder', 'privacy_ok_v1': true, 'chat_text_scale': 1.3});
    ApiService.dio.httpClientAdapter = _PreviewAdapter();
    await tester.pumpWidget(const ElderApp());
    for (var i = 0; i < 15; i++) { await tester.pump(const Duration(milliseconds: 100)); }
    expect(find.text('体征'), findsOneWidget);
    expect(tester.takeException(), isNull);
    chatScale.value = 1.15;
    await tester.pump();
    await tester.pump();
    expect(find.text('体征'), findsOneWidget);
    expect(tester.takeException(), isNull);
    HubNav.go(0);
    await tester.pump();
    HubNav.go(1);
    for (var i = 0; i < 5; i++) { await tester.pump(const Duration(milliseconds: 100)); }
    expect(find.text('体征'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
