import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:elderly_ai_assistant/services/chat/chat_archive.dart';

void main() {
  test('迁移旧聊天记录只执行一次，写入新会话后仍保留旧记录', () async {
    SharedPreferences.setMockInitialValues({
      'elder_1': jsonEncode([{'role': 'me', 'text': '以前的问题'}]),
    });
    await ChatArchive.migrate('elder_1');
    await ChatArchive.save('elder_1', 'new', [{'role': 'me', 'text': '新的问题'}]);
    await ChatArchive.migrate('elder_1');
    final sessions = await ChatArchive.load('elder_1');
    expect(sessions.length, 2);
    expect(sessions.last['messages'][0]['text'], '以前的问题');
  });

  test('两个会话并行保存不会互相覆盖，另一个账号不能读到记录', () async {
    SharedPreferences.setMockInitialValues({});
    await ChatArchive.migrate('elder_2');
    await Future.wait([
      ChatArchive.save('elder_2', 'first', [{'role': 'me', 'text': '第一段'}]),
      ChatArchive.save('elder_2', 'second', [{'role': 'me', 'text': '第二段'}]),
    ]);
    await ChatArchive.save('elder_2', 'first', [
      {'role': 'me', 'text': '第一段'}, {'role': 'ai', 'text': '回复'},
    ]);
    final sessions = await ChatArchive.load('elder_2');
    expect(sessions.length, 2);
    expect((sessions.firstWhere((s) => s['id'] == 'first')['messages'] as List).length, 2);
    expect(await ChatArchive.load('family_3'), isEmpty);
  });
}
