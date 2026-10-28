import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'report_retake.dart';

class ReportJobStore {
  static Future<void> _claiming = Future.value();

  static Future<bool> claimRetake(String scope, String id) {
    final result = _claiming.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      final key = '${scope}_retake_seen';
      final seen = prefs.getStringList(key) ?? [];
      if (seen.contains(id)) return false;
      await prefs.setStringList(key, [...seen, id]);
      return true;
    });
    _claiming =
        result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  static Future<String> keyForScope({required bool mine}) async {
    final userId = await ApiService.getUserId();
    if (userId == null) throw StateError('登录状态已失效，请重新登录');
    final role = (await ApiService.getRole()) ?? 'unknown';
    final query = await ApiService.withElder({}, mine);
    final scope = query['elder_id']?.toString() ?? 'self';
    return 'report_jobs_v1_${role}_${userId}_$scope';
  }

  static Future<List<String>> load(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return List<String>.from(prefs.getStringList(key) ?? const []);
  }

  static Future<void> add(String key, String jobId) async {
    final prefs = await SharedPreferences.getInstance();
    final jobs = List<String>.from(prefs.getStringList(key) ?? const []);
    if (!jobs.contains(jobId)) jobs.add(jobId);
    await prefs.setStringList(key, jobs);
  }

  static Future<void> remove(String key, String jobId) async {
    final prefs = await SharedPreferences.getInstance();
    final jobs = List<String>.from(prefs.getStringList(key) ?? const []);
    jobs.remove(jobId);
    await prefs.setStringList(key, jobs);
  }
}

class ReportJobTracker extends ChangeNotifier {
  ReportJobTracker({required this.mine, this.onReportSaved});

  final bool mine;
  final VoidCallback? onReportSaved;
  final Map<String, Map<String, dynamic>> _jobs = {};
  final List<String> _order = [];
  final Map<String, Timer> _timers = {};
  final Map<String, int> _failures = {};
  final Set<String> _polling = {};
  String? _storageKey;
  bool _disposed = false;
  bool ready = false;
  bool submitting = false;
  String? submissionError;
  final List<ReportRetake> retakes = [];
  String? get storageKey => _storageKey;

  void consumeRetake(ReportRetake retake) => retakes.remove(retake);

  void _recordRetake(Map<String, dynamic> payload, String id) {
    final retake = ReportRetake.fromPayload(payload, id);
    if (retake != null && !retakes.any((item) => item.id == id)) {
      retakes.add(retake);
    }
  }

  List<Map<String, dynamic>> get jobs => [
        for (final id in _order)
          if (_jobs[id] != null) _jobs[id]!,
      ];

  Future<void> restore() async {
    try {
      _storageKey = await ReportJobStore.keyForScope(mine: mine);
      final ids = await ReportJobStore.load(_storageKey!);
      for (final id in ids) {
        _order.add(id);
        _jobs[id] = {
          'job_id': id,
          'status': 'queued',
          'poll_message': '正在恢复任务状态',
        };
      }
      _notify();
      for (final id in ids) {
        unawaited(_poll(id));
      }
    } catch (e) {
      submissionError = e is StateError ? e.message : '无法读取未完成的报告任务';
    } finally {
      ready = true;
      _notify();
    }
  }

  Future<void> submit(List<int> bytes, String fileName) async {
    if (submitting || _disposed) return;
    submitting = true;
    submissionError = null;
    _notify();
    try {
      _storageKey ??= await ReportJobStore.keyForScope(mine: mine);
      final created =
          await ApiService.createReportJob(bytes, fileName, mine: mine);
      final jobId = (created['job_id'] ?? '').toString();
      if (jobId.isEmpty) throw StateError('服务未返回报告任务编号');
      try {
        await ReportJobStore.add(_storageKey!, jobId);
      } catch (_) {
        submissionError = '任务已接收，但本机无法保存任务编号；当前页面将继续查询，请勿重复上传。';
      }
      _order.remove(jobId);
      _order.insert(0, jobId);
      _jobs[jobId] = created;
      _recordRetake(created, jobId);
      _notify();
      if (ReportRetake.fromPayload(created, jobId) == null) {
        _schedule(jobId, _serverDelay(created));
      }
    } catch (e) {
      final retake = ReportRetake.fromError(
          e, 'upload-${DateTime.now().microsecondsSinceEpoch}');
      if (retake != null) {
        retakes.add(retake);
        submissionError = retake.message;
      } else {
        submissionError = _uploadError(e);
      }
    } finally {
      submitting = false;
      _notify();
    }
  }

