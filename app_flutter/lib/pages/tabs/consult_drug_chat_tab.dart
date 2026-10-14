import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../services/api.dart';
import '../../services/answer_speech.dart';
import '../../services/drug_question.dart';
import '../../theme.dart';
import '../../afu/afu_chat_page.dart';
import 'hub_pages.dart';
import 'vitals_tab.dart';
import 'health_record_style.dart';
import 'report_details.dart';
import 'package:geolocator/geolocator.dart';

/// Day3咨询记录（audio_url相对路径需拼baseUrl）+ Day4查药/症状/报告/天气 + Day5问答
class ConsultsTab extends StatefulWidget {
  final bool mine;
  const ConsultsTab({super.key, this.mine = false});
  @override
  State<ConsultsTab> createState() => _ConsultsTabState();
}

class _ConsultsTabState extends State<ConsultsTab> {
  List items = [];
  bool loading = true;
  bool uploading = false;
  final _player = AudioPlayer();
  String? _playing;

  Future<void> pickAndUpload() async {
    if (uploading) return;
    final r = await FilePicker.platform.pickFiles(type: FileType.audio, withData: true);
    final f = (r == null || r.files.isEmpty) ? null : r.files.first;
    if (f == null || f.bytes == null) return;
    setState(() => uploading = true);
    try {
      await ApiService.uploadConsult(f.bytes!, f.name);
      await refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('录音上传成功，家属端同步可见')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('上传失败，请重试')));
      }
    }
    if (mounted) setState(() => uploading = false);
  }
  @override
  void initState() {
    super.initState();
    refresh();
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = null);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  /// 问诊录音回放：点播放，再点停止。
  Future<void> _togglePlay(String url) async {
    try {
      if (_playing == url) {
        await _player.stop();
        if (mounted) setState(() => _playing = null);
        return;
      }
      await _player.stop();
      final bytes = await ApiService.consultAudioBytes(url);
      if (!mounted) return;
      await _player.play(BytesSource(bytes, mimeType: ApiService.audioMimeType(url)));
      if (mounted) setState(() => _playing = url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('播放失败：${ApiService.friendly(e)}')));
      }
    }
  }
  Future<void> refresh() async {
    try { items = await ApiService.consultList(mine: widget.mine); } catch (_) { items = []; }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return Center(child: CircularProgressIndicator(color: const Color(0xFF345C87)));
    return RefreshIndicator(
      color: const Color(0xFF345C87),
      onRefresh: refresh,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('问诊录音', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Color(0xFF222222))),
        const SizedBox(height: 8),
        const Text('回放长辈与AI问事过程中的问诊录音', style: TextStyle(fontSize: 18, color: Color(0xFF222222))),
        const SizedBox(height: 8),
        SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: uploading ? null : pickAndUpload,
              icon: uploading
                  ? const SizedBox(width: 24, height: 24,
                      child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white))
                  : const Icon(Icons.mic, size: 28),
              label: const Text('上传录音', style: TextStyle(fontSize: 20)),
            ),
          ),
          const SizedBox(height: 8),
          if (items.isEmpty) const Text('暂无咨询记录', style: TextStyle(fontSize: 20)),
        ...items.map((e) {
          final m = Map<String, dynamic>.from(e as Map);
          final title = (m['hospital'] ?? m['doctor'] ?? m['created_at'] ?? '一条咨询').toString();
          final audio = (m['audio_url'] ?? '').toString();
          final full = audio.isEmpty ? '' : ApiService.consultAudioUrl(audio);
          final playing = _playing != null && _playing == full;
          return Card(child: ListTile(title: Text(title, style: const TextStyle(fontSize: 20)), subtitle: audio.isEmpty ? null : Text(audio), trailing: audio.isEmpty ? null : IconButton(icon: Icon(playing ? Icons.stop_circle : Icons.play_arrow, size: 32), onPressed: () => _togglePlay(full))));
        }),
      ]),
    );
  }
}

class DrugQueryTab extends StatefulWidget {
  const DrugQueryTab({super.key});
  @override
  State<DrugQueryTab> createState() => _DrugQueryTabState();
}

