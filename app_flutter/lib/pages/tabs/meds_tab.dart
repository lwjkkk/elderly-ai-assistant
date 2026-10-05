import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/api.dart';
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

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    setState(() { loading = true; err = ''; });
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
    try {
      await ApiService.checkin(medId, slot);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('打卡成功')));
      }
      refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('打卡失败：${ApiService.friendly(e)}')));
      }
    }
  }

  Future<void> _openManual() async {
    await _medFormDialog();
  }

  /// 拍照录入：唤起相机拍照，识别后回填药名/剂量/频次，
  /// 开始用药日期与提醒用药时间点仍由用户手动填写。
  Future<void> _pickPhoto() async {
    try {
      final f = await ImagePicker()
          .pickImage(source: ImageSource.camera, maxWidth: 1600);
      if (f == null) return;
      final bytes = await f.readAsBytes();
      final r = await ApiService.queryDrugByImage(bytes.toList());
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
        final dm = RegExp(r'\d+\.?\d*\s*(mg|g|ml|片|粒|颗|袋|支)')
            .firstMatch(ocr);
        if (dm != null) dose = dm.group(0) ?? '';
        final fm = RegExp(r'(每日\d*次|每天\d*次|一日\d*次|一天\d*次|每\d+小时一次)')
            .firstMatch(ocr);
        if (fm != null) freq = fm.group(0) ?? '';
      }
      if (!mounted) return;
      await _medFormDialog(
          presetName: name,
          presetDose: dose,
          presetFreq: freq,
          autoNote: '已自动识别填充，可手动修改');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('识别失败：${ApiService.friendly(e)}')));
      }
    }
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
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
        ),
        child: Text(text,
            style: const TextStyle(
                fontSize: 20, fontWeight: FontWeight.w700)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return Center(child: CircularProgressIndicator(color: const Color(0xFF345C87)));
    final cards = <Widget>[];
    for (final m in items) {
      final map = m is Map ? Map<String, dynamic>.from(m as Map) : <String, dynamic>{};
      final medId = (map['medication_id'] ?? map['id'] ?? 0) as num? ?? 0;
      final name = (map['name'] ?? '药品').toString();
      final dosage = (map['dosage'] ?? '').toString();
      final slots = (map['slots'] is List) ? List.from(map['slots']) : [];
      for (final s in slots) {
        final sm = s is Map ? Map<String, dynamic>.from(s as Map) : <String, dynamic>{};
        final slot = (sm['slot'] ?? '').toString();
        final status = (sm['status'] ?? 'pending').toString();
        final done = status == 'taken';
        cards.add(Card(
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
                    onPressed: done ? null : () => doCheckin(medId.toInt(), slot),
                    child: Text(done ? '已打卡' : '打卡', style: const TextStyle(fontSize: 20)),
                  ),
          ),
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
            const Text('今日用药', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Color(0xFF212936))),
          ]),
          if (!widget.readOnly) ...[
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: _topBtn('手动录入', _openManual)),
              const SizedBox(width: 12),
              Expanded(child: _topBtn('拍照录入', _pickPhoto)),
            ]),
            const SizedBox(height: 16),
          ],
          if (err.isNotEmpty) AppErrorCard(message: err, onRetry: refresh),
          if (cards.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
              child: Column(children: [
                // 空状态：胶囊图形在标题左侧、对勾图形在标题右侧，不再交叉
                Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 92,
                        height: 72,
                        child:
                            CustomPaint(painter: _CapsulePainter()),
                      ),
                      const SizedBox(width: 20),
                      const Flexible(
                        child: Text('今天还没有用药安排',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF212936))),
                      ),
                      const SizedBox(width: 20),
                      SizedBox(
                        width: 60,
                        height: 60,
                        child: CustomPaint(painter: _CheckPainter()),
                      ),
                    ]),
                const SizedBox(height: 16),
                const Text('点击右上角把每天要吃的药记录下来',
                    style: TextStyle(
                        fontSize: 20,
                        color: Color(0xFF6B7280),
                        height: 1.6),
                    textAlign: TextAlign.center),
                const Text('养成记录习惯，帮助您按时用药',
                    style: TextStyle(
                        fontSize: 20,
                        color: Color(0xFF6B7280),
                        height: 1.6),
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
    canvas.drawLine(
        Offset(s.width * 0.50, s.height * 0.22),
        Offset(s.width * 0.50, s.height * 0.78),
        stroke);
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
            child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('·  ',
                      style: TextStyle(
                          fontSize: 18,
                          color: Color(0xFF2F6FD6),
                          height: 1.5)),
                  Expanded(
                    child: Text(tip,
                        style: const TextStyle(
                            fontSize: 18,
                            color: Color(0xFF212936),
                            height: 1.5)),
                  ),
                ]),
          ),
      ]),
    );
  }
}
