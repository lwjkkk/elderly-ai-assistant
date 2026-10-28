import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:elderly_ai_assistant/pages/chat/chat_history_page.dart';
import 'package:elderly_ai_assistant/services/chat/contest_answer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('历史回答可切换详版，旧记录仍展示原文', (tester) async {
    SharedPreferences.setMockInitialValues({
      'test_account_sessions_v1': jsonEncode([
        {
          'id': 'structured',
          'created_at': '2026-10-22T10:00:00',
          'messages': [
            {
              'role': 'ai',
              'text': '保存时的默认简版',
              'answer_data': jsonEncode({
                'parts': {
                  'conclusion': '默认结论',
                  'advice': '默认建议',
                },
                'view': {'conclusion': '老人版重点'},
                'family_view': {'conclusion': '家属版详细重点'},
                'sources': [],
              }),
            },
            {'role': 'ai', 'text': '迁移来的旧版回答'},
          ],
        }
      ]),
    });

    await tester.pumpWidget(const MaterialApp(
      home: ChatHistoryPage(accountKey: 'test_account'),
    ));
    await tester.pumpAndSettle();

    expect(find.text('关注什么\n老人版重点'), findsOneWidget);
    expect(find.text('迁移来的旧版回答'), findsOneWidget);
    expect(find.text('老人简版'), findsOneWidget);
    expect(find.text('家属详版'), findsOneWidget);

    await tester.tap(find.text('家属详版'));
    await tester.pumpAndSettle();

    expect(find.text('关注什么\n家属版详细重点'), findsOneWidget);
    expect(find.text('关注什么\n老人版重点'), findsNothing);
    expect(find.text('迁移来的旧版回答'), findsOneWidget);
  });

  testWidgets('后端角色为家属时默认展示家属详版并可切换老人简版', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ChatHistoryAnswer(
          text: '原文',
          answerData: {
            'role': 'family',
            'elder_view': {'concern': '老人简版重点'},
            'family_view': {'concern': '家属详版重点'},
          },
        ),
      ),
    ));
    expect(find.text('关注什么\n家属详版重点'), findsOneWidget);
    await tester.tap(find.text('老人简版'));
    await tester.pumpAndSettle();
    expect(find.text('关注什么\n老人简版重点'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
