import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:elderly_ai_assistant/services/api.dart';
import 'package:elderly_ai_assistant/services/reports/report_retake.dart';

List<Map<String, dynamic>> reportMetrics(Map<String, dynamic> report) =>
    report['metrics'] is List
        ? (report['metrics'] as List)
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList()
        : [];

bool reportMetricNeedsReview(Map<String, dynamic> metric) =>
    metric['needs_review'] == true ||
    ['indeterminate', 'unverified_bound']
        .contains(metric['comparison_status']) ||
    !['normal', 'high', 'low'].contains(metric['status']);

String reportMetricUnit(Map<String, dynamic> metric) {
  final unit =
      (metric['unit'] ?? metric['result_unit'] ?? '').toString().trim();
  return unit;
}

String reportMetricEvidence(Map<String, dynamic> metric) {
  final evidence = metric['evidence_text'] ??
      metric['ocr_text'] ??
      metric['evidence'] ??
      metric['source_text'] ??
      metric['raw_text'] ??
      '';
  return evidence.toString().trim();
}

Map<String, dynamic> reportOcrDetails(Map<String, dynamic> report) =>
    report['ocr_details'] is Map
        ? Map<String, dynamic>.from(report['ocr_details'] as Map)
        : <String, dynamic>{};

List<String> reportWarnings(dynamic value) => value is List
    ? value
        .map((item) =>
            item is Map ? (item['message'] ?? '').toString() : item.toString())
        .where((text) => text.trim().isNotEmpty)
        .toList()
    : [];

bool reportPartiallyRecognized(Map<String, dynamic> report) =>
    (report['recognition_status'] ??
        reportOcrDetails(report)['recognition_status']) ==
    'partial';

String reportMetricResultText(Map<String, dynamic> metric) {
  final result = metric['result'];
  if (result == null || result.toString().trim().isEmpty) return '—';
  final unit = reportMetricUnit(metric);
  return unit.isEmpty ? '$result' : '$result $unit';
}

String reportMetricSummary(Map<String, dynamic> report) {
  final metrics = reportMetrics(report);
  if (metrics.isEmpty) return '未能核对';
  final abnormal = metrics
      .where((m) =>
          !reportMetricNeedsReview(m) &&
          (m['status'] == 'high' || m['status'] == 'low'))
      .length;
  final unparsed = metrics.where(reportMetricNeedsReview).length;
  return [
    if (abnormal > 0) '$abnormal 项偏高或偏低',
    if (unparsed > 0) '$unparsed 项待核对',
    if (abnormal == 0 && unparsed == 0) '已核对 ${metrics.length} 项正常',
  ].join('，');
}

