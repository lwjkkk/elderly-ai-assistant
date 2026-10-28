import 'dart:async';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart' show XFile;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import 'api.dart';
import 'voice_temp_cleanup.dart';

const voiceTranscriptionMaxDuration = Duration(seconds: 60);
const voiceTranscriptionMaxBytes = 8 * 1024 * 1024;

class VoicePermissionException implements Exception {
  final bool permanentlyDenied;
  const VoicePermissionException({this.permanentlyDenied = false});
  @override
  String toString() => permanentlyDenied
      ? '麦克风权限已关闭，请到系统设置中允许后再录音。'
      : '需要麦克风权限才能录音，请允许访问或改用文字输入。';
}

abstract class VoiceAudioCapture {
  Future<void> start(String path, {required bool wav});
  Future<bool> supportsWav();
  Future<String?> stop();
  Future<void> cancel();
  Future<void> dispose();
}

class PlatformVoiceAudioCapture implements VoiceAudioCapture {
  final _recorder = AudioRecorder();
  @override
  Future<bool> supportsWav() => _recorder.isEncoderSupported(AudioEncoder.wav);
  @override
  Future<void> start(String path, {required bool wav}) => _recorder.start(
      RecordConfig(
          encoder: wav ? AudioEncoder.wav : AudioEncoder.aacLc,
          sampleRate: 16000,
          numChannels: 1),
      path: path);
  @override
  Future<String?> stop() => _recorder.stop();
  @override
  Future<void> cancel() => _recorder.cancel();
  @override
  Future<void> dispose() => _recorder.dispose();
}

typedef VoiceTranscriber = Future<String> Function(
    List<int> bytes, String filename,
    {required String purpose, CancelToken? cancelToken, String? expectedToken});

/// Captures temporary audio; the only network action is transcription, never chat/save.
class VoiceTranscriptionRecorder {
  VoiceTranscriptionRecorder({
    VoiceAudioCapture? capture,
    Future<void> Function()? permission,
    Future<String> Function(String filename)? temporaryPath,
    Future<Uint8List> Function(String path)? readBytes,
    Future<void> Function(String path)? removeFile,
    VoiceTranscriber? transcribe,
  })  : _capture = capture ?? PlatformVoiceAudioCapture(),
        _permission = permission ?? _checkPermission,
        _temporaryPath = temporaryPath ?? _createPath,
        _readBytes = readBytes ?? ((path) => XFile(path).readAsBytes()),
        _removeFile = removeFile ?? removeVoiceTemporaryFile,
        _transcribe = transcribe ?? ApiService.transcribeAudio;

  final VoiceAudioCapture _capture;
  final Future<void> Function() _permission;
  final Future<String> Function(String) _temporaryPath;
  final Future<Uint8List> Function(String) _readBytes;
  final Future<void> Function(String) _removeFile;
  final VoiceTranscriber _transcribe;
  String? _activePath;
  String? _sessionToken;
  bool _recording = false;
  bool _disposed = false;
  int _generation = 0;
  CancelToken? _request;
  Future<void>? _starting;
  Future<String?>? _stopping;

  bool get isRecording => _recording;

  static Future<void> _checkPermission() async {
    var status = await Permission.microphone.status;
    if (!status.isGranted) status = await Permission.microphone.request();
    if (!status.isGranted) {
      throw VoicePermissionException(
          permanentlyDenied: status.isPermanentlyDenied || status.isRestricted);
    }
  }

  static Future<String> _createPath(String filename) async =>
      kIsWeb ? filename : '${(await getTemporaryDirectory()).path}/$filename';

  Future<void> start() async {
    if (_disposed || _recording || _starting != null || _request != null) {
      return;
    }
    final generation = ++_generation;
    final future = _start(generation);
    _starting = future;
    try {
      await future;
    } finally {
      _starting = null;
    }
  }

  Future<void> _start(int generation) async {
    _sessionToken = await ApiService.getToken();
    if (_sessionToken == null || _sessionToken!.isEmpty) {
      throw StateError('请先登录后再使用语音转写。');
    }
    await _permission();
    if (generation != _generation) return;
    final wav = await _capture.supportsWav();
    if (generation != _generation) return;
    final path = await _temporaryPath(
        'voice_${DateTime.now().microsecondsSinceEpoch}.${wav ? 'wav' : 'm4a'}');
    if (generation != _generation) return;
    _activePath = path;
    try {
      await _capture.start(path, wav: wav);
      if (generation != _generation) {
        await _capture.cancel();
        await _cleanup(path);
        return;
      }
      _recording = true;
    } catch (_) {
      await _cleanup(path);
      rethrow;
    }
  }

