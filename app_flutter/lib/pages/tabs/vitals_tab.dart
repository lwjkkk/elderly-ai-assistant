import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/api.dart';
import '../../services/file_download.dart';
import '../../afu/delete_confirm.dart';
import 'health_record_style.dart';

class VitalsTab extends StatefulWidget {
  final bool readOnly;
  final bool mine;
  const VitalsTab({super.key, this.readOnly = false, this.mine = false});
  @override
  State<VitalsTab> createState() => _VitalsTabState();
}

class _VitalsTabState extends State<VitalsTab> {
  static const types = {'bp': '血压', 'bs': '血糖', 'hr': '心率', 'weight': '体重'};
  List items = [];
  bool loading = true;
  bool busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (!mounted) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await ApiService.vitalsList(days: 90, mine: widget.mine);
      if (mounted) setState(() => items = result);
    } catch (e) {
      if (mounted) setState(() => error = ApiService.friendly(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void message(String text) {
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _deleteVital(Map<String, dynamic> item) async {
    final id = (item['id'] as num?)?.toInt();
    if (id == null || !await showDeleteConfirm(context, '这条体征记录')) return;
    try {
      await ApiService.deleteVital(id);
      await load();
    } catch (e) {
      message('删除失败：${ApiService.friendly(e)}');
    }
  }

  Future<void> showAddDialog({Map<String, dynamic>? preset}) async {
    var type =
        types.containsKey(preset?['type']) ? preset!['type'] as String : 'bp';
    final first = TextEditingController(
        text: '${preset?[type == 'bp' ? 'systolic' : 'value'] ?? ''}');
    final second = TextEditingController(text: '${preset?['diastolic'] ?? ''}');
    final form = GlobalKey<FormState>();
    bool saving = false;
    String? saveError;
    await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
              builder: (context, update) => AlertDialog(
                backgroundColor: Colors.white,
                title: const Text('录入体征',
                    style: TextStyle(color: HealthRecordStyle.ink)),
                content: SingleChildScrollView(
                    child: Form(
                        key: form,
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          DropdownButtonFormField<String>(
                            initialValue: type,
                            decoration:
                                const InputDecoration(labelText: '体征类型'),
                            items: types.entries
                                .map((e) => DropdownMenuItem(
                                    value: e.key, child: Text(e.value)))
                                .toList(),
                            onChanged: saving
                                ? null
                                : (value) => update(() {
                                      type = value!;
                                      first.clear();
                                      second.clear();
                                    }),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                              controller: first,
                              enabled: !saving,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              decoration: InputDecoration(
                                  labelText: type == 'bp'
                                      ? '高压（mmHg）'
                                      : type == 'bs'
                                          ? '血糖（mmol/L）'
                                          : type == 'hr'
                                              ? '心率（次/分）'
                                              : '体重（kg）'),
                              validator: (s) =>
                                  _validate(s, integer: type == 'bp')),
                          if (type == 'bp') ...[
                            const SizedBox(height: 12),
                            TextFormField(
                                controller: second,
                                enabled: !saving,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                    labelText: '低压（mmHg）'),
                                validator: (s) => _validate(s, integer: true)),
                          ],
                          if (preset != null)
                            const Padding(
                                padding: EdgeInsets.only(top: 12),
                                child: Text('请核对识别结果后保存',
                                    style: TextStyle(
                                        color: HealthRecordStyle.secondary))),
                          if (saveError != null)
                            Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Text(saveError!,
                                    style: const TextStyle(
                                        color: Color(0xFFB3261E)))),
                        ]))),
                actions: [
                  TextButton(
                      onPressed:
                          saving ? null : () => Navigator.pop(dialogContext),
                      child: const Text('取消')),
                  HealthRecordStyle.button(
                      saving ? '保存中…' : '保存',
                      Icons.check,
                      saving
                          ? null
                          : () async {
                              if (!form.currentState!.validate()) return;
                              update(() {
                                saving = true;
                                saveError = null;
                              });
                              try {
                                await ApiService.addVital(
                                    type: type,
                                    mine: widget.mine,
                                    systolic: type == 'bp'
                                        ? int.parse(first.text.trim())
                                        : null,
                                    diastolic: type == 'bp'
                                        ? int.parse(second.text.trim())
                                        : null,
                                    value: type != 'bp'
                                        ? double.parse(first.text.trim())
                                        : null);
                                if (!dialogContext.mounted) return;
                                Navigator.pop(dialogContext);
                                message('体征已保存');
                                await load();
                              } catch (e) {
                                if (dialogContext.mounted)
                                  update(() {
                                    saving = false;
                                    saveError = ApiService.friendly(e);
                                  });
                              }
                            }),
                ],
              ),
            ));
    first.dispose();
    second.dispose();
  }

  String? _validate(String? text, {bool integer = false}) {
    final value = double.tryParse(text?.trim() ?? '');
    if (value == null || !value.isFinite || value <= 0) return '请输入有效的正数';
    if (integer && int.tryParse(text!.trim()) == null) return '请输入整数';
    return null;
  }

  Future<void> photo() async {
    final source = await showModalBottomSheet<ImageSource>(
        context: context,
        backgroundColor: Colors.white,
        builder: (c) => SafeArea(
            child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('选择上传方式',
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: HealthRecordStyle.ink)),
                  const SizedBox(height: 16),
                  SizedBox(
                      width: double.infinity,
                      child: HealthRecordStyle.button(
                          '拍照',
                          Icons.camera_alt_outlined,
                          () => Navigator.pop(c, ImageSource.camera))),
                  const SizedBox(height: 12),
                  SizedBox(
                      width: double.infinity,
                      child: HealthRecordStyle.button(
                          '从相册选择',
                          Icons.photo_library_outlined,
                          () => Navigator.pop(c, ImageSource.gallery))),
                ]))));
    if (source == null || !mounted) return;
    setState(() => busy = true);
    Map<String, dynamic>? result;
    try {
      final file =
          await ImagePicker().pickImage(source: source, maxWidth: 1600);
      if (file != null)
        result = await ApiService.recognizeVital(await file.readAsBytes(),
            mine: widget.mine);
    } catch (e) {
      message('识别失败：${ApiService.friendly(e)}');
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (result != null && mounted) await showAddDialog(preset: result);
  }

  Future<void> export() async {
    setState(() => busy = true);
    try {
      final bytes =
          await ApiService.vitalsExportPdf(days: 90, mine: widget.mine);
      if (bytes.isEmpty) throw Exception('PDF 文件为空');
      final warning = await saveAndOpenPdf(
          bytes, '体征记录_${DateTime.now().millisecondsSinceEpoch}.pdf');
      message(warning ?? 'PDF 已导出');
    } catch (e) {
      message('导出失败：${ApiService.friendly(e)}');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        color: HealthRecordStyle.primary,
        onRefresh: load,
        child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              if (!widget.readOnly)
                Row(children: [
                  Expanded(
                      child: HealthRecordStyle.button(
                          '手动录入',
                          Icons.edit_outlined,
                          busy ? null : () => showAddDialog())),
                  const SizedBox(width: 12),
                  Expanded(
                      child: HealthRecordStyle.button(busy ? '处理中…' : '拍照上传',
                          Icons.camera_alt_outlined, busy ? null : photo)),
                ]),
              const SizedBox(height: 16),
              HealthRecordStyle.panel(loading
                  ? const SizedBox(
                      height: 190,
                      child: Center(
                          child: CircularProgressIndicator(
                              color: HealthRecordStyle.primary)))
                  : error != null
                      ? Column(children: [
                          Text('加载失败：$error'),
                          HealthRecordStyle.button('重试', Icons.refresh, load)
                        ])
                      : items.isEmpty
                          ? HealthRecordStyle.empty(
                              Icons.show_chart, '暂无体征数据，今天记录一条吧')
                          : Column(
                              children: items.map((item) {
                              final m = Map<String, dynamic>.from(item as Map);
                              final type = m['type'];
                              final value = type == 'bp'
                                  ? '${m['systolic']}/${m['diastolic']} mmHg'
                                  : '${m['value']} ${type == 'bs' ? 'mmol/L' : type == 'hr' ? '次/分' : 'kg'}';
                              return ListTile(
                                  onLongPress: widget.readOnly
                                      ? null
                                      : () => _deleteVital(m),
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(Icons.show_chart,
                                      color: HealthRecordStyle.primary),
                                  title: Text('${types[type] ?? type}  $value',
                                      style: const TextStyle(
                                          fontSize: 20,
                                          color: HealthRecordStyle.ink)),
                                  subtitle: Text(
                                      '${m['measured_at'] ?? ''}'
                                          .replaceAll('T', ' '),
                                      style: const TextStyle(
                                          color: HealthRecordStyle.secondary)));
                            }).toList())),
              const SizedBox(height: 16),
              HealthRecordStyle.button(
                  '导出 PDF',
                  Icons.picture_as_pdf_outlined,
                  busy || loading || error != null || items.isEmpty
                      ? null
                      : export),
            ]),
      );
}