class _DrugQueryTabState extends State<DrugQueryTab> {
  final nameC = TextEditingController();
  String result = '';
  bool busy = false;

  Future<void> byName() async {
    if (nameC.text.trim().isEmpty) return;
    setState(() { busy = true; result = '查询中…'; });
    try {
      final r = await ApiService.queryDrugByName(nameC.text.trim());
      result = '识别：${r['ocr_text'] ?? ''}\n\n解读：${r['explanation'] ?? r}\n\n${r['disclaimer'] ?? ApiService.disclaimer}';
    } catch (e) { result = '查询失败：${ApiService.friendly(e)}'; }
    if (mounted) setState(() => busy = false);
  }

  Future<void> byPhoto() async {
    if (busy) return;
    setState(() { busy = true; result = '识别中…'; });
    try {
      final f = await ImagePicker().pickImage(source: ImageSource.camera);
      if (f == null) return;
      final r = await ApiService.queryDrugByImage(await f.readAsBytes(), fileName: f.name);
      result = '识别：${r['ocr_text'] ?? ''}\n\n解读：${r['explanation'] ?? r}\n\n${r['disclaimer'] ?? ApiService.disclaimer}';
    } catch (e) { result = '识别失败：${ApiService.friendly(e)}'; }
    finally { if (mounted) setState(() => busy = false); }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('查药助手', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      TextField(controller: nameC, decoration: const InputDecoration(labelText: '输入药名', border: OutlineInputBorder())),
      const SizedBox(height: 12),
      ElevatedButton(onPressed: busy ? null : byName, child: const Text('输药名查询')),
      const SizedBox(height: 8),
      OutlinedButton.icon(onPressed: busy ? null : byPhoto, icon: const Icon(Icons.camera_alt), label: const Text('拍照识别药盒')),
      const SizedBox(height: 12),
      Card(child: Padding(padding: const EdgeInsets.all(12), child: Text(result.isEmpty ? '结果显示在这里' : result, style: const TextStyle(fontSize: 20)))),
    ]);
  }
}

/// Day4 症状自查：POST {input_text} → {advice_text,risk}，red/yellow/green 三色展示
class SymptomTab extends StatefulWidget {
  final bool mine;
  const SymptomTab({super.key, this.mine = false});
  @override
  State<SymptomTab> createState() => _SymptomTabState();
}

class _SymptomTabState extends State<SymptomTab> {
  final c = TextEditingController();
  List history = [];
  Map<String, dynamic>? last;
  bool busy = false;

  @override
  void initState() { super.initState(); loadHistory(); }
  Future<void> loadHistory() async {
    try { history = await ApiService.symptomHistory(mine: widget.mine); } catch (_) {}
    if (mounted) setState(() {});
  }

  Color riskColor(String r) {
    if (r == 'red') return Colors.red;
    if (r == 'yellow') return Colors.orange;
    return Colors.green;
  }

  Future<void> submit() async {
    if (c.text.trim().isEmpty || busy) return;
    setState(() => busy = true);
    try {
      last = await ApiService.symptomCheck(c.text.trim());
      loadHistory();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('提交失败：${ApiService.friendly(e)}')));
      }
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('症状自查', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
      TextField(controller: c, maxLines: 3, decoration: const InputDecoration(hintText: '描述症状，如最近总是头晕…', border: OutlineInputBorder())),
      const SizedBox(height: 12),
      ElevatedButton(onPressed: submit, child: Text(busy ? '分析中…' : '提交自查')),
      if (last != null) ...[
        const SizedBox(height: 12),
        Card(
          color: riskColor((last!['risk'] ?? 'green').toString()).withOpacity(0.12),
          child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('风险：${last!['risk']}', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: riskColor((last!['risk'] ?? '').toString()))),
            const SizedBox(height: 8),
            Text((last!['advice_text'] ?? '').toString(), style: const TextStyle(fontSize: 20)),
            if ((last!['risk'] ?? '') == 'red') const Text('请立即拨打120', style: TextStyle(fontSize: 22, color: Colors.red, fontWeight: FontWeight.bold)),
            if ((last!['risk'] ?? '') == 'yellow') const Text('建议尽快就医', style: TextStyle(fontSize: 20, color: Colors.orange)),
          ])),
        ),
      ],
      const SizedBox(height: 12),
      const Text('历史记录', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
      ...history.map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        return Card(child: ListTile(title: Text((m['input_text'] ?? '').toString(), style: const TextStyle(fontSize: 18)), subtitle: Text((m['advice_text'] ?? '').toString(), maxLines: 2, overflow: TextOverflow.ellipsis), trailing: Icon(Icons.circle, color: riskColor((m['risk'] ?? 'green').toString()))));
      }),
      const Padding(padding: EdgeInsets.only(top: 8), child: Text(ApiService.disclaimer, style: TextStyle(fontSize: 14, color: Colors.grey))),
    ]);
  }
}

