import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../services/api.dart';
import '../../theme.dart';
import '../../afu/afu_chat_page.dart';
import 'hub_pages.dart';
import 'vitals_tab.dart';
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
      await _player.play(UrlSource(url));
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
    final f = await ImagePicker().pickImage(source: ImageSource.camera);
    if (f == null) return;
    setState(() { busy = true; result = '识别中…'; });
    try {
      final r = await ApiService.queryDrugByImage(await f.readAsBytes(), f.name);
      result = '识别：${r['ocr_text'] ?? ''}\n\n解读：${r['explanation'] ?? r}\n\n${r['disclaimer'] ?? ApiService.disclaimer}';
    } catch (e) { result = '识别失败：${ApiService.friendly(e)}'; }
    if (mounted) setState(() => busy = false);
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
  bool _showImage = false;
  bool busy = false;
String _adviceOnly(String s) {
    var x = s.replaceAll(RegExp(r'https?://\S+'), '');
    final keep = <String>[];
    for (final line in x.split('\n')) {
      final l = line.trim();
      if (l.isEmpty) continue;
      final cjk = RegExp(r'[\u4e00-\u9fff]').allMatches(l).length;
      if (cjk == 0) continue;
      final asc = RegExp(r'[A-Za-z]').allMatches(l).length;
      if (asc > cjk) continue;
      keep.add(l);
    }
    return keep.join('\n');
  }
  @override
  void initState() { super.initState(); refresh(); }
  Future<void> refresh() async {
    try { items = await ApiService.reportList(mine: widget.mine); } catch (_) { items = []; }
try { _showImage = await ApiService.getRole() != 'elder'; } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> upload() async {
    final f = await ImagePicker().pickImage(source: ImageSource.camera);
    if (f == null) return;
    setState(() => busy = true);
    try {
      await ApiService.uploadReport(await f.readAsBytes(), f.name, mine: widget.mine);
      refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(kIsWeb ? '当前浏览器不支持语音识别，请手动输入（建议用手机App）' : '上传成功')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('上传失败：${ApiService.friendly(e)}')));
      }
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: const Color(0xFF345C87),
      onRefresh: refresh,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [
          const Text('体检报告', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
          const Spacer(),
          ElevatedButton.icon(onPressed: busy ? null : upload, icon: const Icon(Icons.upload), label: Text(busy ? '上传中' : '拍照上传')),
        ]),
        const SizedBox(height: 8),
        if (items.isEmpty) const Text('暂无报告', style: TextStyle(fontSize: 20)),
        ...items.map((e) {
          final m = Map<String, dynamic>.from(e as Map);
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text((m['created_at'] ?? '').toString(), style: const TextStyle(fontSize: 16, color: Color(0xFF8A94A6))),
                const SizedBox(height: 6),
                Builder(builder: (c) {
                  final adv = _adviceOnly((m['advice_text'] ?? '').toString());
                  return Text(adv.isEmpty ? '暂暂有效建建诀' : adv, style: const TextStyle(fontSize: 19, height: 1.6, color: Color(0xFF222222)));
                }),
                if (_showImage && (m['image_url'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.network(
                      ApiService.reportImageUrl((m['image_url'] ?? '').toString()),
                      height: 190,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                ],
              ]),
            ),
          );
        }),
        const Padding(padding: EdgeInsets.only(top: 8), child: Text(ApiService.disclaimer, style: TextStyle(fontSize: 14, color: Colors.grey))),
      ]),
    );
  }
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
  @override
  void initState() {
    super.initState();
    _loadScale();
    chatScale.addListener(_applyScale);
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

  @override
  void dispose() {
    chatScale.removeListener(_applyScale);
    inputC.dispose();
    super.dispose();
  }

  /// 快捷卡片：0 体征（直接进体征记录页，支持上传/查看）
  ///           1 报告（直接进体检报告解读页，支持上传）
  /// 症状描述走输入框/语音，命中关键词时自动调专用自查接口。
  Future<void> onQuick(int i) async {
    if (i == 0) {
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const AfuSubPage(title: '体征', child: VitalsTab())));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => const AfuSubPage(title: '报告', child: ReportTab())));
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
    if (t.isEmpty || busy) return;
    if (_looksLikeSymptom(t)) {
      await _sendSymptom(t);
      return;
    }
    await _sendChat(t);
  }

  /// 症状自查：调专用接口，气泡内展示红黄绿风险 + 建议。
  Future<void> _sendSymptom(String t) async {
    setState(() {
      msgs.add({'role': 'me', 'text': t});
      msgs.add({'role': 'thinking', 'text': ''});
      busy = true;
    });
    try {
      final r = await ApiService.symptomCheck(t);
      final risk = (r['risk'] ?? 'green').toString();
      final advice = (r['advice_text'] ?? '').toString();
      final tag = risk == 'red'
          ? '【症状自查·高风险】'
          : risk == 'yellow'
              ? '【症状自查·中风险】'
              : '【症状自查·低风险】';
      final tail = risk == 'red'
          ? '\n请立即拨打120'
          : risk == 'yellow'
              ? '\n建议尽快就医'
              : '';
      msgs.removeWhere((m) => m['role'] == 'thinking');
      msgs.add({
        'role': 'ai',
        'text': '$tag\n${advice.isEmpty ? '已记录你的症状，请注意观察' : advice}$tail'
      });
    } catch (_) {
      msgs.removeWhere((m) => m['role'] == 'thinking');
      await _sendChat(t);
      return;
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _sendChat(String text) async {
    final t = text.trim();
    if (t.isEmpty || busy) return;
    setState(() {
      msgs.add({'role': 'me', 'text': t});
      msgs.add({'role': 'thinking', 'text': ''});
      busy = true;
    });
    try {
      final r = await ApiService.chat(t);
      final raw = (r['answer'] ?? '').toString();
      var stepsSuffix = '';
      final hasStepGuide = re_step.hasMatch(raw);
      final sl = (!hasStepGuide && r['steps'] is List) ? r['steps'] as List : const [];
      if (sl is List && sl.isNotEmpty) {
        final missing = sl.map((e) => e.toString()).where((s) => s.isNotEmpty && !raw.contains(s)).toList();
        if (missing.isNotEmpty) {
          stepsSuffix = '\n\n步骤：\n${missing.map((e) => '• $e').join('\n')}';
        }
      }
      msgs.removeWhere((m) => m['role'] == 'thinking');
      msgs.add({'role': 'ai', 'text': '$raw$stepsSuffix'});
    } catch (e) {
      msgs.removeWhere((m) => m['role'] == 'thinking');
      msgs.add({'role': 'ai', 'text': '出错了：${ApiService.friendly(e)}'});
    }
    if (mounted) setState(() => busy = false);
  }

  SpeechToText? _activeStt;

  bool _autoSend = false;

  Future<void> startHoldToTalk({bool autoSend = false}) async {
    if (listening) return;
    try {
      final stt = SpeechToText();
      var initErr = '';
      final ok = await stt
          .initialize(
            onError: (e) => initErr = e.errorMsg,
          )
          .timeout(const Duration(seconds: 8),
              onTimeout: () => false);
      if (!ok) {
        throw Exception(
            initErr.isEmpty ? 'init failed' : initErr);
      }
      String? locale;
      try {
        final locales = await stt.locales();
        for (final l in locales) {
          if (l.localeId.startsWith('zh')) { locale = l.localeId; break; }
        }
        locale ??= locales.isNotEmpty ? locales.first.localeId : null;
      } catch (_) {}
      _activeStt = stt;
      _autoSend = autoSend;
      if (mounted) setState(() => listening = true);
      await stt.listen(
        localeId: locale ?? 'zh-CN',
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 30),
        partialResults: true,
        onResult: (res) {
          final words = res.recognizedWords.trim();
          if (words.isEmpty) return;
          if (_autoSend) {
            if (res.finalResult) {
              _autoSend = false;
              stopHoldToTalk();
              send(words);
            }
            return;
          }
          // 手动模式：实时把识别文字填进输入框，松手即停、文字保留可编辑
          if (mounted) inputC.text = words;
        },
      );
    } catch (_) {
      if (mounted) {
        setState(() => listening = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('语音不可用，请检查麦克风权限')));
      }
    }
  }

  Future<void> stopHoldToTalk() async {
    try {
      await _activeStt?.stop();
    } catch (_) {}
    _activeStt = null;
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
      onQuickEntry: onQuick,
      onTipMore: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AfuSubPage(title: '咨询记录', child: ConsultsTab()))),
      textScale: 1.0,
      onSend: send,
      onVoiceStart: startHoldToTalk,
      onVoiceEnd: stopHoldToTalk,
      voiceActive: listening,
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
