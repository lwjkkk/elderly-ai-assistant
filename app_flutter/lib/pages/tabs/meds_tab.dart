import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../../services/api.dart';
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
    if (s == 'taken') return Colors.green;
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

  Future<void> showAddDialog() async {
    final nameC = TextEditingController();
    final doseC = TextEditingController(text: '20mg');
    final freqC = TextEditingController(text: '每日2次');
    final timeC = TextEditingController(text: '08:00,20:00');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('录入药品', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Color(0xFF222222))),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: nameC,
              style: const TextStyle(fontSize: 20, color: Color(0xFF222222)),
              decoration: InputDecoration(
                labelText: '药名*',
                labelStyle: const TextStyle(fontSize: 18),
                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: doseC,
              style: const TextStyle(fontSize: 20, color: Color(0xFF222222)),
              decoration: InputDecoration(
                labelText: '剂量* 如20mg',
                labelStyle: const TextStyle(fontSize: 18),
                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: freqC,
              style: const TextStyle(fontSize: 20, color: Color(0xFF222222)),
              decoration: InputDecoration(
                labelText: '频次* 如每日2次',
                labelStyle: const TextStyle(fontSize: 18),
                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: timeC,
              style: const TextStyle(fontSize: 20, color: Color(0xFF222222)),
              decoration: InputDecoration(
                labelText: '时间点* HH:MM逗号分隔',
                labelStyle: const TextStyle(fontSize: 18),
                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14)),
            child: const Text('取消', style: TextStyle(fontSize: 19)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14)),
            child: const Text('保存', style: TextStyle(fontSize: 19)),
          ),
        ],
      ),
    );
    if (ok == true && nameC.text.trim().isNotEmpty) {
      try {
        await ApiService.addMed(
          name: nameC.text.trim(),
          dosage: doseC.text.trim(),
          frequency: freqC.text.trim(),
          times: timeC.text.trim().split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
        );
        refresh();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('保存失败：${ApiService.friendly(e)}')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
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
            title: Text('$name $dosage  $slot', style: const TextStyle(fontSize: 22)),
            subtitle: Text(statusText(status),
                style: TextStyle(fontSize: 18, color: statusColor(status))),
            trailing: widget.readOnly
                ? null
                : ElevatedButton(
                    onPressed: done ? null : () => doCheckin(medId.toInt(), slot),
                    child: Text(done ? '已打卡' : '打卡', style: const TextStyle(fontSize: 20)),
                  ),
          ),
        ));
      }
    }
    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 今日小贴士：优先展示用药提醒与时间，无提醒则展示当日温度与穿衣建议
          const _MedsTipCard(),
          const SizedBox(height: 12),
          Row(children: [
            const Text('今日用药', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Color(0xFF222222))),
            const Spacer(),
            if (!widget.readOnly)
              ElevatedButton.icon(
                  onPressed: showAddDialog,
                  icon: const Icon(Icons.add),
                  label: const Text('录药')),
          ]),
          if (err.isNotEmpty) AppErrorCard(message: err, onRetry: refresh),
          if (cards.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
              child: Column(children: [
                // 简易插画：药丸 + 对勾
                SizedBox(
                  width: 120,
                  height: 96,
                  child: CustomPaint(painter: _MedsEmptyPainter()),
                ),
                const SizedBox(height: 16),
                const Text('今天还没有用药安排',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Color(0xFF222222))),
                const SizedBox(height: 8),
                const Text('点右上角录药，把每天要吃的药记下来吧',
                    style: TextStyle(fontSize: 18, color: Color(0xFF6B7686), height: 1.5),
                    textAlign: TextAlign.center),
              ]),
            ),
          ...cards,
        ],
      ),
    );
  }
}

/// 用药页今日小贴士：优先查当前用户用药提醒并展示对应时间；
/// 无用药提醒时调用天气，展示当日温度与穿衣建议。
class _MedsTipCard extends StatefulWidget {
  const _MedsTipCard();
  @override
  State<_MedsTipCard> createState() => _MedsTipCardState();
}

class _MedsTipCardState extends State<_MedsTipCard> {
  late final Future<String?> _future = _load();

  static Future<String?> _load() async {
    try {
      final meds = await ApiService.medsToday();
      for (final m in meds) {
        final map = m is Map ? Map<String, dynamic>.from(m as Map) : <String, dynamic>{};
        final name = (map['name'] ?? '').toString();
        final slots = map['slots'] is List ? List.from(map['slots']) : [];
        for (final s in slots) {
          final sm = s is Map ? Map<String, dynamic>.from(s as Map) : <String, dynamic>{};
          if ((sm['status'] ?? 'pending').toString() == 'pending' && name.isNotEmpty) {
            final slot = (sm['slot'] ?? '').toString();
            return '用药提醒：$name ${slot.isEmpty ? '今日' : slot}服用，别忘了按时吃药';
          }
        }
      }
    } catch (_) {}
    try {
      Map<String, dynamic>? d;
      try {
        var perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied) {
          perm = await Geolocator.requestPermission();
        }
        if (perm == LocationPermission.whileInUse || perm == LocationPermission.always) {
          final pos = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.low,
            timeLimit: const Duration(seconds: 8),
          );
          d = await ApiService.weatherRemind(lat: pos.latitude, lon: pos.longitude);
        }
      } catch (_) {}
      d ??= await ApiService.weatherRemind();
      final text = (d['text'] ?? '').toString();
      final tip = (d['tip'] ?? '').toString();
      final body = (text + tip).trim();
      if (body.isNotEmpty) return '今日天气：$body';
    } catch (_) {}
    return '记得按时作息、均衡饮食';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _future,
      builder: (c, s) {
        if (s.connectionState == ConnectionState.waiting) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Text('正在查看提醒…', style: TextStyle(fontSize: 19, color: Color(0xFF222222))),
            ),
          );
        }
        if (s.data == null) return const SizedBox.shrink();
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(children: [
              Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(color: Color(0xFFFFF3E2), shape: BoxShape.circle),
                child: const Icon(Icons.lightbulb_outline, size: 28, color: Color(0xFFB07A2A)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(s.data!,
                    style: const TextStyle(fontSize: 19, color: Color(0xFF222222), height: 1.5)),
              ),
            ]),
          ),
        );
      },
    );
  }
}

/// 用药空状态简易插画：胶囊药丸 + 对勾。
class _MedsEmptyPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final stroke = Paint()
      ..color = const Color(0xFF7AA5F0)
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final fill = Paint()
      ..color = const Color(0xFFE8EFFD)
      ..style = PaintingStyle.fill;
    final body = RRect.fromRectAndRadius(
        Rect.fromLTWH(s.width * 0.12, s.height * 0.22, s.width * 0.60, s.height * 0.44),
        const Radius.circular(20));
    canvas.drawRRect(body, fill);
    canvas.drawRRect(body, stroke);
    canvas.drawLine(
        Offset(s.width * 0.42, s.height * 0.22), Offset(s.width * 0.42, s.height * 0.66), stroke);
    final cc = Offset(s.width * 0.80, s.height * 0.62);
    canvas.drawCircle(cc, s.height * 0.20, stroke);
    final tick = Path()
      ..moveTo(cc.dx - s.height * 0.10, cc.dy)
      ..lineTo(cc.dx - s.height * 0.02, cc.dy + s.height * 0.08)
      ..lineTo(cc.dx + s.height * 0.11, cc.dy - s.height * 0.09);
    canvas.drawPath(tick, stroke);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