Color reportMetricColor(Map<String, dynamic> report) {
  final metrics = reportMetrics(report);
  if (metrics.any((m) =>
      !reportMetricNeedsReview(m) &&
      (m['status'] == 'high' || m['status'] == 'low'))) {
    return const Color(0xFFB3261E);
  }
  if (metrics.isEmpty ||
      metrics.any((m) => reportMetricNeedsReview(m)) ||
      metrics.any((m) => m['status'] != 'normal')) {
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
    final details = reportOcrDetails(report);
    final warnings = reportWarnings(details['warnings']);
    final coverage =
        details['coverage'] is Map ? details['coverage'] as Map : const {};
    final findings = reportWarnings(coverage['findings']);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('指标核对结果',
          style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Color(0xFF212936))),
      if (reportPartiallyRecognized(report))
        const Text('部分项目待核对', style: TextStyle(color: Color(0xFF6B7280))),
      if (coverage['complete_report_verified'] == false)
        const Text('仅核对已识别项目，尚未确认整份报告完整性。',
            style: TextStyle(color: Color(0xFF6B7280))),
      if (findings.isNotEmpty) ...[
        const Text('疑似漏项或未配对提示（不代表已确认漏项）：',
            style: TextStyle(color: Color(0xFF6B4E16))),
        for (final finding in findings) Text(finding),
      ],
      if (warnings.isNotEmpty) ...[
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: const Color(0xFFFFF5E5),
              border: Border.all(color: const Color(0xFFE7C77A)),
              borderRadius: BorderRadius.circular(8)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('原图识别提示',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, color: Color(0xFF6B4E16))),
              for (final warning in warnings)
                Text(warning,
                    style:
                        const TextStyle(color: Color(0xFF6B4E16), height: 1.4)),
            ],
          ),
        ),
      ],
      const SizedBox(height: 8),
      if (metrics.isEmpty)
        const Text('未能自动核对指标，请对照原报告确认。',
            style:
                TextStyle(fontSize: 18, color: Color(0xFF6B7280), height: 1.5)),
      for (final metric in metrics)
        _row(context, metric,
            parserVersion: (report['parser_version'] ?? '').toString()),
    ]);
  }

  Widget _row(BuildContext context, Map<String, dynamic> m,
      {String parserVersion = ''}) {
    final status = m['status'];
    final needsReview = reportMetricNeedsReview(m);
    final label = needsReview
        ? '待核对'
        : status == 'normal'
            ? '正常'
            : status == 'high'
                ? '偏高'
                : status == 'low'
                    ? '偏低'
                    : '待核对';
    final color = needsReview
        ? const Color(0xFF6B7280)
        : status == 'normal'
            ? const Color(0xFF347A58)
            : status == 'high' || status == 'low'
                ? const Color(0xFFB3261E)
                : const Color(0xFF6B7280);
    final lo = m['lo'], hi = m['hi'];
    final range = (m['range_text'] ?? '').toString().trim().isNotEmpty
        ? m['range_text'].toString()
        : lo != null && hi != null
            ? '$lo～$hi'
            : lo != null
                ? '≥ $lo'
                : hi != null
                    ? '≤ $hi'
                    : '未能核对';
    final unit = reportMetricUnit(m);
    final evidence = reportMetricEvidence(m);
    final reason =
        (m['verification_reason'] ?? m['parse_reason'] ?? '').toString().trim();
    final metricWarnings = reportWarnings(m['warnings']);
    final resultText = (m['result_text'] ?? '').toString().trim();
    final comparison =
        m['bound_comparison'] is Map ? m['bound_comparison'] as Map : const {};
    final comparisonNote = (comparison['note'] ?? '').toString().trim();
    final normalization = m['unit_normalization'] is Map
        ? m['unit_normalization'] as Map
        : const {};
    final rawUnit =
        (m['unit_raw'] ?? normalization['original'] ?? '').toString().trim();
    final confidence = m['ocr_confidence'];
    final sourceBlocks = m['source_blocks'] is List
        ? (m['source_blocks'] as List).whereType<Map>().toList()
        : <Map>[];
    final version = (m['parser_version'] ?? parserVersion).toString().trim();
    final rangeWithUnit =
        unit.isEmpty || range == '未能核对' ? range : '$range $unit';
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(
                    '${m['code'] ?? m['name'] ?? '未识别项目'}  ${reportMetricResultText(m)}',
                    style: const TextStyle(
                        fontSize: 19, color: Color(0xFF212936))),
                Text(
                    '参考范围：$rangeWithUnit${needsReview && range != '未能核对' ? '（待核对）' : ''}',
                    style: const TextStyle(
                        fontSize: 16, color: Color(0xFF6B7280))),
                if (needsReview && reason.isNotEmpty)
                  Text('核对说明：$reason',
                      style: const TextStyle(color: Color(0xFF6B7280))),
                if (m['result'] == null && resultText.isNotEmpty)
                  Text('识别原文，待核对：$resultText',
                      style: const TextStyle(color: Color(0xFF6B7280))),
                for (final warning in metricWarnings)
                  Text(warning,
                      style: const TextStyle(color: Color(0xFF6B4E16))),
                if ((report['image_url'] ?? '').toString().isNotEmpty)
                  TextButton.icon(
                    onPressed: () => showReportOriginal(
                        context, report['image_url'].toString(),
                        details: reportOcrDetails(report),
                        sourceBlocks: sourceBlocks),
                    icon: const Icon(Icons.image_outlined),
                    label: const Text('查看对应原图'),
                  ),
                if (evidence.isNotEmpty ||
                    reason.isNotEmpty ||
                    version.isNotEmpty ||
                    confidence != null ||
                    sourceBlocks.isNotEmpty ||
                    needsReview)
                  TextButton.icon(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        title: Text('${m['code'] ?? m['name'] ?? '该指标'}的原文依据'),
                        content: SingleChildScrollView(
                          child: SelectableText([
                            if (evidence.isNotEmpty) evidence,
                            if (reason.isNotEmpty) '核对说明：$reason',
                            if (comparisonNote.isNotEmpty)
                              '界限结果说明：$comparisonNote',
                            if (rawUnit.isNotEmpty) '单位识别原文：$rawUnit',
                            ...metricWarnings,
                            if (needsReview && reason.isEmpty)
                              '核对说明：该指标需要人工核对，系统未确认其正常或异常',
                            if (version.isNotEmpty) '解析版本：$version',
                            if (confidence is num)
                              'OCR文字置信度：${(confidence * 100).toStringAsFixed(0)}%（不是医学准确率）',
                            if (sourceBlocks.isNotEmpty)
                              '对应原图文字块：\n${sourceBlocks.map((block) => (block['text'] ?? '').toString()).where((text) => text.isNotEmpty).join('\n')}',
                            if (m['source_line'] != null)
                              '原文行号：${m['source_line']}',
                            if (m['source_lines'] is List &&
                                (m['source_lines'] as List).isNotEmpty)
                              '关联行号：${(m['source_lines'] as List).join('、')}',
                            if (evidence.isEmpty &&
                                reason.isEmpty &&
                                !needsReview)
                              '接口未返回原文或解析说明',
                          ].join('\n\n')),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            child: const Text('关闭'),
                          ),
                        ],
                      ),
                    ),
                    icon: const Icon(Icons.article_outlined),
                    label: Text(evidence.isNotEmpty ? '查看原文依据' : '查看解析信息'),
                  ),
              ])),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w700, color: color)),
        ]));
  }
}

