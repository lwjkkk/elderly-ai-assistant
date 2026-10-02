import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../../services/api.dart';
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

/// Day5 问事助手：只支持文字或语音提问，不支持图片
/// （视觉模型幻觉严重，图片入口已下线；查药/报告拍照走专用OCR接口）
class ChatTab extends StatefulWidget {
  const ChatTab({super.key});
  @override
  State<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<ChatTab> {
  static final msgs = <Map<String, String>>[];
  final c = TextEditingController();
  bool busy = false;
  bool listening = false;

  Future<void> send() async {
    final t = c.text.trim();
    if (t.isEmpty || busy) return;
    setState(() {
      msgs.add({'role': 'me', 'text': t});
      msgs.add({'role': 'thinking', 'text': ''});
      busy = true;
    });
    c.clear();
    try {
      final r = await ApiService.chat(t);
      final raw = (r['answer'] ?? '').toString();
      var stepsSuffix = '';
      final sl = r['steps'];
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

  Future<void> startHoldToTalk() async {
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
      if (mounted) setState(() => listening = true);
      await stt.listen(
        localeId: locale ?? 'zh-CN',
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 30),
        partialResults: true,
        onResult: (res) {
          c.text = res.recognizedWords;
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
    return Container(
      color: AppColors.bg,
      child: Column(children: [
      const Padding(
        padding: EdgeInsets.all(8),
        child: Text('问事页v2 只支持文字提问', style: TextStyle(fontSize: 16, color: Colors.grey)),
      ),
      Expanded(child: msgs.isEmpty
          ? const Center(child: Text('在下方输入问题开始咨询', style: TextStyle(fontSize: 20)))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: msgs.length,
              itemBuilder: (c, i) {
                final m = msgs[i];
                if (m['role'] == 'thinking') {
                  return const Align(
                    alignment: Alignment.centerLeft,
                    child: Card(
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3)),
                          SizedBox(width: 12),
                          Text('正在思考…', style: TextStyle(fontSize: 20)),
                        ]),
                      ),
                    ),
                  );
                }
                final me = m['role'] == 'me';
                return Align(
                  alignment: me ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                    decoration: BoxDecoration(
                      color: me ? AppColors.primary : Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: me
                          ? null
                          : [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, 2))],
                    ),
                    child: Text(
                      m['text'] ?? '',
                      style: TextStyle(fontSize: 17, color: me ? Colors.white : AppColors.ink, height: 1.4),
                    ),
                  ),
                );
              },
            )),
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Expanded(
            child: GestureDetector(
              onLongPressStart: (_) => startHoldToTalk(),
              onLongPressEnd: (_) => stopHoldToTalk(),
              child: TextField(
                controller: c,
                decoration: InputDecoration(
                  hintText: '请在这里输入问题，长按可语音输入',
                  border: const OutlineInputBorder(),
                  suffixIcon: GestureDetector(
                    onLongPressStart: (_) => startHoldToTalk(),
                    onLongPressEnd: (_) => stopHoldToTalk(),
                    child: Icon(
                      listening ? Icons.mic : Icons.mic_none,
                      color: listening ? Colors.red : null,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(onPressed: busy ? null : send, child: Text(busy ? '…' : '发送')),
        ]),
      ),
      ]),
    );
  }
}

/// Day4 天气提醒：GET /api/weather/remind?city&lat&lon
class WeatherCard extends StatelessWidget {
  const WeatherCard({super.key});
  Future<Map<String, dynamic>> _load() => ApiService.weatherRemind(city: '武汉');
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _load(),
      builder: (c, s) {
        if (!s.hasData) return const SizedBox.shrink();
        final d = s.data!;
        return Card(
          color: Colors.blue[50],
          child: ListTile(
            leading: const Icon(Icons.cloud, size: 36),
            title: Text('${d['city'] ?? ''} ${d['text'] ?? ''}', style: const TextStyle(fontSize: 20)),
            subtitle: Text((d['tip'] ?? '').toString(), style: const TextStyle(fontSize: 18)),
          ),
        );
      },
    );
  }
}