/// Day4 体检报告：multipart上传 → ocr_text + advice_text；原图拼 baseUrl
class ReportTab extends StatefulWidget {
  final bool mine;
  const ReportTab({super.key, this.mine = false});
  @override
  State<ReportTab> createState() => _ReportTabState();
}

class _ReportTabState extends State<ReportTab> {
  List items = [];
  bool loading = true;
  bool busy = false;
  String? error;

  @override
  void initState() { super.initState(); refresh(); }

  Future<void> refresh() async {
    if (!mounted) return;
    setState(() { loading = true; error = null; });
    try {
      final result = await ApiService.reportList(mine: widget.mine);
      if (mounted) setState(() => items = result);
    } catch (e) {
      if (mounted) setState(() => error = ApiService.friendly(e));
    } finally { if (mounted) setState(() => loading = false); }
  }

  Future<void> upload(ImageSource source) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final file = await ImagePicker().pickImage(source: source, maxWidth: 2000);
      if (file == null) return;
      await ApiService.uploadReport(await file.readAsBytes(), file.name, mine: widget.mine);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('报告已上传并完成解读')));
      await refresh();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('上传失败：${ApiService.friendly(e)}')));
    } finally { if (mounted) setState(() => busy = false); }
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    color: HealthRecordStyle.primary,
    onRefresh: refresh,
    child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), children: [
      Row(children: [
        Expanded(child: HealthRecordStyle.button(busy ? '处理中…' : '拍照上传', Icons.camera_alt_outlined, busy ? null : () => upload(ImageSource.camera))),
        const SizedBox(width: 12),
        Expanded(child: HealthRecordStyle.button('相册上传', Icons.photo_library_outlined, busy ? null : () => upload(ImageSource.gallery))),
      ]),
      const SizedBox(height: 16),
      if (busy) const Padding(padding: EdgeInsets.only(bottom: 16), child: Column(children: [
        LinearProgressIndicator(color: HealthRecordStyle.primary, backgroundColor: HealthRecordStyle.soft),
        SizedBox(height: 8),
        Text('正在识别并解读报告，请稍候', style: TextStyle(color: HealthRecordStyle.secondary)),
      ])),
      HealthRecordStyle.panel(loading ? const SizedBox(height: 190, child: Center(child: CircularProgressIndicator(color: HealthRecordStyle.primary)))
        : error != null ? Column(children: [Text('加载失败：$error'), HealthRecordStyle.button('重试', Icons.refresh, refresh)])
        : items.isEmpty ? HealthRecordStyle.empty(Icons.description_outlined, '暂无报告信息')
        : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final item in items) ...[
            Text('${item['created_at'] ?? ''}'.replaceAll('T', ' '), style: const TextStyle(fontSize: 16, color: HealthRecordStyle.secondary)),
            const SizedBox(height: 8),
            ReportMetrics(report: Map<String, dynamic>.from(item as Map)),
            const SizedBox(height: 12),
            Text((item['advice_text'] ?? '').toString().trim().isEmpty ? '暂无解读建议' : item['advice_text'].toString(),
              style: const TextStyle(fontSize: 19, height: 1.6, color: HealthRecordStyle.ink)),
            const SizedBox(height: 12),
            if ((item['image_url'] ?? '').toString().isNotEmpty)
              TextButton.icon(
                onPressed: () => showReportOriginal(context, item['image_url'].toString()),
                icon: const Icon(Icons.image_outlined), label: const Text('查看原图')),
            const Text(ApiService.disclaimer, style: TextStyle(fontSize: 15, color: HealthRecordStyle.secondary)),
            const Divider(height: 32, color: HealthRecordStyle.border),
          ],
        ])),
    ]),
  );
}

