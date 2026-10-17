import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:cross_file/cross_file.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../services/api.dart';
import '../../services/answer_speech.dart';
import '../../services/drug_question.dart';
import '../../services/location_access.dart';
import '../../services/chat_archive.dart';
import '../chat_history_page.dart';
import '../../theme.dart';
import '../../afu/afu_chat_page.dart';
import '../../afu/delete_confirm.dart';
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
  bool recording = false;
  final _recorder = AudioRecorder();
  final _player = AudioPlayer();
  String? _playing;

  Future<void> _toggleRecord() async {
    if (uploading) return;
    if (recording) {
      setState(() => uploading = true);
      try {
        final path = await _recorder.stop();
        if (mounted) setState(() => recording = false);
        if (path != null && mounted) await _saveRecording(path);
      } catch (_) {
        if (mounted)
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('录音保存失败，请重试')));
      } finally {
        if (mounted) setState(() => uploading = false);
      }
      return;
    }
    try {
      if (!await _recorder.hasPermission()) throw Exception('no permission');
      final ext = kIsWeb ? 'wav' : 'm4a';
      final name = 'consult_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final path =
          kIsWeb ? name : '${(await getTemporaryDirectory()).path}/$name';
      await _recorder.start(
          RecordConfig(encoder: kIsWeb ? AudioEncoder.wav : AudioEncoder.aacLc),
          path: path);
      if (mounted) setState(() => recording = true);
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('录音启动失败，请检查麦克风权限')));
    }
  }

  Future<void> _saveRecording(String path) async {
    final address = TextEditingController();
    final title = TextEditingController();
    final locationHint = await _suggestAddress();
    if (locationHint.startsWith('推荐地址：')) {
      address.text = locationHint.substring('推荐地址：'.length);
    }
    if (!mounted) return;
    final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
              backgroundColor: const Color(0xFFF9E7E9),
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
              contentPadding: const EdgeInsets.fromLTRB(24, 18, 24, 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28)),
              title: const Text('保存录音',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              content: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                _consultField(address, '地址', locationHint),
                const SizedBox(height: 20),
                _consultField(title, '标题', '请输入标题'),
              ])),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: const Text('取消',
                        style:
                            TextStyle(fontSize: 19, color: Color(0xFF333333)))),
                ElevatedButton(
                    onPressed: () => Navigator.pop(c, true),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD48792),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 30, vertical: 15),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16))),
                    child: const Text('上传',
                        style: TextStyle(
                            fontSize: 19, fontWeight: FontWeight.w700))),
              ],
            ));
    if (ok != true) return;
    final bytes = await XFile(path).readAsBytes();
    final ext = kIsWeb ? 'wav' : 'm4a';
    await ApiService.uploadConsult(
        bytes, 'consult_${DateTime.now().millisecondsSinceEpoch}.$ext',
        hospital: address.text.trim().isEmpty ? null : address.text.trim(),
        doctor: title.text.trim().isEmpty ? null : title.text.trim(),
        mine: widget.mine);
    await refresh();
    if (mounted)
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('录音已保存')));
  }

  Future<String> _suggestAddress() async {
    return LocationAccess.suggestAddress();
  }

  Widget _consultField(TextEditingController c, String label, String hint) =>
      TextField(
          controller: c,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
              labelText: label,
              hintText: hint,
              labelStyle: const TextStyle(
                  fontWeight: FontWeight.w700, color: Color(0xFFD48792)),
              hintStyle:
                  const TextStyle(color: Color(0xFFAAA5AA), fontSize: 16),
              filled: true,
              fillColor: Colors.white,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(18))));
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
    _recorder.dispose();
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
      await _player
          .play(BytesSource(bytes, mimeType: ApiService.audioMimeType(url)));
      if (mounted) setState(() => _playing = url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('播放失败：${ApiService.friendly(e)}')));
      }
    }
  }

  Future<void> refresh() async {
    try {
      items = await ApiService.consultList(mine: widget.mine);
    } catch (_) {
      items = [];
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _deleteConsult(Map<String, dynamic> item) async {
    final id = (item['id'] as num?)?.toInt();
    if (id == null) return;
    if (!await showDeleteConfirm(context, '这条咨询录音')) return;
    try {
      await ApiService.deleteConsult(id);
      await refresh();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('删除失败：${ApiService.friendly(e)}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading)
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFFD48792)));
    return Container(
      color: const Color(0xFFF7F8FA),
      child: RefreshIndicator(
        color: const Color(0xFFD48792),
        onRefresh: refresh,
        child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            children: [
              SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: uploading ? null : _toggleRecord,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF9E7E9),
                        foregroundColor: const Color(0xFF333333),
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18))),
                    icon: uploading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                                strokeWidth: 3, color: Color(0xFFD48792)))
                        : Icon(
                            recording
                                ? Icons.stop_circle
                                : Icons.mic_none_outlined,
                            color: const Color(0xFFD48792),
                            size: 28),
                    label: Text(recording ? '停止并保存' : '开始录音',
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w700)),
                  )),
              const SizedBox(height: 16),
              _consultTable(),
            ]),
      ),
    );
  }

  Widget _consultTable() {
    const border = Color(0xFFE5E7EB);
    if (items.isEmpty) {
      return Container(
          height: 310,
          decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: border),
              borderRadius: BorderRadius.circular(18)),
          child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.mic_none_outlined,
                    size: 58, color: Color(0xFFD48792)),
                SizedBox(height: 18),
                Text('暂无录音记录，点击记录就诊历史',
                    style: TextStyle(fontSize: 18, color: Color(0xFF888888))),
              ]));
    }
    Widget cell(String text,
            {FontWeight weight = FontWeight.w400,
            Color color = const Color(0xFF333333)}) =>
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
            child: Text(text,
                style: TextStyle(
                    fontSize: 17,
                    height: 1.4,
                    fontWeight: weight,
                    color: color)));
    return ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Container(
          decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: border),
              borderRadius: BorderRadius.circular(18)),
          child: Table(
              columnWidths: const {
                0: FlexColumnWidth(3),
                1: FlexColumnWidth(2),
                2: FlexColumnWidth(2),
                3: FlexColumnWidth(2)
              },
              border: const TableBorder(
                  horizontalInside: BorderSide(color: border)),
              children: [
                TableRow(
                    decoration: const BoxDecoration(color: Color(0xFFF9E7E9)),
                    children: [
                      for (final h in const ['标题', '时间', 'AI摘要', '地址'])
                        cell(h, weight: FontWeight.w700)
                    ]),
                for (final e in items)
                  _consultRow(Map<String, dynamic>.from(e as Map), cell),
              ]),
        ));
  }

  TableRow _consultRow(Map<String, dynamic> m,
      Widget Function(String, {FontWeight weight, Color color}) cell) {
    final audio = (m['audio_url'] ?? '').toString();
    final full = audio.isEmpty ? '' : ApiService.consultAudioUrl(audio);
    final date = (m['created_at'] ?? '').toString();
    final title = (m['doctor'] ?? '').toString().trim().isNotEmpty
        ? m['doctor'].toString()
        : '问诊录音${date.length >= 10 ? date.substring(0, 10) : ''}';
    final cells = <Widget>[
      Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(children: [
            Expanded(
                child: Text(title,
                    style: const TextStyle(fontSize: 17, height: 1.4))),
            if (full.isNotEmpty)
              IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: Icon(
                      _playing == full ? Icons.stop_circle : Icons.play_arrow,
                      color: const Color(0xFFD48792),
                      size: 27),
                  onPressed: () => _togglePlay(full)),
          ])),
      cell(date.length >= 10 ? date.substring(0, 10) : date),
      cell((m['summary'] ?? '—').toString(), color: const Color(0xFF888888)),
      cell((m['hospital'] ?? '').toString()),
    ];
    return TableRow(children: [
      for (final child in cells)
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onLongPress: () => _deleteConsult(m),
          child: child,
        ),
    ]);
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
    setState(() {
      busy = true;
      result = '查询中…';
    });
    try {
      final r = await ApiService.queryDrugByName(nameC.text.trim());
      result =
          '识别：${r['ocr_text'] ?? ''}\n\n解读：${r['explanation'] ?? r}\n\n${r['disclaimer'] ?? ApiService.disclaimer}';
    } catch (e) {
      result = '查询失败：${ApiService.friendly(e)}';
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> byPhoto() async {
    if (busy) return;
    setState(() {
      busy = true;
      result = '识别中…';
    });
    try {
      final f = await ImagePicker().pickImage(source: ImageSource.camera);
      if (f == null) return;
      final r = await ApiService.queryDrugByImage(await f.readAsBytes(),
          fileName: f.name);
      result =
          '识别：${r['ocr_text'] ?? ''}\n\n解读：${r['explanation'] ?? r}\n\n${r['disclaimer'] ?? ApiService.disclaimer}';
    } catch (e) {
      result = '识别失败：${ApiService.friendly(e)}';
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('查药助手',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      TextField(
          controller: nameC,
          decoration: const InputDecoration(
              labelText: '输入药名', border: OutlineInputBorder())),
      const SizedBox(height: 12),
      ElevatedButton(
          onPressed: busy ? null : byName, child: const Text('输药名查询')),
      const SizedBox(height: 8),
      OutlinedButton.icon(
          onPressed: busy ? null : byPhoto,
          icon: const Icon(Icons.camera_alt),
          label: const Text('拍照识别药盒')),
      const SizedBox(height: 12),
      Card(
          child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(result.isEmpty ? '结果显示在这里' : result,
                  style: const TextStyle(fontSize: 20)))),
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
  void initState() {
    super.initState();
    loadHistory();
  }

  Future<void> loadHistory() async {
    try {
      history = await ApiService.symptomHistory(mine: widget.mine);
    } catch (_) {}
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
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('提交失败：${ApiService.friendly(e)}')));
      }
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('症状自查',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
      TextField(
          controller: c,
          maxLines: 3,
          decoration: const InputDecoration(
              hintText: '描述症状，如最近总是头晕…', border: OutlineInputBorder())),
      const SizedBox(height: 12),
      ElevatedButton(onPressed: submit, child: Text(busy ? '分析中…' : '提交自查')),
      if (last != null) ...[
        const SizedBox(height: 12),
        Card(
          color: riskColor((last!['risk'] ?? 'green').toString())
              .withOpacity(0.12),
          child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('风险：${last!['risk']}',
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color:
                                riskColor((last!['risk'] ?? '').toString()))),
                    const SizedBox(height: 8),
                    Text((last!['advice_text'] ?? '').toString(),
                        style: const TextStyle(fontSize: 20)),
                    if ((last!['risk'] ?? '') == 'red')
                      const Text('请立即拨打120',
                          style: TextStyle(
                              fontSize: 22,
                              color: Colors.red,
                              fontWeight: FontWeight.bold)),
                    if ((last!['risk'] ?? '') == 'yellow')
                      const Text('建议尽快就医',
                          style: TextStyle(fontSize: 20, color: Colors.orange)),
                  ])),
        ),
      ],
      const SizedBox(height: 12),
      const Text('历史记录',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
      ...history.map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        return Card(
            child: ListTile(
                title: Text((m['input_text'] ?? '').toString(),
                    style: const TextStyle(fontSize: 18)),
                subtitle: Text((m['advice_text'] ?? '').toString(),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: Icon(Icons.circle,
                    color: riskColor((m['risk'] ?? 'green').toString()))));
      }),
      const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(ApiService.disclaimer,
              style: TextStyle(fontSize: 14, color: Colors.grey))),
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
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    if (!mounted) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await ApiService.reportList(mine: widget.mine);
      if (mounted) setState(() => items = result);
    } catch (e) {
      if (mounted) setState(() => error = ApiService.friendly(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> upload(ImageSource source) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final file =
          await ImagePicker().pickImage(source: source, maxWidth: 2000);
      if (file == null) return;
      await ApiService.uploadReport(await file.readAsBytes(), file.name,
          mine: widget.mine);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('报告已上传并完成解读')));
      await refresh();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('上传失败：${ApiService.friendly(e)}')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _deleteReport(Map<String, dynamic> item) async {
    final id = (item['id'] as num?)?.toInt();
    if (id == null || !await showDeleteConfirm(context, '这份报告')) return;
    try {
      await ApiService.deleteReport(id);
      await refresh();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('删除失败：${ApiService.friendly(e)}')));
    }
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        color: HealthRecordStyle.primary,
        onRefresh: refresh,
        child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              Row(children: [
                Expanded(
                    child: HealthRecordStyle.button(
                        busy ? '处理中…' : '拍照上传',
                        Icons.camera_alt_outlined,
                        busy ? null : () => upload(ImageSource.camera))),
                const SizedBox(width: 12),
                Expanded(
                    child: HealthRecordStyle.button(
                        '相册上传',
                        Icons.photo_library_outlined,
                        busy ? null : () => upload(ImageSource.gallery))),
              ]),
              const SizedBox(height: 16),
              if (busy)
                const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: Column(children: [
                      LinearProgressIndicator(
                          color: HealthRecordStyle.primary,
                          backgroundColor: HealthRecordStyle.soft),
                      SizedBox(height: 8),
                      Text('正在识别并解读报告，请稍候',
                          style: TextStyle(color: HealthRecordStyle.secondary)),
                    ])),
              HealthRecordStyle.panel(loading
                  ? const SizedBox(
                      height: 190,
                      child: Center(
                          child: CircularProgressIndicator(
                              color: HealthRecordStyle.primary)))
                  : error != null
                      ? Column(children: [
                          Text('加载失败：$error'),
                          HealthRecordStyle.button('重试', Icons.refresh, refresh)
                        ])
                      : items.isEmpty
                          ? HealthRecordStyle.empty(
                              Icons.description_outlined, '暂无报告信息')
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                  for (final item in items)
                                    GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onLongPress: () => _deleteReport(
                                          Map<String, dynamic>.from(
                                              item as Map)),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                              '${item['created_at'] ?? ''}'
                                                  .replaceAll('T', ' '),
                                              style: const TextStyle(
                                                  fontSize: 16,
                                                  color: HealthRecordStyle
                                                      .secondary)),
                                          const SizedBox(height: 8),
                                          ReportMetrics(
                                              report: Map<String, dynamic>.from(
                                                  item as Map)),
                                          const SizedBox(height: 12),
                                          Text(
                                              (item['advice_text'] ?? '')
                                                      .toString()
                                                      .trim()
                                                      .isEmpty
                                                  ? '暂无解读建议'
                                                  : item['advice_text']
                                                      .toString(),
                                              style: const TextStyle(
                                                  fontSize: 19,
                                                  height: 1.6,
                                                  color:
                                                      HealthRecordStyle.ink)),
                                          const SizedBox(height: 12),
                                          if ((item['image_url'] ?? '')
                                              .toString()
                                              .isNotEmpty)
                                            TextButton.icon(
                                                onPressed: () =>
                                                    showReportOriginal(
                                                        context,
                                                        item['image_url']
                                                            .toString()),
                                                icon: const Icon(
                                                    Icons.image_outlined),
                                                label: const Text('查看原图')),
                                          const Text(ApiService.disclaimer,
                                              style: TextStyle(
                                                  fontSize: 15,
                                                  color: HealthRecordStyle
                                                      .secondary)),
                                          const Divider(
                                              height: 32,
                                              color: HealthRecordStyle.border),
                                        ],
                                      ),
                                    ),
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
  final msgs = <Map<String, String>>[];
  final inputC = TextEditingController();
  bool busy = false;
  bool listening = false;
  bool fontBig = false;
  late final AnswerSpeech _speech;
  bool _voiceStarting = false;
  int _voiceGeneration = 0;
  String _voiceHint = '点按话筒开始说话，再点停止';
  String _voicePrefix = '';
  String? _historyKey;
  final _sessionId = DateTime.now().toIso8601String();
  late final Future<void> _historyReady;
  @override
  void initState() {
    super.initState();
    ChatHistory.current = [];
    _speech = AnswerSpeech(onError: (text) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(text)));
    })
      ..addListener(_speechChanged);
    _loadScale();
    _historyReady = _loadHistory();
    chatScale.addListener(_applyScale);
  }

  Future<void> _loadHistory() async {
    final id = await ApiService.getUserId();
    final role = await ApiService.getRole() ?? 'unknown';
    _historyKey = 'ai_chat_${role}_${id ?? 'legacy'}';
    try {
      await ChatArchive.migrate(_historyKey!);
    } catch (_) {
      msgs.clear();
    }
  }

  Future<void> _saveHistory() async {
    final key = _historyKey;
    if (key == null) return;
    final stable = msgs.where((m) => m['role'] != 'thinking').toList();
    ChatHistory.current = List<Map<String, String>>.from(stable);
    await ChatArchive.save(key, _sessionId, stable);
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

  void _speechChanged() {
    if (mounted) setState(() {});
  }

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
      HubNav.go(
          0,
          i == 0
              ? 'mine_vitals'
              : i == 1
                  ? 'mine_reports'
                  : 'mine_consults');
      return;
    }
    if (i == 0) {
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const HealthRecordPage(child: VitalsTab())));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => HealthRecordPage(
            child: i == 1 ? const ReportTab() : const ConsultsTab())));
  }

  /// 症状关键词：命中则走专用自查接口并展示风险等级，而非普通问答。
  static const _symptomKeys = [
    '头晕',
    '头痛',
    '头疼',
    '发烧',
    '发热',
    '咳嗽',
    '胸闷',
    '心慌',
    '心悸',
    '气短',
    '腹痛',
    '肚子疼',
    '胃疼',
    '恶心',
    '呕吐',
    '腹泻',
    '失眠',
    '乏力',
    '疼痛',
    '麻木',
    '发麻',
    '水肿',
    '感冒',
    '咽痛',
    '牙疼',
    '腰疼',
    '腿疼',
    '背疼',
    '不舒服',
    '难受',
    '眩晕',
    '耳鸣',
    '皮疹',
  ];

  bool _looksLikeSymptom(String t) {
    if (t.length > 60) return false;
    for (final k in _symptomKeys) {
      if (t.contains(k)) return true;
    }
    return false;
  }

  Future<void> send(String text) async {
    await _historyReady;
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
    await _saveHistory();
    String answer;
    try {
      final drug = drugQueryName(t);
      // 后端统一生成 kind=chat 的查药记录，并执行摘要同步隐私规则。
      if (drug == null && _looksLikeSymptom(t)) {
        try {
          final r = await ApiService.symptomCheck(t);
          final risk = (r['risk'] ?? 'green').toString();
          final tag = risk == 'red'
              ? '高风险'
              : risk == 'yellow'
                  ? '中风险'
                  : '低风险';
          final tail = risk == 'red'
              ? '\n请立即拨打120'
              : risk == 'yellow'
                  ? '\n建议尽快就医'
                  : '';
          answer =
              '【症状自查·$tag】\n${r['advice_text'] ?? ''}$tail\n${r['disclaimer'] ?? ApiService.disclaimer}';
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
    final missing = (result['steps'] as List)
        .map((s) => s.toString())
        .where((s) => s.isNotEmpty && !raw.contains(s))
        .toList();
    return missing.isEmpty
        ? raw
        : '$raw\n\n步骤：\n${missing.map((s) => '• $s').join('\n')}';
  }

  SpeechToText? _activeStt;
  Future<bool>? _sttInitialization;

  bool _autoSend = false;

  Future<bool> _ensureSpeechReady() {
    return _sttInitialization ??= () async {
      final stt = _activeStt ??= SpeechToText();
      stt.errorListener = (e) {
        if (!mounted) return;
        final permission = e.errorMsg.contains('permission');
        final noSpeech = e.errorMsg.contains('no_match') ||
            e.errorMsg.contains('speech_timeout');
        final message = permission
            ? '请在系统设置中允许麦克风权限'
            : noSpeech
                ? '没有听清，请点话筒后靠近手机说话'
                : '系统语音识别不可用（${e.errorMsg}），请检查语音服务和网络';
        setState(() {
          listening = false;
          _voiceHint = message;
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      };
      stt.statusListener = (status) {
        if (mounted &&
            (status == SpeechToText.doneStatus ||
                status == SpeechToText.notListeningStatus)) {
          setState(() {
            listening = false;
            _voiceHint = '点按话筒开始说话，再点停止';
          });
        }
      };
      return stt.initialize(
          onError: stt.errorListener,
          onStatus: stt.statusListener,
          options: [
            SpeechToText.androidIntentLookup,
            SpeechToText.androidNoBluetooth
          ]).timeout(const Duration(seconds: 10), onTimeout: () => false);
    }();
  }

  Future<void> startHoldToTalk({bool autoSend = false}) async {
    if (listening || _voiceStarting || busy) return;
    final generation = ++_voiceGeneration;
    setState(() {
      _voiceStarting = true;
      _voiceHint = '正在准备麦克风…';
    });
    try {
      await _speech
          .stop()
          .timeout(const Duration(seconds: 2), onTimeout: () {});
      final stt = _activeStt ??= SpeechToText();
      final ok = await _ensureSpeechReady();
      if (!mounted || generation != _voiceGeneration) return;
      if (!ok) {
        _sttInitialization = null;
        throw StateError('请允许麦克风权限，并在手机设置中启用系统语音识别服务');
      }
      String? locale = 'zh_CN';
      final locales = await stt
          .locales()
          .timeout(const Duration(seconds: 3), onTimeout: () => []);
      for (final l in locales) {
        final id = l.localeId.toLowerCase().replaceAll('-', '_');
        if (id == 'zh_cn' || id.startsWith('zh_hans') || id.startsWith('cmn')) {
          locale = l.localeId;
          break;
        }
      }
      if (!mounted || generation != _voiceGeneration) return;
      _autoSend = autoSend;
      _voicePrefix = inputC.text.trim();
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() {
        listening = true;
        _voiceHint = '正在听，请讲话；再点话筒停止';
      });
      await stt.listen(
        localeId: locale,
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 5),
        listenOptions: SpeechListenOptions(
            partialResults: true,
            cancelOnError: false,
            listenMode: ListenMode.dictation),
        onResult: (res) {
          if (!mounted || generation != _voiceGeneration) return;
          final words = res.recognizedWords.trim();
          if (words.isEmpty) return;
          final text = _voicePrefix.isEmpty ? words : '$_voicePrefix $words';
          setState(() {
            inputC.value = TextEditingValue(
                text: text,
                selection: TextSelection.collapsed(offset: text.length));
          });
          if (_autoSend && res.finalResult) {
            _autoSend = false;
            unawaited(send(words));
          }
        },
      );
    } catch (e) {
      if (mounted) {
        final message =
            e is StateError ? e.message : '语音启动失败，请检查麦克风权限和系统语音识别服务';
        setState(() {
          listening = false;
          _voiceHint = message;
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _voiceStarting = false);
    }
  }

  Future<void> stopHoldToTalk() async {
    if (_voiceStarting) ++_voiceGeneration;
    try {
      await _activeStt?.stop();
    } catch (_) {}
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
          unawaited(stopHoldToTalk()
              .then((_) => _speech.toggle(i, msgs[i]['text'] ?? '')));
        }
      },
      onQuickEntry: onQuick,
      onTipMore: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => Scaffold(
                appBar: AppBar(title: const Text('当地天气与穿衣提醒')),
                body: const WeatherCard(),
              ))),
      textScale: 1.0,
      onSend: send,
      onVoiceStart: () => startHoldToTalk(),
      onVoiceEnd: stopHoldToTalk,
      voiceActive: listening || _voiceStarting,
      voiceHint: _voiceHint,
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
      header: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF345C87),
                    backgroundColor: const Color(0xFFEDF4FB)),
                icon: const Icon(Icons.history),
                label: const Text('查看历史聊天记录'),
                onPressed: () async {
                  await _historyReady;
                  await _saveHistory();
                  if (!mounted || _historyKey == null) return;
                  Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) =>
                          ChatHistoryPage(accountKey: _historyKey!)));
                },
              )),
        ),
      ]),
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
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.whileInUse ||
          perm == LocationPermission.always) {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.low,
          timeLimit: const Duration(seconds: 8),
        );
        final d = await ApiService.weatherRemind(
            lat: pos.latitude, lon: pos.longitude);
        if (_unconfigured(d)) return null;
        return _Weather(data: d, fromGps: true);
      }
    } catch (_) {}
    return null;
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
        if (w == null)
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Text('请允许定位并开启手机定位服务，以查看当地天气和穿衣提醒。',
                style: TextStyle(fontSize: 20)),
          );
        final d = w.data;
        return Card(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: ListTile(
            leading:
                const Icon(Icons.cloud, size: 36, color: AppColors.primary),
            title: Text('${d['city'] ?? ''} ${d['text'] ?? ''}',
                style: AppText.body),
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
  static List<Map<String, String>> current = [];
  static List<AfuMessage> get items {
    final out = <AfuMessage>[];
    for (final m in current) {
      if (m['role'] == 'thinking') continue;
      out.add(AfuMessage(text: m['text'] ?? '', isMe: m['role'] == 'me'));
    }
    return out;
  }
}