class ReportJobStatusCard extends StatelessWidget {
  final Map<String, dynamic> job;
  final VoidCallback? onDismiss;
  final ValueChanged<Map<String, dynamic>>? onOpenReport;
  const ReportJobStatusCard(
      {super.key, required this.job, this.onDismiss, this.onOpenReport});

  @override
  Widget build(BuildContext context) {
    final retake =
        ReportRetake.fromPayload(job, (job['job_id'] ?? '').toString());
    final status = retake != null ? 'failed' : (job['status'] ?? '').toString();
    final title = retake != null
        ? '识别未完成，请重新拍摄'
        : switch (status) {
            'queued' => '排队中',
            'ocr' => '正在识别报告',
            'explaining' => '正在生成解读',
            'completed' => '处理完成，报告已保存',
            'failed' => '处理失败',
            'unavailable' => '任务暂不可用',
            _ => '等待报告任务状态',
          };
    final metrics = job['metrics'] is List ? job['metrics'] : const [];
    final report = <String, dynamic>{
      'metrics': metrics,
      'ocr_details': job['ocr_details'],
      'recognition_status': job['recognition_status'],
    };
    final savedReport = job['report'] is Map
        ? Map<String, dynamic>.from(job['report'] as Map)
        : null;
    final error = (job['error'] ?? '').toString().trim();
    final pollMessage = (job['poll_message'] ?? '').toString().trim();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border.all(color: const Color(0xFFD5DDE5)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (status == 'queued' || status == 'ocr' || status == 'explaining')
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          Expanded(
            child: Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, color: Color(0xFF212936))),
          ),
          if (onDismiss != null)
            IconButton(
              tooltip: '移除此任务状态',
              visualDensity: VisualDensity.compact,
              onPressed: onDismiss,
              icon: const Icon(Icons.close, size: 20),
            ),
        ]),
        if (status == 'explaining')
          const Text('已识别的指标可先查看，AI解读尚未完成。',
              style: TextStyle(color: Color(0xFF5B6572))),
        if (status == 'completed' && savedReport != null)
          Text('报告编号：${savedReport['id'] ?? '已保存'}',
              style: const TextStyle(color: Color(0xFF5B6572))),
        if (status == 'completed' &&
            savedReport != null &&
            savedReport['id'] != null &&
            onOpenReport != null)
          TextButton.icon(
            onPressed: () => onOpenReport!(savedReport),
            icon: const Icon(Icons.open_in_new),
            label: const Text('查看已保存报告'),
          ),
        if (error.isNotEmpty)
          Text(error,
              style: const TextStyle(color: Color(0xFF8B2D27), height: 1.4)),
        if (retake != null) ...[
          Text(retake.message,
              style: const TextStyle(color: Color(0xFF8B2D27))),
          const Text('本次没有生成已保存报告，可使用上方拍照或相册入口重新上传。'),
        ],
        if (status == 'failed' && metrics.isNotEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('以下阶段性指标仅供核对，本次没有生成已保存报告。',
                style: TextStyle(color: Color(0xFF8B2D27), height: 1.4)),
          ),
        if (pollMessage.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(pollMessage,
                style: const TextStyle(color: Color(0xFF6B7280), height: 1.4)),
          ),
        if (metrics.isNotEmpty) ...[
          const Divider(height: 18),
          ReportMetrics(report: report),
        ],
      ]),
    );
  }
}

