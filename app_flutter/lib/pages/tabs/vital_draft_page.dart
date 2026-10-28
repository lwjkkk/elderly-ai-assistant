import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/api.dart';
import '../../services/contest_answer.dart';
import '../../services/vital_validation.dart';
import '../../services/vital_notification_status.dart';
import '../../services/voice_transcription.dart';
import '../../services/voice_transcription_ui.dart';

/// 所有入口共用同一草稿会话；离页不确认，重新进入可继续。
class VitalDraftPage extends StatefulWidget {
  final String? initialText;
  final bool mine;
  final VoiceTranscriptionRecorder Function()? voiceRecorderFactory;
  const VitalDraftPage(
      {super.key,
      this.initialText,
      this.mine = true,
      this.voiceRecorderFactory});
  @override
  State<VitalDraftPage> createState() => _VitalDraftPageState();
}

class _VitalDraftPageState extends State<VitalDraftPage> {
  final _input = TextEditingController();
  Map<String, dynamic> _turn = {};
  bool _busy = true;
  bool _voiceBusy = false;
  int _voiceGeneration = 0;
  bool _synchronized = false;
  String? _error;
  String? _key;
  String _owner = '本人';
  int? _targetId;
  bool get _subjectConfirmed {
    final value = _turn['subject_confirmed'] ?? _draft['subject_confirmed'];
    return value == null || value == true;
  }

  bool get _hasMeasuredAt =>
      (_draft['measured_at'] ?? '').toString().trim().isNotEmpty;
  bool get _canConfirm =>
      _turn['can_confirm'] == true && _subjectConfirmed && _hasMeasuredAt;
  int? get _id => (_turn['session_id'] as num?)?.toInt();
  Map<String, dynamic> get _draft => answerMap(_turn['draft']);

  ({String value, String timezone})? _normalizeMeasuredAt(String input,
      {bool useNow = false}) {
    if (useNow) {
      return (value: DateTime.now().toUtc().toIso8601String(), timezone: 'UTC');
    }
    final normalized = input.trim().replaceFirst(' ', 'T');
    final parsed = DateTime.tryParse(normalized);
    if (parsed == null) return null;
    final explicitZone = RegExp(r'(Z|[+-]\d{2}:?\d{2})$', caseSensitive: false)
        .firstMatch(normalized)
        ?.group(1);
    if (explicitZone != null) {
      final value = normalized.replaceFirstMapped(
          RegExp(r'([+-]\d{2})(\d{2})$'), (match) => '${match[1]}:${match[2]}');
      // The backend uses an explicit ISO offset as authoritative. Keep the
      // separate timezone field a valid IANA name, never a numeric offset.
      return (value: value, timezone: 'Asia/Shanghai');
    }
    // Naive times are interpreted by the API in the selected IANA zone.
    return (value: parsed.toIso8601String(), timezone: 'Asia/Shanghai');
  }

