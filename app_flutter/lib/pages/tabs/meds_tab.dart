import 'package:flutter/material.dart';
import '../../services/api.dart';
import '../../theme.dart';

/// Day2：今日清单(GET /api/meds/today → slots) + 打卡 + 录药
/// v2.0：status 枚举 pending/taken/missed；录药必填 name/dosage/frequency/times
class MedsTab extends StatefulWidget {
  final bool readOnly;
  const MedsTab({super.key, this.readOnly = false});
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
      items = await ApiService.medsToday();
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
        title: const Text('录入药品'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: nameC, decoration: const InputDecoration(labelText: '药名*')),
            TextField(controller: doseC, decoration: const InputDecoration(labelText: '剂量* 如20mg')),
            TextField(controller: freqC, decoration: const InputDecoration(labelText: '频次* 如每日2次')),
            TextField(controller: timeC, decoration: const InputDecoration(labelText: '时间点* HH:MM逗号分隔')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          ElevatedButton(onPressed: () => Navigator.pop(c, true), child: const Text('保存')),
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
          Row(children: [
            const Text('今日用药', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
            const Spacer(),
            if (!widget.readOnly)
              ElevatedButton.icon(
                  onPressed: showAddDialog,
                  icon: const Icon(Icons.add),
                  label: const Text('录药')),
          ]),
          if (err.isNotEmpty) AppErrorCard(message: err, onRetry: refresh),
          if (cards.isEmpty)
            const Padding(padding: EdgeInsets.all(24), child: Text('今日暂无用药，下拉刷新试试', style: TextStyle(fontSize: 20))),
          ...cards,
        ],
      ),
    );
  }
}
