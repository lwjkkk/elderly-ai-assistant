import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../api.dart';
import 'voice_transcription.dart';

Future<String?> showVoiceRecording(BuildContext context,
        {required String purpose,
        VoiceTranscriptionRecorder Function()? recorderFactory,
        bool Function()? isOwnerActive}) =>
    showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => VoiceRecordingSheet(
            purpose: purpose,
            recorderFactory: recorderFactory,
            isOwnerActive: isOwnerActive));

/// Shared capture -> ASR -> editable confirmation flow for chat and vital drafts.
class VoiceRecordingSheet extends StatefulWidget {
  final String purpose;
  final VoiceTranscriptionRecorder Function()? recorderFactory;
  final bool Function()? isOwnerActive;
  const VoiceRecordingSheet(
      {super.key,
      required this.purpose,
      this.recorderFactory,
      this.isOwnerActive});
  @override
  State<VoiceRecordingSheet> createState() => _VoiceRecordingSheetState();
}

class _VoiceRecordingSheetState extends State<VoiceRecordingSheet>
    with WidgetsBindingObserver {
  late final VoiceTranscriptionRecorder _recorder;
  final _text = TextEditingController();
  Timer? _timer;
  Timer? _ownerWatch;
  String _phase = 'starting';
  String? _error;
  String? _sessionToken;
  bool _permissionBlocked = false;
  int _seconds = 0;
  int _generation = 0;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _recorder = widget.recorderFactory?.call() ?? VoiceTranscriptionRecorder();
    _ownerWatch = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted || _closing) return;
      if (widget.isOwnerActive?.call() == false ||
          ModalRoute.of(context)?.isCurrent == false) {
        _abort();
      }
    });
    unawaited(_start());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _abort();
    }
  }

  bool _current(int generation) => mounted && _generation == generation;

  Future<void> _start() async {
    final generation = ++_generation;
    _timer?.cancel();
    setState(() {
      _phase = 'starting';
      _error = null;
      _permissionBlocked = false;
      _seconds = 0;
    });
    try {
      _sessionToken = await ApiService.getToken();
      if (!_current(generation)) return;
      await _recorder.start();
      if (!_current(generation) || !_recorder.isRecording) return;
      setState(() => _phase = 'recording');
      _timer = Timer.periodic(const Duration(milliseconds: 250), (timer) {
        if (!_current(generation)) return;
        final elapsed = Duration(milliseconds: timer.tick * 250);
        setState(() => _seconds = elapsed.inSeconds.clamp(0, 60));
        if (elapsed >= voiceTranscriptionMaxDuration) unawaited(_stop());
      });
    } catch (error) {
      if (_current(generation)) _failed(error);
    }
  }

  Future<void> _stop() async {
    if (_phase != 'recording') return;
    final generation = ++_generation;
    _timer?.cancel();
    setState(() => _phase = 'transcribing');
    try {
      final text = await _recorder.stopAndTranscribe(purpose: widget.purpose);
      if (!_current(generation)) return;
      _text.text = text;
      setState(() => _phase = 'review');
    } catch (error) {
      if (_current(generation)) _failed(error);
    }
  }

  void _failed(Object error) {
    setState(() {
      _phase = 'failed';
      _error = voiceTranscriptionError(error);
      _permissionBlocked =
          error is VoicePermissionException && error.permanentlyDenied;
    });
  }

  void _abort() {
    if (_closing) return;
    _closing = true;
    ++_generation;
    _timer?.cancel();
    unawaited(_recorder.cancel());
    _ownerWatch?.cancel();
    if (mounted) {
      final route = ModalRoute.of(context);
      if (route?.isCurrent == true) {
        Navigator.of(context).pop();
      } else if (route != null && route.isActive) {
        Navigator.of(context).removeRoute(route);
      }
    }
  }

  Future<void> _useText() async {
    if (_phase != 'review' || _text.text.trim().isEmpty) return;
    setState(() => _phase = 'accepting');
    final generation = _generation;
    final token = await ApiService.getToken();
    if (!mounted || generation != _generation) return;
    if (token != _sessionToken || token == null) {
      _abort();
      return;
    }
    if (_closing) return;
    _closing = true;
    Navigator.of(context).pop(_text.text.trim());
  }

  @override
  void dispose() {
    ++_generation;
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _ownerWatch?.cancel();
    unawaited(_recorder.dispose());
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
              const Text('语音转文字',
                  style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              const Text('录音将上传后端并使用百炼云语音识别。请勿录入他人隐私；最多60秒。'),
              const SizedBox(height: 12),
              if (_phase == 'starting') const Text('正在准备麦克风…'),
              if (_phase == 'recording') ...[
                Text('正在录音 $_seconds / 60秒',
                    key: const ValueKey('voice-timer')),
                FilledButton.icon(
                    onPressed: _stop,
                    icon: const Icon(Icons.stop),
                    label: const Text('停止并识别')),
              ],
              if (_phase == 'transcribing') ...[
                const LinearProgressIndicator(),
                const Text('正在识别，可随时取消；不会自动发送或保存。'),
              ],
              if (_phase == 'review') ...[
                TextField(
                    key: const ValueKey('voice-transcript'),
                    controller: _text,
                    minLines: 2,
                    maxLines: 5,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                        labelText: '识别文字（可修改）', border: OutlineInputBorder())),
                const Text('请核对文字、数字、时间、药名，再提交；语音识别可能有误。'),
                FilledButton(
                    onPressed: _text.text.trim().isEmpty ? null : _useText,
                    child: const Text('使用核对后的文字')),
                const Text('填入后还需点击发送或更新草稿，体征正式保存仍需核对确认。'),
              ],
              if (_error != null)
                Text(_error!, style: const TextStyle(color: Color(0xFFB3261E))),
              if (_phase == 'failed') ...[
                if (_permissionBlocked)
                  const TextButton(
                      onPressed: openAppSettings, child: Text('打开麦克风设置')),
                TextButton(onPressed: _start, child: const Text('重新录音')),
              ],
              TextButton(onPressed: _abort, child: const Text('取消，使用文字输入')),
            ])),
      );
}

Future<void> applyVoiceTranscript(
    {required BuildContext context,
    required TextEditingController input,
    required String originalInput,
    required String transcript,
    required bool Function() isCurrent}) async {
  if (!context.mounted || !isCurrent()) return;
  var text = [input.text.trim(), transcript.trim()]
      .where((s) => s.isNotEmpty)
      .join(' ');
  if (input.text != originalInput) {
    final append = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('输入内容已变化'),
                content: const Text('是否将已核对的语音文字追加到当前输入？'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('取消')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('追加文字'))
                ]));
    if (!context.mounted || !isCurrent() || append != true) return;
    text = [input.text.trim(), transcript.trim()]
        .where((s) => s.isNotEmpty)
        .join(' ');
  }
  input.value = TextEditingValue(
      text: text, selection: TextSelection.collapsed(offset: text.length));
}