Future<void> showReportDetails(
    BuildContext context, Map<String, dynamic> report) async {
  final createdAt = (report['created_at'] ?? '').toString();
  final date = createdAt.length >= 10 ? createdAt.substring(0, 10) : '';
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(date.isEmpty ? '体检报告' : date),
        if (report['id'] != null)
          Text('报告编号：${report['id']}',
              style: const TextStyle(fontSize: 14, color: Color(0xFF6B7280))),
      ]),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ReportMetrics(report: report),
            const SizedBox(height: 12),
            const Text('识别文字',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            SelectableText((report['ocr_text'] ?? '').toString()),
            const SizedBox(height: 12),
            const Text('健康建议',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            SelectableText((report['advice_text'] ?? '').toString()),
            if ((report['image_url'] ?? '').toString().isNotEmpty)
              TextButton.icon(
                  onPressed: () => showReportOriginal(
                      context, report['image_url'].toString(),
                      details: reportOcrDetails(report)),
                  icon: const Icon(Icons.image_outlined),
                  label: const Text('查看原图')),
            const SizedBox(height: 8),
            const Text(ApiService.disclaimer,
                style: TextStyle(fontSize: 14, color: Color(0xFF6B7280))),
          ]),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('关闭')),
      ],
    ),
  );
}

class AuthenticatedReportImage extends StatefulWidget {
  final String url;
  final Map<String, dynamic> details;
  final List<Map> sourceBlocks;
  const AuthenticatedReportImage(
      {super.key,
      required this.url,
      this.details = const {},
      this.sourceBlocks = const []});
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
    if (oldWidget.url != widget.url) {
      _image = ApiService.reportImageBytes(widget.url);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
        future: _image,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Column(children: [
              Text('原图加载失败：${ApiService.friendly(snapshot.error!)}'),
              TextButton(
                  onPressed: () => setState(() {
                        _image = ApiService.reportImageBytes(widget.url);
                      }),
                  child: const Text('重试')),
            ]);
          }
          if (!snapshot.hasData) {
            return const SizedBox(
                height: 100,
                child: Center(
                    child:
                        CircularProgressIndicator(color: Color(0xFF345C87))));
          }
          final picture = Image.memory(snapshot.data!,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Text('原图格式无法显示'));
          final width = widget.details['width'];
          final height = widget.details['height'];
          final polygons =
              reportEvidencePolygons(widget.details, widget.sourceBlocks);
          if (polygons.isEmpty || width is! num || height is! num) {
            return picture;
          }
          return AspectRatio(
            aspectRatio: width / height,
            child: CustomPaint(
              foregroundPainter: _ReportEvidencePainter(
                  polygons, Size(width.toDouble(), height.toDouble())),
              child: picture,
            ),
          );
        },
      );
}

/// Legacy crop/debug coordinates are intentionally never drawn on the original.
List<List<Offset>> reportEvidencePolygons(
    Map<String, dynamic> details, List<Map> blocks) {
  final width = details['width'], height = details['height'];
  if (details['coordinate_space'] != 'original_image_pixels' ||
      width is! num ||
      height is! num ||
      !width.isFinite ||
      !height.isFinite ||
      width <= 0 ||
      height <= 0) {
    return [];
  }
  final polygons = <List<Offset>>[];
  for (final block in blocks) {
    final polygon = block['polygon'];
    if (polygon is! List || polygon.length < 3) continue;
    final points = <Offset>[];
    for (final point in polygon) {
      if (point is! List ||
          point.length != 2 ||
          point[0] is! num ||
          point[1] is! num) {
        break;
      }
      final x = (point[0] as num).toDouble(), y = (point[1] as num).toDouble();
      if (!x.isFinite ||
          !y.isFinite ||
          x < 0 ||
          y < 0 ||
          x > width ||
          y > height) {
        break;
      }
      points.add(Offset(x, y));
    }
    if (points.length == polygon.length) polygons.add(points);
  }
  return polygons;
}

class _ReportEvidencePainter extends CustomPainter {
  final List<List<Offset>> polygons;
  final Size original;
  const _ReportEvidencePainter(this.polygons, this.original);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFB3261E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final points in polygons) {
      final path = Path();
      for (var i = 0; i < points.length; i++) {
        final point = Offset(points[i].dx * size.width / original.width,
            points[i].dy * size.height / original.height);
        if (i == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      canvas.drawPath(path..close(), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ReportEvidencePainter oldDelegate) =>
      oldDelegate.polygons != polygons || oldDelegate.original != original;
}

Future<void> showReportOriginal(BuildContext context, String url,
        {Map<String, dynamic> details = const {},
        List<Map> sourceBlocks = const []}) =>
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('报告原图'),
        content: SizedBox(
            width: 600,
            child: SingleChildScrollView(
                child: AuthenticatedReportImage(
                    url: url, details: details, sourceBlocks: sourceBlocks))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('关闭'))
        ],
      ),
    );
