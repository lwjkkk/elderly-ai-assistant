import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api.dart';
import '../services/report_job_tracker.dart';
import '../services/report_retake.dart';
import '../pages/tabs/report_details.dart';

class ReportJobUploadPanel extends StatefulWidget {
  final bool mine;
  final Color primary;
  final Color soft;
  final VoidCallback? onReportSaved;
  final ValueChanged<Map<String, dynamic>>? onOpenReport;

  const ReportJobUploadPanel({
    super.key,
    required this.mine,
    required this.primary,
    required this.soft,
    this.onReportSaved,
    this.onOpenReport,
  });

  @override
  State<ReportJobUploadPanel> createState() => _ReportJobUploadPanelState();
}

class _ReportJobUploadPanelState extends State<ReportJobUploadPanel> {
  late ReportJobTracker _tracker;
  bool _retakeDialogScheduled = false;

  @override
  void initState() {
    super.initState();
    _createTracker();
  }

  void _createTracker() {
    _tracker = ReportJobTracker(
        mine: widget.mine, onReportSaved: widget.onReportSaved);
    _tracker.addListener(_onTrackerChanged);
    unawaited(_tracker.restore());
  }

  void _onTrackerChanged() {
    if (!mounted) return;
    setState(() {});
    if (!_retakeDialogScheduled && _tracker.retakes.isNotEmpty) {
      _retakeDialogScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_showPendingRetakes());
      });
    }
  }

  Future<void> _showPendingRetakes() async {
    final tracker = _tracker;
    try {
      while (mounted &&
          identical(tracker, _tracker) &&
          tracker.retakes.isNotEmpty) {
        final retake = tracker.retakes.first;
        final scope = tracker.storageKey;
        final show =
            scope != null && await ReportJobStore.claimRetake(scope, retake.id);
        if (!mounted || !identical(tracker, _tracker)) return;
        tracker.consumeRetake(retake);
        if (!show) continue;
        final source = await showReportRetakeDialog(context, retake);
        if (!mounted || !identical(tracker, _tracker)) return;
        if (source != null) await _pickAndUpload(source);
      }
    } finally {
      _retakeDialogScheduled = false;
    }
  }

  @override
  void didUpdateWidget(covariant ReportJobUploadPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mine != widget.mine) {
      _tracker
        ..removeListener(_onTrackerChanged)
        ..dispose();
      _createTracker();
    }
  }

  @override
  void dispose() {
    _tracker
      ..removeListener(_onTrackerChanged)
      ..dispose();
    super.dispose();
  }

  Future<void> _pickAndUpload(ImageSource source) async {
    if (!_tracker.ready || _tracker.submitting) return;
    final tracker = _tracker;
    try {
      final image = await ImagePicker().pickImage(source: source);
      if (image == null || !mounted || !identical(tracker, _tracker)) return;
      final bytes = await image.readAsBytes();
      if (!mounted || !identical(tracker, _tracker)) return;
      await tracker.submit(bytes, image.name);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('选择图片失败：${ApiService.friendly(e)}')));
    }
  }

  ButtonStyle _buttonStyle() => ElevatedButton.styleFrom(
        backgroundColor: widget.soft,
        foregroundColor: widget.primary,
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      );

  @override
  Widget build(BuildContext context) {
    final disabled = !_tracker.ready || _tracker.submitting;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed:
                disabled ? null : () => _pickAndUpload(ImageSource.camera),
            style: _buttonStyle(),
            icon: const Icon(Icons.camera_alt_outlined),
            label: const Text('拍照上传'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ElevatedButton.icon(
            onPressed:
                disabled ? null : () => _pickAndUpload(ImageSource.gallery),
            style: _buttonStyle(),
            icon: const Icon(Icons.photo_outlined),
            label: const Text('相册上传'),
          ),
        ),
      ]),
      if (_tracker.submitting) ...[
        const SizedBox(height: 10),
        LinearProgressIndicator(
            color: widget.primary, backgroundColor: widget.soft),
        const SizedBox(height: 6),
        const Text('正在提交原图，请稍候', style: TextStyle(color: Color(0xFF5B6572))),
      ],
      if (_tracker.submissionError != null) ...[
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF5E5),
            border: Border.all(color: const Color(0xFFE7C77A)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(_tracker.submissionError!,
              style: const TextStyle(color: Color(0xFF6B4E16), height: 1.4)),
        ),
      ],
      for (final job in _tracker.jobs)
        ReportJobStatusCard(
          key: ValueKey(job['job_id']),
          job: job,
          onOpenReport: widget.onOpenReport,
          onDismiss: const {
            'completed',
            'failed',
            'unavailable',
          }.contains(job['status'])
              ? () =>
                  unawaited(_tracker.dismiss((job['job_id'] ?? '').toString()))
              : null,
        ),
    ]);
  }
}

Future<ImageSource?> showReportRetakeDialog(
        BuildContext context, ReportRetake retake) =>
    showDialog<ImageSource>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('识别未完成，请重新拍摄'),
        content: SingleChildScrollView(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(retake.message),
            const SizedBox(height: 12),
            for (final requirement in retake.requirements)
              Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('• $requirement')),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('稍后处理')),
          TextButton(
              onPressed: () => Navigator.pop(context, ImageSource.camera),
              child: const Text('重新拍摄')),
          TextButton(
              onPressed: () => Navigator.pop(context, ImageSource.gallery),
              child: const Text('重新选择图片')),
        ],
      ),
    );
