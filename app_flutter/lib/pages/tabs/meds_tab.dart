import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/api.dart';
import '../../services/medication_time.dart';
import '../../afu/delete_confirm.dart';
import 'med_form.dart';
import '../../theme.dart';

/// Day2：今日清单(GET /api/meds/today → slots) + 打卡 + 录药
/// v2.0：status 枚举 pending/taken/missed；录药必填 name/dosage/frequency/times
class MedsTab extends StatefulWidget {
  final bool readOnly;
  final bool mine;
  const MedsTab({super.key, this.readOnly = false, this.mine = false});
  @override
  State<MedsTab> createState() => _MedsTabState();
}

class _MedsTabState extends State<MedsTab> {
  List items = [];
  bool loading = true;
  String err = '';
  Timer? _clock;
  final Set<String> _checking = {};
  bool _recognizingPhoto = false;
  String _loadedDate = medicationNow().toIso8601String().split('T').first;

  @override
  void initState() {
    super.initState();
    refresh();
    _clock = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted) return;
      final date = medicationNow().toIso8601String().split('T').first;
      if (_loadedDate != date) {
        _loadedDate = date;
        unawaited(refresh());
      } else {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  Future<void> refresh() async {
    setState(() {
      loading = true;
      err = '';
    });
    try {
      items = await ApiService.medsToday(mine: widget.mine);
    } catch (e) {
      err = ApiService.friendly(e);
    }
    if (mounted) setState(() => loading = false);
  }

  Color statusColor(String s) {
    if (s == 'taken') return const Color(0xFF345C87);
    if (s == 'missed') return Colors.red;
    return Colors.orange;
  }

  String statusText(String s) {
    if (s == 'taken') return '已服';
    if (s == 'missed') return '漏服';
    return '待服';
  }

  Future<void> doCheckin(int medId, String slot) async {
    final key = '$medId-$slot';
    if (!medicationSlotDue(slot) || _checking.contains(key)) return;
    setState(() => _checking.add(key));
    try {
      await ApiService.checkin(medId, slot);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('打卡成功')));
      }
      refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('打卡失败：${ApiService.friendly(e)}')));
      }
    } finally {
      if (mounted) setState(() => _checking.remove(key));
    }
  }

  Future<void> _deleteMed(int id, String name) async {
    if (!await showDeleteConfirm(context, '“$name”')) return;
    try {
      await ApiService.deleteMed(id);
      await refresh();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('删除失败：${ApiService.friendly(e)}')));
    }
  }

  Future<void> _openManual() async {
    await _medFormDialog();
  }

  /// 拍照录入：先让用户选择相机或相册，识别后回填药名/剂量/频次。
  /// 开始用药日期与提醒用药时间点仍由用户手动填写。
  Future<void> _pickPhoto() async {
    if (_recognizingPhoto) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD5DCE5),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 14),
              const Text('选择录入方式',
                  style: TextStyle(
                      color: Color(0xFF212936),
                      fontSize: 20,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined,
                    color: Color(0xFF345C87), size: 28),
                title: const Text('直接拍照', style: TextStyle(fontSize: 18)),
                onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined,
                    color: Color(0xFF345C87), size: 28),
                title: const Text('从相册选择', style: TextStyle(fontSize: 18)),
                onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
    if (source == null || !mounted) return;

    try {
      final f = await ImagePicker().pickImage(
          source: source, maxWidth: 1600, imageQuality: 88);
      if (f == null) return;
      setState(() => _recognizingPhoto = true);
      _showRecognizingMessage();
      final bytes = await f.readAsBytes();
      final r =
          await ApiService.queryDrugByImage(bytes.toList(), mine: widget.mine);
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      final ocr = (r['ocr_text'] ?? '').toString();
      var name = '';
      var dose = '';
      var freq = '';
      if (ocr.trim().isNotEmpty) {
        final lines = [
          for (final l in ocr.split('\n'))
            if (l.trim().isNotEmpty) l.trim(),
        ];
        if (lines.isNotEmpty) name = lines.first;
        final dm = RegExp(r'\d+\.?\d*\s*(mg|g|ml|片|粒|颗|袋|支)').firstMatch(ocr);
        if (dm != null) dose = dm.group(0) ?? '';
        final fm =
            RegExp(r'(每日\d*次|每天\d*次|一日\d*次|一天\d*次|每\d+小时一次)').firstMatch(ocr);
        if (fm != null) freq = fm.group(0) ?? '';
      }
      if (!mounted) return;
      final recognized = ocr.trim().isNotEmpty;
      if (!recognized) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('图片已处理，但没有识别到药品信息，请手动填写')));
      }
      await _medFormDialog(
          presetName: name,
          presetDose: dose,
          presetFreq: freq,
          autoNote: recognized ? '已自动识别填充，可手动修改' : '请核对药品包装并手动填写');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('识别失败：${ApiService.friendly(e)}')));
      }
    } finally {
      if (mounted) setState(() => _recognizingPhoto = false);
    }
  }

  void _showRecognizingMessage() {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      duration: Duration(minutes: 10),
      content: Row(children: [
        SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: Colors.white)),
        SizedBox(width: 12),
        Expanded(child: Text('正在识别药品，请稍候…')),
      ]),
    ));
  }

  /// 录入药品弹窗：浅灰白底、超大圆角、整体下移留白。
  /// 字段自上而下：药名 / 剂量 / 频次 / 开始用药日期 / 提醒用药时间点。
  Future<void> _medFormDialog(
      {String? presetName,
      String? presetDose,
      String? presetFreq,
      String? autoNote}) async {
    final data = await showMedFormDialog(context,
        presetName: presetName,
        presetDose: presetDose,
        presetFreq: presetFreq,
        autoNote: autoNote);
    if (data == null) return;
    try {
      await ApiService.addMed(
        name: data['name'] as String,
        dosage: data['dosage'] as String,
        frequency: data['frequency'] as String,
        times: List<String>.from(data['times'] as List),
        startDate: data['startDate'] as String?,
      );
      refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('保存失败：${ApiService.friendly(e)}')));
      }
    }
  }

  Widget _topBtn(String text, VoidCallback onTap) {
    return SizedBox(
      height: 56,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF345C87),
          foregroundColor: Colors.white,
          elevation: 2,
          shadowColor: const Color(0xFF345C87).withOpacity(0.25),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        child: Text(text,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading)
      return Center(
          child: CircularProgressIndicator(color: const Color(0xFF345C87)));
    final cards = <Widget>[];
    for (final m in items) {
      final map =
          m is Map ? Map<String, dynamic>.from(m as Map) : <String, dynamic>{};
      final medId = (map['medication_id'] ?? map['id'] ?? 0) as num? ?? 0;
      final name = (map['name'] ?? '药品').toString();
      final dosage = (map['dosage'] ?? '').toString();
      final slots = (map['slots'] is List) ? List.from(map['slots']) : [];
      for (final s in slots) {
        final sm = s is Map
            ? Map<String, dynamic>.from(s as Map)
            : <String, dynamic>{};
        final slot = (sm['slot'] ?? '').toString();
        final status = (sm['status'] ?? 'pending').toString();
        final done = status == 'taken';
        final due = medicationSlotDue(slot);
        final checking = _checking.contains('${medId.toInt()}-$slot');
        cards.add(GestureDetector(
          behavior: HitTestBehavior.opaque,
          onLongPress:
              widget.readOnly ? null : () => _deleteMed(medId.toInt(), name),
          child: Card(
              child: ListTile(
            title: Text(name, style: const TextStyle(fontSize: 22)),
            subtitle: Text('$slot吃$dosage',
                style: TextStyle(fontSize: 18, color: Color(0xFF212936))),
            trailing: widget.readOnly
                ? null
                : ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF345C87),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: done || !due || checking
                        ? null
                        : () => doCheckin(medId.toInt(), slot),
                    child: Text(
                        done
                            ? '已打卡'
                            : checking
                                ? '提交中'
                                : due
                                    ? '打卡'
                                    : '时间未到',
                        style: const TextStyle(fontSize: 20)),
                  ),
          )),
        ));
      }
    }
    return RefreshIndicator(
      color: const Color(0xFF345C87),
      onRefresh: refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(children: [
            const Text('今日用药',
                style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF212936))),
          ]),
          if (!widget.readOnly) ...[
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: _topBtn('手动录入', _openManual)),
              const SizedBox(width: 12),
              Expanded(
                  child: _topBtn(
                      _recognizingPhoto ? '正在识别…' : '拍照录入', _pickPhoto)),
            ]),
            const SizedBox(height: 16),
          ],
          if (err.isNotEmpty) AppErrorCard(message: err, onRetry: refresh),
          if (cards.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
              child: Column(children: [
                const Text('今天还没有用药安排',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF212936))),
                const SizedBox(height: 10),
                Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 72,
                        height: 60,
                        child: CustomPaint(painter: _CapsulePainter()),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 52,
                        height: 52,
                        child: CustomPaint(painter: _CheckPainter()),
                      ),
                    ]),
                const SizedBox(height: 10),
                const Text('点击右上角\n把每天要吃的药记录下来',
                    style: TextStyle(
                        fontSize: 20, color: Color(0xFF6B7280), height: 1.6),
                    textAlign: TextAlign.center),
              ]),
            ),
          if (cards.isEmpty) const _MedScienceCard(),
          // 科普卡与底部 Tab 栏间距：列表 padding 16 + 此处 8 = 24
          if (cards.isEmpty) const SizedBox(height: 8),
          ...cards,
        ],
      ),
    );
  }
}

