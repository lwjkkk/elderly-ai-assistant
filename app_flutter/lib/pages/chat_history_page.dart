import 'package:flutter/material.dart';
import '../services/chat_archive.dart';

class ChatHistoryPage extends StatelessWidget {
  final String accountKey;
  const ChatHistoryPage({super.key, required this.accountKey});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFFF7FAFD),
        appBar: AppBar(
            title: const Text('历史聊天记录'),
            backgroundColor: const Color(0xFFF7FAFD)),
        body: FutureBuilder<List<Map<String, dynamic>>>(
          future: ChatArchive.load(accountKey),
          builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('历史记录暂时无法读取，请稍后重试'));
        }
            if (!snapshot.hasData)
              return const Center(child: CircularProgressIndicator());
            final sessions = snapshot.data!;
            if (sessions.isEmpty)
              return const Center(
                  child: Text('暂无历史聊天记录', style: TextStyle(fontSize: 20)));
            return ListView(
              padding: const EdgeInsets.all(18),
              children: [
                for (final session in sessions) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Text(
                        (session['created_at'] ?? '').toString().isEmpty
                            ? '以前的聊天记录'
                            : session['created_at']
                                .toString()
                                .replaceFirst('T', ' ')
                                .split('.')
                                .first,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFF6B7280))),
                  ),
                  for (final message in session['messages'] as List)
                    Align(
                      alignment: message['role'] == 'me'
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        constraints: BoxConstraints(
                            maxWidth: MediaQuery.sizeOf(context).width * .85),
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: message['role'] == 'me'
                              ? const Color(0xFFDCE9F7)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: SelectableText(
                            (message['text'] ?? '').toString(),
                            style: const TextStyle(
                                fontSize: 19,
                                height: 1.5,
                                color: Color(0xFF212936))),
                      ),
                    ),
                ]
              ],
            );
          },
        ),
      );
}