  String _formatMeasuredAtForDisplay(dynamic raw) {
    final value = (raw ?? '').toString().trim();
    if (value.isEmpty) return value;
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return value;
    final shanghai = parsed.toUtc().add(const Duration(hours: 8));
    String twoDigits(int number) => number.toString().padLeft(2, '0');
    return '${shanghai.year}-${twoDigits(shanghai.month)}-${twoDigits(shanghai.day)} '
        '${twoDigits(shanghai.hour)}:${twoDigits(shanghai.minute)}:${twoDigits(shanghai.second)}';
  }

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final user = await ApiService.getUserId();
      final role = await ApiService.getRole();
      final targetArgs = await ApiService.withElder({}, widget.mine);
      final target = (targetArgs['elder_id'] as num?)?.toInt() ?? user;
      _targetId = target;
      _owner = widget.mine || role != 'family' ? '本人' : '当前绑定长辈';
      _key = 'vital_draft_${role}_${user}_$target';
      _turn = decodeAnswer(prefs.getString(_key!));
      if (_id != null) {
        // 新版走只读 GET；旧后端仅在路由不存在时回退空文本续读。
        try {
          _turn = await ApiService.getVitalDraft(_id!, mine: widget.mine);
        } catch (e) {
          final detail = ApiService.errorDetail(e);
          final legacyGetMissing = ApiService.statusOf(e) == 405 ||
              (ApiService.statusOf(e) == 404 &&
                  (detail == null || detail == 'Not Found'));
          if (!legacyGetMissing) rethrow;
          _turn = await ApiService.spokenVitalTurn('',
              sessionId: _id, mine: widget.mine);
        }
        _validateDraftTarget(_turn);
        _synchronized = true;
      }
      _input.text = widget.initialText ?? '';
      if (_input.text.trim().isNotEmpty) {
        if (!mounted) return;
        setState(() => _busy = false);
        await _send();
      }
    } catch (e) {
      _error = ApiService.friendly(e);
      // 已结束或不存在的会话允许重新开始；网络失败保留本地草稿以便重试。
      if ([400, 404].contains(ApiService.statusOf(e))) {
        _turn = {};
        if (_key != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove(_key!);
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() async {
    if (_busy || _voiceBusy) return;
    final text = _input.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
      _synchronized = false;
    });
    try {
      final turn = await ApiService.spokenVitalTurn(text,
          sessionId: _id, mine: widget.mine);
      _validateDraftTarget(turn);
      _turn = turn;
      _synchronized = true;
      if (_key != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_key!, jsonEncode(turn));
      }
      if (mounted) _input.clear();
    } catch (e) {
      _error = ApiService.friendly(e);
    } finally {
      if (mounted)
        setState(() {
          _busy = false;
        });
    }
  }

  void _validateDraftTarget(Map<String, dynamic> turn) {
    final returnedTarget = turn['elder_id'] ?? _draft['elder_id'];
    if (returnedTarget is num &&
        _targetId != null &&
        returnedTarget.toInt() != _targetId) {
      throw StateError('当前草稿属于另一条长辈记录，请切换绑定对象后再操作。');
    }
  }

  Future<void> _setSubjectConfirmed(bool confirmed) async {
    if (_busy || _id == null) return;
    final version = _turn['version'];
    if (version is! num) {
      setState(() => _error = '草稿版本信息缺失，请重新同步后再确认记录对象。');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _synchronized = false;
    });
    try {
      final turn = await ApiService.updateVitalDraft(
          _id!, {'version': version, 'subject_confirmed': confirmed},
          mine: widget.mine);
      _validateDraftTarget(turn);
      _turn = turn;
      _synchronized = true;
      if (_key != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_key!, jsonEncode(turn));
      }
    } catch (e) {
      _error = ApiService.friendly(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finish({required bool confirm}) async {
    if (_busy ||
        _voiceBusy ||
        (confirm && (!_synchronized || _id == null || !_canConfirm))) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_id != null) {
        if (confirm) {
          final result =
              await ApiService.confirmVitalDraft(_id!, mine: widget.mine);
          if (mounted) {
            // Hide the indeterminate progress animation while the result
            // dialog is open so it does not keep the page animating.
            setState(() => _busy = false);
            await _showConfirmationFeedback(result);
          }
        } else {
          await ApiService.cancelVitalDraft(_id!, mine: widget.mine);
        }
      }
      if (_key != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_key!);
      }
      if (mounted) Navigator.pop(context, confirm);
    } catch (e) {
      _error = '${ApiService.friendly(e)}。未确认成功，请保留草稿并核对体征记录后重试。';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showConfirmationFeedback(Map<String, dynamic> result) async {
    final status = vitalNotificationFeedback(result['notification_status']);
    await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
              title: const Text('体征记录已保存'),
              content: Text(status),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('知道了')),
              ],
            ));
  }

  Future<void> _voice() async {
    if (_busy || _voiceBusy) return;
    final generation = ++_voiceGeneration;
    final original = _input.text;
    final token = await ApiService.getToken();
    if (!mounted || generation != _voiceGeneration) return;
    setState(() => _voiceBusy = true);
    try {
      final text = await showVoiceRecording(context,
          purpose: 'vitals',
          recorderFactory: widget.voiceRecorderFactory,
          isOwnerActive: () => mounted && generation == _voiceGeneration);
      if (!mounted || generation != _voiceGeneration || text == null) return;
      if (await ApiService.getToken() != token || !mounted) return;
      await applyVoiceTranscript(
          context: context,
          input: _input,
          originalInput: original,
          transcript: text,
          isCurrent: () => mounted && generation == _voiceGeneration);
    } finally {
      if (mounted && generation == _voiceGeneration) {
        setState(() => _voiceBusy = false);
      }
    }
  }

  Future<void> _edit() async {
    final draft = _draft;
    final type = (draft['type'] ?? 'bp').toString();
    final first = TextEditingController(
        text: '${draft[type == 'bp' ? 'systolic' : 'value'] ?? ''}');
    final second = TextEditingController(text: '${draft['diastolic'] ?? ''}');
    final time = TextEditingController(
        text: _formatMeasuredAtForDisplay(draft['measured_at']));
    var contextValue = (draft['measurement_context'] ?? 'unknown').toString();
    var useNow = false;
    const contexts = {
      'unknown': '未注明',
      'fasting': '空腹',
      'postprandial': '餐后',
      'random': '随机'
    };
    String? editError;
    bool saving = false;
    final result = await showDialog<Map<String, dynamic>>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
              builder: (context, update) => AlertDialog(
                title: const Text('修改体征草稿'),
                content: SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(
                      '当前账号：$_owner${_targetId == null ? '' : '（账号 ID：$_targetId）'}'),
                  Text('单位：${draft['unit'] ?? '以服务端校验为准'}'),
                  TextField(
                      controller: first,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                          labelText: type == 'bp' ? '高压' : '数值')),
                  if (type == 'bp')
                    TextField(
                        controller: second,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: '低压')),
                  TextField(
                      controller: time,
                      enabled: !useNow,
                      decoration: const InputDecoration(
                          labelText: '测量时间 YYYY-MM-DD HH:mm',
                          hintText: '按中国标准时间解释；也可填 ISO 时区偏移')),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: useNow,
                    onChanged: (value) => update(() => useNow = value == true),
                    title: const Text('测量时间就是现在'),
                    subtitle: const Text('勾选后按当前 UTC 时刻记录'),
                  ),
                  if (type == 'bs')
                    DropdownButtonFormField<String>(
                        initialValue: contexts.containsKey(contextValue)
                            ? contextValue
                            : 'unknown',
                        items: contexts.entries
                            .map((e) => DropdownMenuItem(
                                value: e.key, child: Text(e.value)))
                            .toList(),
                        onChanged: (v) => update(() => contextValue = v!),
                        decoration: const InputDecoration(labelText: '测量场景')),
                  const Text('修改后先校验草稿，再由您确认保存。'),
                  if (editError != null)
                    Text(editError!, style: const TextStyle(color: Colors.red)),
                ])),
                actions: [
                  TextButton(
                      onPressed:
                          saving ? null : () => Navigator.pop(dialogContext),
                      child: const Text('返回')),
                  TextButton(
                      onPressed: saving
                          ? null
                          : () async {
                              final systolic = type == 'bp'
                                  ? int.tryParse(first.text.trim())
                                  : null;
                              final diastolic = type == 'bp'
                                  ? int.tryParse(second.text.trim())
                                  : null;
                              final value = type != 'bp'
                                  ? double.tryParse(first.text.trim())
                                  : null;
                              final error = validateVitalValues(type,
                                  systolic: systolic,
                                  diastolic: diastolic,
                                  value: value);
                              if (error != null) {
                                update(() => editError = error);
                                return;
                              }
                              final inputTime = time.text.trim();
                              final normalizedTime = useNow
                                  ? _normalizeMeasuredAt('', useNow: true)
                                  : inputTime.isEmpty
                                      ? null
                                      : _normalizeMeasuredAt(inputTime);
                              if (inputTime.isNotEmpty &&
                                  normalizedTime == null) {
                                update(() => editError =
                                    '请输入有效测量时间，例如 2026-10-22 08:30；如需指定时区，可填写 2026-10-22T08:30:00+08:00');
                                return;
                              }
                              if (_turn['version'] is! num) {
                                update(() => editError = '草稿版本信息缺失，请先重新同步草稿。');
                                return;
                              }
                              update(() {
                                saving = true;
                                editError = null;
                              });
                              if (mounted)
                                setState(() => _synchronized = false);
                              try {
                                Map<String, dynamic> turn;
                                try {
                                  turn = await ApiService.updateVitalDraft(
                                      _id!,
                                      {
                                        'version': _turn['version'],
                                        'type': type,
                                        'systolic': systolic,
                                        'diastolic': diastolic,
                                        'value': value,
                                        if (inputTime.isNotEmpty || useNow)
                                          'measured_at': normalizedTime?.value,
                                        if (inputTime.isNotEmpty || useNow)
                                          'timezone': normalizedTime?.timezone,
                                        if (type == 'bs')
                                          'measurement_context': contextValue,
                                      },
                                      mine: widget.mine);
                                } catch (e) {
                                  if (![
                                    404,
                                    405
                                  ].contains(ApiService.statusOf(e))) rethrow;
                                  if (inputTime.isNotEmpty &&
                                      (normalizedTime == null ||
                                          !_sameInstant(draft['measured_at'],
                                              normalizedTime.value))) {
                                    throw StateError(
                                        '当前服务器暂不支持逐项修改时间，请返回用口述补充时间，或在手动录入中填写日期。');
                                  }
                                  final label = {
                                    'bp': '血压',
                                    'bs': '血糖',
                                    'hr': '心率',
                                    'weight': '体重'
                                  }[type];
                                  turn = await ApiService.spokenVitalTurn(
                                      '$label ${first.text}${type == 'bp' ? '/${second.text}' : ''} ${draft['unit'] ?? ''} ${type == 'bs' ? contexts[contextValue] : ''}',
                                      sessionId: _id,
                                      mine: widget.mine);
                                }
                                final edited = answerMap(turn['draft']);
                                if ((type == 'bp' &&
                                        (edited['systolic'] != systolic ||
                                            edited['diastolic'] !=
                                                diastolic)) ||
                                    (type != 'bp' &&
                                        edited['value'] != value)) {
                                  throw StateError('服务器未能采纳修改，请返回用完整语句重新补充。');
                                }
                                if (type == 'bs' &&
                                    (edited['measurement_context'] ??
                                            'unknown') !=
                                        contextValue) {
                                  throw StateError('服务器未采纳血糖测量场景，请核对后重新补充。');
                                }
                                if ((inputTime.isNotEmpty || useNow) &&
                                    !_sameInstant(edited['measured_at'],
                                        normalizedTime!.value)) {
                                  throw StateError('服务器未采纳测量时间，请核对后重新补充。');
                                }
                                if (dialogContext.mounted)
                                  Navigator.pop(dialogContext, turn);
                              } catch (e) {
                                if (dialogContext.mounted)
                                  update(
                                      () => editError = ApiService.friendly(e));
                              } finally {
                                if (dialogContext.mounted)
                                  update(() => saving = false);
                              }
                            },
                      child: Text(saving ? '校验中…' : '校验修改')),
                ],
              ),
            ));
    if (result != null) {
      _turn = result;
      _synchronized = true;
      if (_key != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_key!, jsonEncode(result));
      }
      if (mounted) setState(() {});
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    first.dispose();
    second.dispose();
    time.dispose();
  }

  bool _sameInstant(dynamic actual, String expected) {
    DateTime? parseInstant(dynamic raw) {
      final text = '$raw'.trim();
      final parsed = DateTime.tryParse(text);
      if (parsed == null) return null;
      final hasOffset =
          RegExp(r'(Z|[+-]\d{2}:?\d{2})$', caseSensitive: false).hasMatch(text);
      if (hasOffset) return parsed.toUtc();
      // The editor's offset-free input is interpreted by the API as
      // Asia/Shanghai, independent of the device's local timezone.
      return DateTime.utc(parsed.year, parsed.month, parsed.day, parsed.hour,
              parsed.minute, parsed.second, parsed.millisecond)
          .subtract(const Duration(hours: 8));
    }

    final actualTime = parseInstant(actual);
    final expectedTime = parseInstant(expected);
    return actualTime != null &&
        expectedTime != null &&
        actualTime.toUtc().isAtSameMomentAs(expectedTime.toUtc());
  }

  @override
  void dispose() {
    ++_voiceGeneration;
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    final type = draft['type'];
    const names = {'bp': '血压', 'bs': '血糖', 'hr': '心率', 'weight': '体重'};
    return Scaffold(
      appBar: AppBar(title: const Text('体征草稿')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text('记录对象：$_owner',
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
        if (_targetId != null)
          Text('当前数据归属账号 ID：$_targetId', style: const TextStyle(fontSize: 16)),
        const SizedBox(height: 12),
        const Text('说出测量结果，核对后再保存。返回页面会保留草稿，不会自动写入体征记录。',
            style: TextStyle(fontSize: 18, height: 1.5)),
        if (_busy) const LinearProgressIndicator(),
        if (_id != null)
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            '${names[type] ?? '待确定类型'}：${type == 'bp' ? '${draft['systolic'] ?? '待补充'}/${draft['diastolic'] ?? '待补充'}' : draft['value'] ?? '待补充'} ${draft['unit'] ?? ''}',
                            style: const TextStyle(fontSize: 22)),
                        Text(
                            '测量时间：${_formatMeasuredAtForDisplay(draft['measured_at']).isNotEmpty ? _formatMeasuredAtForDisplay(draft['measured_at']) : draft['measured_text'] ?? '请补充'}',
                            style: const TextStyle(fontSize: 18)),
                        if (type == 'bs')
                          Text('血糖场景：${{
                                'fasting': '空腹',
                                'postprandial': '餐后',
                                'random': '随机'
                              }[draft['measurement_context']] ?? '未注明'}'),
                        if (draft['raw_text'] != null)
                          Text('原话：${draft['raw_text']}'),
                        if ((_turn['subject_label'] ?? '')
                            .toString()
                            .isNotEmpty)
                          Text('口述识别对象：${_turn['subject_label']}'),
                        TextButton.icon(
                            onPressed: _busy || type == null ? null : _edit,
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('修改数值和时间')),
                      ]))),
        if (_id != null)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _subjectConfirmed,
            onChanged: _busy
                ? null
                : (value) {
                    if (value != null) _setSubjectConfirmed(value);
                  },
            title: Text(
                '我已确认这条记录属于$_owner${_targetId == null ? '' : '（账号 ID：$_targetId）'}'),
            subtitle: const Text('如识别对象与当前账号不一致，请勿确认保存。'),
          ),
        const SizedBox(height: 12),
        Text((_turn['question'] ?? '例如：今天早上八点，我的血压高压130、低压80。').toString(),
            style: const TextStyle(fontSize: 20, height: 1.5)),
        TextField(
            controller: _input,
            enabled: !_busy,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(
                labelText: '补充或修改信息', hintText: '可以打字，也可以点话筒说话')),
        Wrap(spacing: 12, children: [
          TextButton.icon(
              onPressed: _busy || _voiceBusy ? null : _voice,
              icon: const Icon(Icons.mic_none),
              label: const Text('录音补充')),
          FilledButton(
              onPressed: _busy || _voiceBusy ? null : _send,
              child: const Text('更新草稿')),
        ]),
        const Text('请核对文字、数字、时间、药名后再更新草稿。'),
        if (_error != null)
          Text(_error!,
              style: const TextStyle(fontSize: 18, color: Colors.red)),
        if (_id != null && !_synchronized && !_busy)
          TextButton(onPressed: _restore, child: const Text('重新同步草稿')),
        const SizedBox(height: 24),
        FilledButton.icon(
            onPressed: !_busy && !_voiceBusy && _synchronized && _canConfirm
                ? () => _finish(confirm: true)
                : null,
            icon: const Icon(Icons.check),
            label: const Text('核对无误，确认保存')),
        if (_turn['can_confirm'] == true && !_hasMeasuredAt)
          const Text('请先修改草稿填写测量时间，或明确选择“测量时间就是现在”。',
              style: TextStyle(color: Color(0xFF9A6700))),
        if (_turn['can_confirm'] == true && !_subjectConfirmed)
          const Text('请先确认记录对象与当前账号一致。',
              style: TextStyle(color: Color(0xFF9A6700))),
        TextButton(
            onPressed: _busy ? null : () => _finish(confirm: false),
            child: const Text('取消并丢弃草稿')),
        const Text(ApiService.disclaimer),
      ]),
    );
  }
}