/// Day5 问事助手：柔和风 UI（AfuElderChatPage），逻辑复用原有 send/语音/天气。
class ChatTab extends StatefulWidget {
  const ChatTab({super.key});
  @override
  State<ChatTab> createState() => _ChatTabState();
}

final re_step = RegExp('第[一二三四五六七八九十]+步|步骤');

class _ChatTabState extends State<ChatTab> {
  static final msgs = <Map<String, String>>[];
  final inputC = TextEditingController();
  bool busy = false;
  bool listening = false;
  bool fontBig = false;
  late final AnswerSpeech _speech;
  bool _voiceStarting = false;
  int _voiceGeneration = 0;
  String? _historyKey;
  @override
  void initState() {
    super.initState();
    _speech = AnswerSpeech(onError: (text) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    })..addListener(_speechChanged);
    _loadScale();
    _loadHistory();
    chatScale.addListener(_applyScale);
  }
  Future<void> _loadHistory() async {
    final id = await ApiService.getUserId();
    final role = await ApiService.getRole() ?? 'unknown';
    _historyKey = 'ai_chat_${role}_${id ?? 'legacy'}';
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_historyKey!);
      final decoded = raw == null ? <dynamic>[] : jsonDecode(raw) as List;
      msgs
        ..clear()
        ..addAll(decoded.map((e) => Map<String, String>.from(e as Map)));
      if (mounted) setState(() {});
    } catch (_) {
      msgs.clear();
    }
  }

  Future<void> _saveHistory() async {
    final key = _historyKey;
    if (key == null) return;
    final stable = msgs.where((m) => m['role'] != 'thinking').toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(stable));
  }
  Future<void> _loadScale() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      chatScale.value = prefs.getDouble('chat_text_scale') ?? 1.0;
    } catch (_) {}
  }
  void _applyScale() {
    if (mounted) setState(() => fontBig = chatScale.value > 1.05);
  }

  void _speechChanged() { if (mounted) setState(() {}); }

  @override
  void dispose() {
    ++_voiceGeneration;
    unawaited(_activeStt?.cancel().catchError((_) {}) ?? Future<void>.value());
    _speech.removeListener(_speechChanged);
    _speech.dispose();
    chatScale.removeListener(_applyScale);
    inputC.dispose();
    super.dispose();
  }

  /// 快捷卡片：0 体征（直接进体征记录页，支持上传/查看）
  ///           1 报告（直接进体检报告解读页，支持上传） 2 咨询录音
  /// 症状描述走输入框/语音，命中关键词时自动调专用自查接口。
  Future<void> onQuick(int i) async {
    final role = await ApiService.getRole();
    if (!mounted) return;
    if (role == 'family') {
      HubNav.go(0, i == 0 ? 'mine_vitals' : i == 1 ? 'mine_reports' : 'mine_consults');
      return;
    }
    if (i == 0) {
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const HealthRecordPage(child: VitalsTab())));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => HealthRecordPage(child: i == 1 ? const ReportTab() : const ConsultsTab())));
  }

  /// 症状关键词：命中则走专用自查接口并展示风险等级，而非普通问答。
  static const _symptomKeys = [
    '头晕', '头痛', '头疼', '发烧', '发热', '咳嗽', '胸闷', '心慌', '心悸',
    '气短', '腹痛', '肚子疼', '胃疼', '恶心', '呕吐', '腹泻', '失眠',
    '乏力', '疼痛', '麻木', '发麻', '水肿', '感冒', '咽痛', '牙疼',
    '腰疼', '腿疼', '背疼', '不舒服', '难受', '眩晕', '耳鸣', '皮疹',
  ];

  bool _looksLikeSymptom(String t) {
    if (t.length > 60) return false;
    for (final k in _symptomKeys) {
      if (t.contains(k)) return true;
    }
    return false;
  }

  Future<void> send(String text) async {
    final t = text.trim();
    if (t.isEmpty || busy || !mounted) return;
    setState(() => busy = true);
    await stopHoldToTalk();
    await _speech.stop();
    if (!mounted) return;
    setState(() {
      msgs.add({'role': 'me', 'text': t});
      msgs.add({'role': 'thinking', 'text': ''});
      busy = true;
    });
    String answer;
    try {
      final drug = drugQueryName(t);
      // 后端统一生成 kind=chat 的查药记录，并执行摘要同步隐私规则。
      if (drug == null && _looksLikeSymptom(t)) {
        try {
          final r = await ApiService.symptomCheck(t);
          final risk = (r['risk'] ?? 'green').toString();
          final tag = risk == 'red' ? '高风险' : risk == 'yellow' ? '中风险' : '低风险';
          final tail = risk == 'red' ? '\n请立即拨打120' : risk == 'yellow' ? '\n建议尽快就医' : '';
          answer = '【症状自查·$tag】\n${r['advice_text'] ?? ''}$tail\n${r['disclaimer'] ?? ApiService.disclaimer}';
        } catch (_) {
          // 同一条提问回退到普通问答，不重复插入消息，也不被 busy 挡住。
          answer = _formatChat(await ApiService.chat(t));
        }
      } else {
        answer = _formatChat(await ApiService.chat(t));
      }
    } catch (e) {
      answer = '出错了：${ApiService.friendly(e)}';
    }
    msgs.removeWhere((m) => m['role'] == 'thinking');
    msgs.add({'role': 'ai', 'text': answer});
    await _saveHistory();
    if (!mounted) return;
    setState(() => busy = false);
    unawaited(_speech.play(msgs.length - 1, answer));
  }

  String _formatChat(Map<String, dynamic> result) {
    final raw = (result['answer'] ?? '').toString();
    if (re_step.hasMatch(raw) || result['steps'] is! List) return raw;
    final missing = (result['steps'] as List).map((s) => s.toString())
        .where((s) => s.isNotEmpty && !raw.contains(s)).toList();
    return missing.isEmpty ? raw : '$raw\n\n步骤：\n${missing.map((s) => '• $s').join('\n')}';
  }

  SpeechToText? _activeStt;

  bool _autoSend = false;

  Future<void> startHoldToTalk({bool autoSend = false}) async {
    if (listening || _voiceStarting || busy) return;
    final generation = ++_voiceGeneration;
    setState(() => _voiceStarting = true);
    await _speech.stop();
    try {
      final stt = _activeStt ??= SpeechToText();
      // speech_to_text 是单例，initialize 成功后不会重绑回调；每次进入页面都重新绑定。
      stt.errorListener = (e) {
        if (mounted) {
          setState(() => listening = false);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
            e.errorMsg.contains('permission') ? '请允许麦克风权限后重试' : '语音识别中断，请重试或手动输入')));
        }
      };
      stt.statusListener = (status) {
        if (mounted && (status == SpeechToText.doneStatus || status == SpeechToText.notListeningStatus)) {
          setState(() => listening = false);
        }
      };
      final ok = await stt.initialize(onError: stt.errorListener, onStatus: stt.statusListener)
          .timeout(const Duration(seconds: 8), onTimeout: () => false);
      if (!mounted || generation != _voiceGeneration) return;
      if (!ok) throw StateError('语音识别不可用');
      String? locale;
      final locales = await stt.locales();
      for (final l in locales) {
        if (l.localeId.startsWith('zh')) { locale = l.localeId; break; }
      }
      if (!mounted || generation != _voiceGeneration) return;
      _autoSend = autoSend;
      setState(() => listening = true);
      await stt.listen(
        localeId: locale,
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 5),
        listenOptions: SpeechListenOptions(partialResults: true, cancelOnError: true, listenMode: ListenMode.dictation),
        onResult: (res) {
          if (!mounted || generation != _voiceGeneration) return;
          final words = res.recognizedWords.trim();
          if (words.isEmpty) return;
          inputC.value = TextEditingValue(text: words, selection: TextSelection.collapsed(offset: words.length));
          if (_autoSend && res.finalResult) {
            _autoSend = false;
            unawaited(send(words));
          }
        },
      );
    } catch (_) {
      if (mounted) {
        setState(() => listening = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('语音不可用，请检查麦克风权限和系统语音识别服务')));
      }
    } finally { if (mounted) setState(() => _voiceStarting = false); }
  }

  Future<void> stopHoldToTalk() async {
    if (_voiceStarting) ++_voiceGeneration;
    try { await _activeStt?.stop(); } catch (_) {}
    if (mounted && listening) setState(() => listening = false);
  }

  @override
  Widget build(BuildContext context) {
    final items = <AfuMessage>[
      for (final m in msgs)
        if (m['role'] == 'thinking')
          const AfuMessage(text: '', isMe: false, thinking: true)
        else
          AfuMessage(text: m['text'] ?? '', isMe: m['role'] == 'me'),
    ];
    return AfuElderChatPage(
      messages: items,
      busy: busy,
      inputController: inputC,
      speakingMessage: _speech.messageIndex,
      speechPaused: _speech.paused,
      onToggleSpeech: (i) {
        if (i >= 0 && i < msgs.length && msgs[i]['role'] == 'ai') {
          unawaited(stopHoldToTalk().then((_) => _speech.toggle(i, msgs[i]['text'] ?? '')));
        }
      },
      onQuickEntry: onQuick,
      onTipMore: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AfuSubPage(title: '咨询记录', child: ConsultsTab()))),
      textScale: 1.0,
      onSend: send,
      onVoiceStart: startHoldToTalk,
      onVoiceEnd: stopHoldToTalk,
      voiceActive: listening || _voiceStarting,
      onToggleTextScale: () async {
        const steps = [1.0, 1.15, 1.3];
        var i = steps.indexWhere((s) => (s - chatScale.value).abs() < 0.01);
        final next = steps[(i + 1) % steps.length];
        chatScale.value = next;
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setDouble('chat_text_scale', next);
        } catch (_) {}
      },
      header: ValueListenableBuilder<bool>(
        valueListenable: tipIsWeather,
        builder: (_, isWx, __) => isWx ? const SizedBox.shrink() : const WeatherCard(),
      ),
    );
  }
}

