import 'package:flutter/material.dart';
import '../services/chat_archive.dart';
import '../services/contest_answer.dart';
import '../widgets/answer_evidence.dart';

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
                    _HistoryMessage(message: message),
                ]
              ],
            );
          },
        ),
      );
}

class _HistoryMessage extends StatelessWidget {
  final Map message;
  const _HistoryMessage({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message['role'] == 'me';
    final rawAnswerData = message['answer_data'];
    final answerData = rawAnswerData is Map
        ? answerMap(rawAnswerData)
        : rawAnswerData == null
            ? null
            : decodeAnswer(rawAnswerData.toString());
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints:
            BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .85),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isUser ? const Color(0xFFDCE9F7) : Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: isUser
            ? SelectableText((message['text'] ?? '').toString(),
                style: const TextStyle(
                    fontSize: 19, height: 1.5, color: Color(0xFF212936)))
            : ChatHistoryAnswer(
                text: (message['text'] ?? '').toString(),
                answerData: answerData,
              ),
      ),
    );
  }
}

class ChatHistoryAnswer extends StatefulWidget {
  final String text;
  final Map<String, dynamic>? answerData;

  const ChatHistoryAnswer({
    super.key,
    required this.text,
    this.answerData,
  });

  @override
  State<ChatHistoryAnswer> createState() => _ChatHistoryAnswerState();
}

class _ChatHistoryAnswerState extends State<ChatHistoryAnswer> {
  bool _detailed = false;

  @override
  void initState() {
    super.initState();
    _detailed = answerDefaultsToDetailedView(widget.answerData ?? {});
  }

  @override
  void didUpdateWidget(covariant ChatHistoryAnswer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.answerData?['role'] != widget.answerData?['role']) {
      _detailed = answerDefaultsToDetailedView(widget.answerData ?? {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.answerData;
    final distinct = data != null && hasDistinctAnswerViews(data);
    final emergency = data != null && answerIsEmergency(data);
    final selectedText =
        data != null ? answerText(data, detailed: _detailed) : widget.text;
    final text = selectedText.isEmpty ? widget.text : selectedText;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (emergency)
        AnswerEmergencyBanner(
            data: data!, fallbackText: widget.text, detailed: _detailed),
      if (distinct)
        Wrap(spacing: 8, children: [
          ChoiceChip(
            label: const Text('老人简版'),
            selected: !_detailed,
            onSelected: (_) => setState(() => _detailed = false),
          ),
          ChoiceChip(
            label: const Text('家属详版'),
            selected: _detailed,
            onSelected: (_) => setState(() => _detailed = true),
          ),
        ]),
      if (data != null && answerNeedsUrgentReview(data))
        const AnswerUncertainBanner(),
      if (!emergency)
        SelectableText(text,
            style: const TextStyle(
                fontSize: 19, height: 1.5, color: Color(0xFF212936))),
      if (data != null) AnswerEvidence(data: data),
    ]);
  }
}
