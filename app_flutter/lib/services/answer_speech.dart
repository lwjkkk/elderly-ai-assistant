import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// 每条新回复按段落依次朗读，离页停止；历史消息仅在用户点击时重播。
class AnswerSpeech extends ChangeNotifier {
  final FlutterTts _tts;
  final ValueChanged<String>? onError;
  AnswerSpeech({FlutterTts? tts, this.onError}) : _tts = tts ?? FlutterTts() {
    _tts.setCompletionHandler(() {
      if (_disposed || paused || messageIndex == null) return;
      _part++;
      unawaited(_next(_generation));
    });
    _tts.setErrorHandler((_) => _fail());
  }

  int? messageIndex;
  bool paused = false;
  List<String> _parts = [];
  int _part = 0;
  int _generation = 0;
  bool _disposed = false;
  Future<void>? _ready;

  Future<void> _initialize() async {
    await _tts.setLanguage('zh-CN');
    await _tts.setSpeechRate(0.45);
    await _tts.setVolume(1.0);
    await _tts.awaitSpeakCompletion(false);
  }

  Future<void> play(int index, String text) async {
    if (_disposed) return;
    final generation = ++_generation;
    messageIndex = null;
    paused = false;
    try {
      await _tts.stop();
      await (_ready ??= _initialize());
      if (_disposed || generation != _generation) return;
      _parts = text
          .replaceAll(RegExp(r'[*#`]'), '')
          .split(RegExp(r'\n+'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      _part = 0;
      messageIndex = index;
      notifyListeners();
      await _next(generation);
    } catch (_) {
      if (!_disposed && generation == _generation) _fail();
    }
  }

  Future<void> _next(int generation) async {
    if (_disposed || generation != _generation || paused) return;
    if (_part >= _parts.length) {
      messageIndex = null;
      notifyListeners();
      return;
    }
    try {
      final result = await _tts.speak(_parts[_part]);
      if (result == 0 && !_disposed && generation == _generation) _fail();
    } catch (_) {
      if (!_disposed && generation == _generation) _fail();
    }
  }

  Future<void> toggle(int index, String text) async {
    if (_disposed) return;
    if (messageIndex != index) {
      await play(index, text);
      return;
    }
    if (paused) {
      paused = false;
      notifyListeners();
      await _next(_generation);
    } else {
      paused = true;
      notifyListeners();
      try {
        final result = await _tts.pause();
        if (result == 0) await _tts.stop();
      } catch (_) {
        try { await _tts.stop(); } catch (_) { _fail(); }
      }
    }
  }

  Future<void> stop() async {
    ++_generation;
    messageIndex = null;
    paused = false;
    if (!_disposed) notifyListeners();
    try {
      await _tts.stop();
    } catch (_) {}
  }

  void _fail() {
    if (_disposed) return;
    messageIndex = null;
    paused = false;
    notifyListeners();
    onError?.call('语音播报暂不可用，请检查设备是否支持中文语音');
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    unawaited(_tts.stop().catchError((_) => 0));
    super.dispose();
  }
}
