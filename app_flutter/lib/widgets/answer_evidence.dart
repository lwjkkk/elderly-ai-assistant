import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/contest_answer.dart';

class AnswerUncertainBanner extends StatelessWidget {
  const AnswerUncertainBanner({super.key});
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('紧急程度未能核定，请保留警惕，并按下方提示联系身边人或医生。',
            style: TextStyle(
                color: Color(0xFF8A5500),
                fontSize: 18,
                fontWeight: FontWeight.w700)),
      );
}

class AnswerEmergencyBanner extends StatelessWidget {
  final Map<String, dynamic> data;
  final String fallbackText;
  final bool detailed;

  const AnswerEmergencyBanner({
    super.key,
    required this.data,
    required this.fallbackText,
    this.detailed = false,
  });

  @override
  Widget build(BuildContext context) {
    final sections = answerEmergencySections(data, detailed: detailed);
    final action = sections['action'] ?? '';
    final seek = sections['seek'] ?? '';
    final original = answerOriginalText(data);
    final types = answerEmergencyTypeLabels(data);
    final reported = (data['reported_question'] ?? '').toString().trim();
    final notification = familyNotificationExplanation(data);
    final hasAction = action.isNotEmpty || fallbackText.trim().isNotEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEEEE),
        border: Border.all(color: const Color(0xFFB3261E), width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Material(
        color: Colors.transparent,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.emergency_outlined, color: Color(0xFFB3261E), size: 24),
            SizedBox(width: 8),
            Expanded(
              child: Text('立即求助',
                  style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF8E1B16))),
            ),
          ]),
          if (types.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('提醒类别：${types.join('、')}',
                style: const TextStyle(
                    color: Color(0xFF8E1B16), fontWeight: FontWeight.w600)),
          ],
          if (reported.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('您描述：$reported',
                style: const TextStyle(fontSize: 18, color: Color(0xFF8E1B16))),
          ],
          const SizedBox(height: 6),
          if (hasAction)
            Text(action.isNotEmpty ? action : fallbackText,
                style: const TextStyle(
                    fontSize: 18,
                    height: 1.45,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF8E1B16))),
          if (!action.contains('120') && !seek.contains('120'))
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('请立即拨打120或前往急诊，不要等待。',
                  style: TextStyle(
                      fontSize: 18,
                      height: 1.45,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF8E1B16))),
            ),
          if (seek.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('就医提醒：$seek',
                style: const TextStyle(
                    fontSize: 18,
                    height: 1.45,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF8E1B16))),
          ],
          if (notification.isNotEmpty)
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(notification,
                    style: const TextStyle(
                        fontSize: 16, color: Color(0xFF7A1A1A)))),
          if (original.isNotEmpty && original != action && original != seek)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('查看完整回答原文'),
              children: [
                SelectableText(original,
                    style: const TextStyle(fontSize: 17, height: 1.5)),
              ],
            ),
        ]),
      ),
    );
  }
}

class AnswerEvidence extends StatelessWidget {
  final Map<String, dynamic> data;
  const AnswerEvidence({super.key, required this.data});

  static const _style =
      TextStyle(fontSize: 16, height: 1.5, color: Color(0xFF52606D));

  @override
  Widget build(BuildContext context) {
    final footer = answerFooter(data);
    final items = (footer['items'] as List).cast<Map<String, dynamic>>();
    final safety = footer['safety_notice'] as String;
    if (items.isEmpty && safety.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
          color: Colors.transparent,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (items.isNotEmpty)
              ExpansionTile(
                key: ValueKey(items
                    .map((item) => '${item['title']}:${item['excerpts']}')
                    .join('|')),
                initiallyExpanded: false,
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 8),
                minTileHeight: 48,
                leading: const Icon(Icons.menu_book_outlined,
                    color: Color(0xFF345C87)),
                title: const Text('查看知识库依据',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF345C87))),
                children: [
                  for (final item in items) _reference(context, item),
                  if ((footer['notice'] as String).isNotEmpty)
                    Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(footer['notice'] as String, style: _style)),
                ],
              ),
            if (safety.isNotEmpty) Text(safety, style: _style),
          ])),
    );
  }

  Widget _reference(BuildContext context, Map<String, dynamic> item) {
    final applicability = answerMap(item['applicability']);
    final url = _safeSourceUri(item['source_url']);
    const labels = {
      'region': '适用地区',
      'platform': '适用平台',
      'updated_at': '更新时间',
      'valid_until': '有效期至'
    };
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .65),
          borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(item['title'] as String,
            style: _style.copyWith(fontWeight: FontWeight.w700)),
        for (final excerpt in item['excerpts'] as List)
          Padding(
              padding: const EdgeInsets.only(top: 6),
              child: SelectableText(excerpt.toString(), style: _style)),
        for (final key in labels.keys)
          if ((applicability[key] ?? '').toString().trim().isNotEmpty)
            Text('${labels[key]}：${applicability[key]}', style: _style),
        if (url != null)
          TextButton.icon(
            style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
            onPressed: () => _openSource(context, url),
            icon: const Icon(Icons.open_in_new),
            label: const Text('查看原始来源', style: TextStyle(fontSize: 16)),
          ),
      ]),
    );
  }

  Uri? _safeSourceUri(dynamic raw) {
    final value = raw?.toString().trim() ?? '';
    if (value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme.toLowerCase()) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    return uri;
  }

  Future<void> _openSource(BuildContext context, Uri uri) async {
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('无法打开该来源链接')));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('无法打开该来源链接')));
      }
    }
  }
}
