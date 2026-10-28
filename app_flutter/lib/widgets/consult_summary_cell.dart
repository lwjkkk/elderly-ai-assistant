import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api.dart';

/// Shared by elder consultations and both sections of the family overview.
class ConsultSummaryCell extends StatefulWidget {
  final Map<String, dynamic> record;
  const ConsultSummaryCell({super.key, required this.record});
  @override
  State<ConsultSummaryCell> createState() => _ConsultSummaryCellState();
}

class _ConsultSummaryCellState extends State<ConsultSummaryCell> {
  late Map<String, dynamic> _record;
  Timer? _timer;
  bool _requesting = false;
  int _polls = 0;
  String? _error;
  bool get _working =>
      ['pending', 'processing'].contains(_record['summary_status']);
  @override
  void initState() {
    super.initState();
    _record = Map.of(widget.record);
    if (_working) _schedule();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 4), _poll);
  }

  Future<void> _poll() async {
    try {
      final response =
          await ApiService.dio.get('/api/consults/${_record['id']}/summary');
      if (!mounted) return;
      setState(() {
        _record = Map<String, dynamic>.from(response.data as Map);
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = ApiService.friendly(e));
    }
    if (!mounted) return;
    if (_working && ++_polls < 150) {
      _schedule();
    } else if (_working) {
      setState(() => _error = '生成时间较长，请点击重试');
    }
  }

  Future<void> _generate() async {
    setState(() {
      _requesting = true;
      _error = null;
    });
    try {
      final response =
          await ApiService.dio.post('/api/consults/${_record['id']}/summarize');
      if (!mounted) return;
      setState(() => _record = Map<String, dynamic>.from(response.data as Map));
      _polls = 0;
      if (_working) _schedule();
    } catch (e) {
      if (mounted) setState(() => _error = ApiService.friendly(e));
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = (_record['summary'] ?? '').toString().trim();
    if (summary.isNotEmpty) {
      return InkWell(
        onTap: () => showDialog<void>(
            context: context,
            builder: (c) => AlertDialog(
                  title: const Text('AI摘要'),
                  content:
                      SingleChildScrollView(child: SelectableText(summary)),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(c),
                        child: const Text('关闭'))
                  ],
                )),
        child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(summary, maxLines: 3, overflow: TextOverflow.ellipsis),
                const Text('查看全文',
                    style: TextStyle(fontSize: 13, color: Color(0xFFD48792)))
              ],
            )),
      );
    }
    final error = _error ?? (_record['summary_error'] as String?);
    return Padding(
        padding: const EdgeInsets.all(4),
        child: Column(children: [
          if (error != null)
            Text(error,
                style: const TextStyle(fontSize: 13, color: Colors.black54)),
          if (_working && error == null)
            const Text('正在转写并生成摘要…', style: TextStyle(fontSize: 14))
          else
            TextButton(
                onPressed: _requesting ? null : _generate,
                style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFD48792)),
                child: Text(_requesting
                    ? '提交中…'
                    : error == null
                        ? '生成摘要'
                        : '重试摘要')),
        ]));
  }
}