  Future<String> stopAndTranscribe({required String purpose}) async {
    if (!_recording || _disposed) throw StateError('请先开始录音。');
    final generation = _generation;
    final ownedPath = _activePath;
    _recording = false;
    String? path;
    try {
      final stopping = _capture.stop();
      _stopping = stopping;
      path = await stopping;
      _stopping = null;
      if (generation != _generation) throw StateError('语音识别已取消。');
      // Web recorders may return a blob URL instead of the requested filename.
      path ??= ownedPath;
      if (path == null) throw StateError('没有录到声音，请重新录音。');
      final bytes = await _readBytes(path);
      if (generation != _generation) throw StateError('语音识别已取消。');
      if (bytes.isEmpty) throw StateError('没有录到声音，请重新录音。');
      if (bytes.length > voiceTranscriptionMaxBytes) {
        throw StateError('录音超过8MiB，请缩短录音后重试。');
      }
      final token = CancelToken();
      _request = token;
      final transcript = await _transcribe(
          bytes, ownedPath!.split(RegExp(r'[/\\]')).last,
          purpose: purpose, cancelToken: token, expectedToken: _sessionToken);
      if (generation != _generation ||
          await ApiService.getToken() != _sessionToken) {
        throw StateError('语音识别已取消或登录状态已变化。');
      }
      if (transcript.trim().isEmpty) {
        throw StateError('没有识别到清楚的语音，请重新录音或使用文字输入。');
      }
      return transcript.trim();
    } finally {
      if (generation == _generation) _request = null;
      if (path != null) await _cleanup(path);
      if (ownedPath != null && ownedPath != path) await _cleanup(ownedPath);
      if (_activePath == ownedPath) _activePath = null;
    }
  }

  Future<void> _cleanup(String path) async {
    try {
      await _removeFile(path);
    } catch (_) {}
  }

  Future<void> cancel() async {
    ++_generation;
    _request?.cancel('Voice transcription cancelled');
    _request = null;
    try {
      await _starting;
    } catch (_) {}
    try {
      await _stopping;
    } catch (_) {}
    _stopping = null;
    if (_recording) {
      _recording = false;
      try {
        await _capture.cancel();
      } catch (_) {}
    }
    final path = _activePath;
    _activePath = null;
    if (path != null) await _cleanup(path);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await cancel();
    await _capture.dispose();
  }
}

String voiceTranscriptionError(Object error) {
  if (error is VoicePermissionException) return error.toString();
  final status = ApiService.statusOf(error);
  // FastAPI validation arrays and HTML errors must never appear as raw text.
  final detail = error is DioException && error.response?.data is Map
      ? (error.response!.data as Map)['detail']
      : null;
  final message =
      detail is String && detail.trim().isNotEmpty ? detail.trim() : null;
  switch (status) {
    case 401:
      return '登录状态已失效，请重新登录后再使用语音转写。';
    case 400:
      return message ?? '没有录到声音，请重新录音。';
    case 413:
      return message ?? '录音超过大小限制，请缩短后重试。';
    case 415:
      return message ?? '录音格式暂不支持，请重新录音或使用文字输入。';
    case 422:
      return message ?? '录音内容或参数未通过校验，请重新录音或使用文字输入。';
    case 429:
      final retry = error is DioException
          ? int.tryParse(error.response?.headers.value('retry-after') ?? '')
          : null;
      return '${message ?? '语音服务正忙'}${retry != null && retry > 0 ? '，请在 $retry 秒后手动重试。' : '，请稍后手动重试。'}';
    case 502:
    case 503:
      return message ?? '语音服务暂不可用，请使用文字输入或稍后重试。';
    case 504:
      return message ?? '语音识别超时，请重新录音或使用文字输入。';
  }
  if (error is DioException &&
      [
        DioExceptionType.receiveTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.connectionTimeout
      ].contains(error.type)) {
    return '语音识别超时，请重新录音或使用文字输入。';
  }
  return error is StateError ? error.message : '语音识别未完成，请检查网络后重试或使用文字输入。';
}