class WeatherCard extends StatefulWidget {
  const WeatherCard({super.key});
  @override
  State<WeatherCard> createState() => _WeatherCardState();
}

class _WeatherCardState extends State<WeatherCard> {
  late final Future<_Weather?> _future = _load();

  static Future<_Weather?> _load() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.whileInUse ||
          perm == LocationPermission.always) {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.low,
          timeLimit: const Duration(seconds: 8),
        );
        final d = await ApiService.weatherRemind(lat: pos.latitude, lon: pos.longitude);
        if (_unconfigured(d)) return null;
        return _Weather(data: d, fromGps: true);
      }
    } catch (_) {}
    try {
      final d = await ApiService.weatherRemind(city: '武汉');
      if (_unconfigured(d)) return null;
      return _Weather(data: d, fromGps: false);
    } catch (_) {
      return null;
    }
  }

  static bool _unconfigured(Map<String, dynamic> d) {
    final tipAll = '${d['text'] ?? ''} ${d['tip'] ?? ''}';
    if (tipAll.contains('未配置') || tipAll.contains('API_KEY')) {
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_Weather?>(
      future: _future,
      builder: (c, s) {
        final w = s.data;
        if (w == null) return const SizedBox.shrink();
        final d = w.data;
        return Card(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: ListTile(
            leading: const Icon(Icons.cloud, size: 36, color: AppColors.primary),
            title: Text('${d['city'] ?? ''} ${d['text'] ?? ''}', style: AppText.body),
            subtitle: Text(
              '${(d['tip'] ?? '').toString()}${w.fromGps ? '' : '（定位失败，显示武汉）'}',
              style: AppText.secondary,
            ),
          ),
        );
      },
    );
  }
}

class _Weather {
  final Map<String, dynamic> data;
  final bool fromGps;
  const _Weather({required this.data, required this.fromGps});
}

class ChatHistory {
  static List<AfuMessage> get items {
    final out = <AfuMessage>[];
    for (final m in _ChatTabState.msgs) {
      if (m['role'] == 'thinking') continue;
      out.add(AfuMessage(text: m['text'] ?? '', isMe: m['role'] == 'me'));
    }
    return out;
  }
}