/// 用药空状态插画（一）：胶囊药丸，低饱和健康蓝绿色。
class _CapsulePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final stroke = Paint()
      ..color = const Color(0xFF5FA9A6)
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final fill = Paint()
      ..color = const Color(0xFFE2F2F0)
      ..style = PaintingStyle.fill;
    final body = RRect.fromRectAndRadius(
        Rect.fromLTWH(
            s.width * 0.06, s.height * 0.22, s.width * 0.88, s.height * 0.56),
        const Radius.circular(22));
    canvas.drawRRect(body, fill);
    canvas.drawRRect(body, stroke);
    canvas.drawLine(Offset(s.width * 0.50, s.height * 0.22),
        Offset(s.width * 0.50, s.height * 0.78), stroke);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// 用药空状态插画（二）：对勾圆环，低饱和健康蓝绿色。
class _CheckPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final stroke = Paint()
      ..color = const Color(0xFF5FA9A6)
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final cc = Offset(s.width * 0.5, s.height * 0.5);
    canvas.drawCircle(cc, s.width * 0.42, stroke);
    final tick = Path()
      ..moveTo(cc.dx - s.width * 0.22, cc.dy)
      ..lineTo(cc.dx - s.width * 0.04, cc.dy + s.width * 0.16)
      ..lineTo(cc.dx + s.width * 0.24, cc.dy - s.width * 0.18);
    canvas.drawPath(tick, stroke);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// 无用药安排时的浅色科普卡：浅蓝白底，圆角与普通卡片统一。
class _MedScienceCard extends StatelessWidget {
  const _MedScienceCard();
  @override
  Widget build(BuildContext context) {
    const tips = [
      '用药前请确认药名、剂量和服用时间',
      '降压药、降糖药请按医嘱规律服用',
      '如有不适，请及时联系家属或就医',
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5FB),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE3EAF5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('常见药科普',
            style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w700,
                color: Color(0xFF212936))),
        const SizedBox(height: 10),
        for (final tip in tips)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('·  ',
                  style: TextStyle(
                      fontSize: 18, color: Color(0xFF2F6FD6), height: 1.5)),
              Expanded(
                child: Text(tip,
                    style: const TextStyle(
                        fontSize: 18, color: Color(0xFF212936), height: 1.5)),
              ),
            ]),
          ),
      ]),
    );
  }
}