  Future<void> dismiss(String jobId) async {
    _timers.remove(jobId)?.cancel();
    if (_storageKey != null) {
      try {
        await ReportJobStore.remove(_storageKey!, jobId);
      } catch (_) {}
    }
    _jobs.remove(jobId);
    _order.remove(jobId);
    _notify();
  }

  Future<void> _poll(String jobId) async {
    if (_disposed || !_polling.add(jobId)) return;
    _timers.remove(jobId)?.cancel();
    try {
      final result = await ApiService.reportJobStatus(jobId);
      if (_disposed) return;
      final status = (result['status'] ?? '').toString();
      _jobs[jobId] = result;
      _failures.remove(jobId);
      _recordRetake(result, jobId);
      _notify();
      final retake = ReportRetake.fromPayload(result, jobId);
      if (status == 'completed' && retake == null) {
        if (_storageKey != null) {
          try {
            await ReportJobStore.remove(_storageKey!, jobId);
          } catch (_) {}
        }
        onReportSaved?.call();
      } else if (status != 'failed' && retake == null) {
        _schedule(jobId, _serverDelay(result));
      }
    } on DioException catch (e) {
      if (_disposed) return;
      final code = e.response?.statusCode;
      if (code == 401 ||
          code == 403 ||
          code == 404 ||
          code == 410 ||
          (code != null && code < 500 && code != 429)) {
        _jobs[jobId] = {
          'job_id': jobId,
          'status': 'unavailable',
          'error': _statusError(code),
        };
        if (_storageKey != null) {
          try {
            await ReportJobStore.remove(_storageKey!, jobId);
          } catch (_) {}
        }
        _notify();
      } else {
        _setPollError(jobId, '暂时无法查询任务状态，稍后会重试，不会重新上传');
        _schedule(jobId, _retryDelay(jobId, e.response?.headers));
      }
    } catch (_) {
      if (_disposed) return;
      _setPollError(jobId, '暂时无法查询任务状态，稍后会重试，不会重新上传');
      _schedule(jobId, _retryDelay(jobId, null));
    } finally {
      _polling.remove(jobId);
    }
  }

  void _setPollError(String jobId, String message) {
    _jobs[jobId] = {
      ...?_jobs[jobId],
      'job_id': jobId,
      'poll_message': message,
    };
    _notify();
  }

  Duration _serverDelay(Map<String, dynamic> response) {
    final raw = response['poll_after_ms'];
    final value = raw is num ? raw.toInt() : 1500;
    return Duration(milliseconds: value.clamp(1000, 30000).toInt());
  }

  Duration _retryDelay(String jobId, Headers? headers) {
    final attempt =
        _failures.update(jobId, (value) => value + 1, ifAbsent: () => 1);
    final retryAfter = int.tryParse(headers?.value('retry-after') ?? '');
    if (retryAfter != null) {
      return Duration(seconds: retryAfter.clamp(1, 60).toInt());
    }
    final seconds = 2 * (1 << (attempt - 1).clamp(0, 4));
    return Duration(seconds: seconds.clamp(2, 30).toInt());
  }

  void _schedule(String jobId, Duration delay) {
    if (_disposed) return;
    _timers.remove(jobId)?.cancel();
    _timers[jobId] = Timer(delay, () => unawaited(_poll(jobId)));
  }

  String _statusError(int? status) => switch (status) {
        401 => '登录状态已失效，请重新登录后刷新任务',
        403 => '当前账号无权查看该报告任务',
        404 => '报告任务不存在或已过期',
        410 => '对应报告已删除',
        _ => '报告任务暂不可用，请刷新报告历史',
      };

  String _uploadError(Object error) {
    if (error is DioException) {
      final detail = ApiService.errorDetail(error);
      final retryAfter = int.tryParse(
          error.response?.headers.value('retry-after')?.trim() ?? '');
      return switch (error.response?.statusCode) {
        400 => detail ?? '图片格式或内容无法识别，请上传 JPG、PNG 或 WEBP 原图',
        401 => '登录状态已失效，请重新登录后上传',
        403 => '当前账号无权为此长辈上传报告',
        413 => '图片超过20MB，本次未重复上传；请调整文件大小后重新提交',
        429 => retryAfter == null
            ? '报告处理任务较多，请稍后手动重新上传'
            : '报告处理任务较多，请在 $retryAfter 秒后手动重新上传',
        503 => detail ?? '报告处理服务暂不可用，请稍后手动重新上传',
        _ => '提交结果未确认，请先刷新报告历史，勿重复上传：${ApiService.friendly(error)}',
      };
    }
    return error is StateError
        ? error.message
        : '上传失败：${ApiService.friendly(error)}';
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    super.dispose();
  }
}
