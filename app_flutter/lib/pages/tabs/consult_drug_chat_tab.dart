import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../../services/api.dart';
import '../../theme.dart';
import '../../afu/afu_chat_page.dart';
import 'hub_pages.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import '../../theme.dart';

/// Day3咨询记录（audio_url相对路径需拼baseUrl）+ Day4查药/症状/报告/天气 + Day5问答
class ConsultsTab extends StatefulWidget {
  const ConsultsTab({super.key});
  @override
  State<ConsultsTab> createState() => _ConsultsTabState();
}

class _ConsultsTabState extends State<ConsultsTab> {
  List items = [];
  bool loading = true;
  bool uploading = false;

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
  void initState() { super.initState(); refresh(); }
  Future<void> refresh() async {
    try { items = await ApiService.consultList(); } catch (_) { items = []; }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('咨询记录', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('录音上传后家属端同步可见，可点播放链接收听', style: TextStyle(fontSize: 18)),
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
          return Card(child: ListTile(title: Text(title, style: const TextStyle(fontSize: 20)), subtitle: audio.isEmpty ? null : Text(audio), trailing: audio.isEmpty ? null : IconButton(icon: const Icon(Icons.play_arrow, size: 32), onPressed: () { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('音频地址：${ApiService.consultAudioUrl(audio)}'))); })));
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
  const SymptomTab({super.key});
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
    try { history = await ApiService.symptomHistory(); } catch (_) {}
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
  const ReportTab({super.key});
  @override
  State<ReportTab> createState() => _ReportTabState();
}

class _ReportTabState extends State<ReportTab> {
  List items = [];
  bool busy = false;
  @override
  void initState() { super.initState(); refresh(); }
  Future<void> refresh() async {
    try { items = await ApiService.reportList(); } catch (_) { items = []; }
    if (mounted) setState(() {});
  }

  Future<void> upload() async {
    final f = await ImagePicker().pickImage(source: ImageSource.camera);
    if (f == null) return;
    setState(() => busy = true);
    try {
      await ApiService.uploadReport(await f.readAsBytes(), f.name);
      refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('上传成功')));
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
          return Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text((m['created_at'] ?? '').toString(), style: const TextStyle(fontSize: 16, color: Colors.grey)),
            const SizedBox(height: 4),
            Text('识别：${m['ocr_text'] ?? ''}', style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 4),
            Text('建议：${m['advice_text'] ?? ''}', style: const TextStyle(fontSize: 18)),
            if ((m['image_url'] ?? '').toString().isNotEmpty)
              Text('原图：${ApiService.reportImageUrl((m['image_url'] ?? '').toString())}', style: const TextStyle(fontSize: 14, color: Colors.blue)),
          ])));
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
  void dispose() {
    inputC.dispose();
    super.dispose();
  }

  /// 快捷入口：0查药品 1问症状 2看报告 3语音咨询
  Future<void> onQuick(int i) async {
    if (i == 0) {
      HubNav.go(1, 'drugs');
      return;
    }
    if (i == 1) {
      inputC.text = '我想咨询一下这个症状';
      return;
    }
    if (i == 2) {
      _pickReport();
      return;
    }
    startHoldToTalk(autoSend: true);
  }

  Future<void> _pickReport() async {
    final src = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_library, size: 32),
            title: const Text('从相册选', style: TextStyle(fontSize: 20)),
            onTap: () => Navigator.of(context).pop(ImageSource.gallery),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera, size: 32),
            title: const Text('拍照', style: TextStyle(fontSize: 20)),
            onTap: () => Navigator.of(context).pop(ImageSource.camera),
          ),
        ]),
      ),
    );
    if (src == null || !mounted) return;
    final f = await ImagePicker().pickImage(source: src);
    if (f == null || !mounted) return;
    try {
      final r = await ApiService.uploadReport(await f.readAsBytes(), f.name);
      if (!mounted) return;
      final ocr = (r['ocr_text'] ?? '').toString();
      final adv = (r['advice_text'] ?? '').toString();
      showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('报告解读', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
              child: Text(ocr.isEmpty ? adv : '$ocr\n\n$adv',
                  style: const TextStyle(fontSize: 19, height: 1.5))),
          actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('知道了', style: TextStyle(fontSize: 19)))],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('上传失败：${ApiService.friendly(e)}')));
    }
  }

  Future<void> send(String text) async {
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
      final ok = await stt.initialize();
      if (!ok) throw Exception('init failed');
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
          if (res.finalResult && res.recognizedWords.trim().isNotEmpty) {
            if (_autoSend) {
              _autoSend = false;
              stopHoldToTalk();
              send(res.recognizedWords.trim());
            }
          }
        },
      );
    } catch (_) {
      if (mounted) {
        setState(() => listening = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('语音不可用，请打字提问')));
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
      onTipMore: () => HubNav.go(1, 'news'),
      textScale: fontBig ? 1.25 : 1.0,
      onSend: send,
      onVoiceStart: startHoldToTalk,
      onVoiceEnd: stopHoldToTalk,
      onToggleTextScale: () => setState(() => fontBig = !fontBig),
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
