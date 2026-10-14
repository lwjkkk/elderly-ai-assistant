import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../services/api.dart';

List<Map<String, dynamic>> reportMetrics(Map<String, dynamic> report) =>
    report['metrics'] is List
        ? (report['metrics'] as List)
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList()
        : [];

String reportMetricSummary(Map<String, dynamic> report) {
  final metrics = reportMetrics(report);
  if (metrics.isEmpty) return '未能核对';
  final abnormal = metrics
      .where((m) => m['status'] == 'high' || m['status'] == 'low')
      .length;
  final unparsed = metrics
      .where((m) => !['normal', 'high', 'low'].contains(m['status']))
      .length;
  return [
    if (abnormal > 0) '$abnormal 项偏高或偏低',
    if (unparsed > 0) '$unparsed 项待核对',
    if (abnormal == 0 && unparsed == 0) '已核对 ${metrics.length} 项正常',
  ].join('，');
}

Color reportMetricColor(Map<String, dynamic> report) {
  final metrics = reportMetrics(report);
  if (metrics.any((m) => m['status'] == 'high' || m['status'] == 'low')) {
    return const Color(0xFFB3261E);
  }
  if (metrics.isEmpty || metrics.any((m) => m['status'] != 'normal')) {
    return const Color(0xFF6B7280);
  }
  return const Color(0xFF347A58);
}

class ReportMetrics extends StatelessWidget {
  final Map<String, dynamic> report;
  const ReportMetrics({super.key, required this.report});

  @override
  Widget build(BuildContext context) {
    final metrics = reportMetrics(report);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('指标核对结果',
          style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Color(0xFF212936))),
      const SizedBox(height: 8),
      if (metrics.isEmpty)
        const Text('未能自动核对指标，请对照原报告确认。',
            style:
                TextStyle(fontSize: 18, color: Color(0xFF6B7280), height: 1.5)),
      for (final metric in metrics) _row(metric),
    ]);
  }

  Widget _row(Map<String, dynamic> m) {
    final status = m['status'];
    final label = status == 'normal'
        ? '正常'
        : status == 'high'
            ? '偏高'
            : status == 'low'
                ? '偏低'
                : '待核对';
    final color = status == 'normal'
        ? const Color(0xFF347A58)
        : status == 'high' || status == 'low'
            ? const Color(0xFFB3261E)
            : const Color(0xFF6B7280);
    final lo = m['lo'], hi = m['hi'];
    final range = lo != null && hi != null
        ? '$lo～$hi'
        : lo != null
            ? '≥ $lo'
            : hi != null
                ? '≤ $hi'
                : '未识别';
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(
                    '${m['code'] ?? m['name'] ?? '未识别项目'}  ${m['result'] ?? '—'}',
                    style: const TextStyle(
                        fontSize: 19, color: Color(0xFF212936))),
                Text('参考范围：$range',
                    style: const TextStyle(
                        fontSize: 16, color: Color(0xFF6B7280))),
              ])),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w700, color: color)),
        ]));
  }
}

class AuthenticatedReportImage extends StatefulWidget {
  final String url;
  const AuthenticatedReportImage({super.key, required this.url});
  @override
  State<AuthenticatedReportImage> createState() =>
      _AuthenticatedReportImageState();
}

class _AuthenticatedReportImageState extends State<AuthenticatedReportImage> {
  late Future<Uint8List> _image;
  @override
  void initState() {
    super.initState();
    _image = ApiService.reportImageBytes(widget.url);
  }

  @override
  void didUpdateWidget(AuthenticatedReportImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url)
      _image = ApiService.reportImageBytes(widget.url);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
        future: _image,
        builder: (context, snapshot) {
          if (snapshot.hasError)
            return Column(children: [
              Text('原图加载失败：${ApiService.friendly(snapshot.error!)}'),
              TextButton(
                  onPressed: () => setState(() {
                        _image = ApiService.reportImageBytes(widget.url);
                      }),
                  child: const Text('重试')),
            ]);
          if (!snapshot.hasData)
            return const SizedBox(
                height: 100,
                child: Center(
                    child:
                        CircularProgressIndicator(color: Color(0xFF345C87))));
          return Image.memory(snapshot.data!,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Text('原图格式无法显示'));
        },
      );
}

Future<void> showReportOriginal(BuildContext context, String url) =>
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('报告原图'),
        content: SizedBox(
            width: 600,
            child: SingleChildScrollView(
                child: AuthenticatedReportImage(url: url))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('关闭'))
        ],
      ),
    );
