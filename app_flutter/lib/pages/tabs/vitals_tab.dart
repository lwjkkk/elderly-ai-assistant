import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../services/api.dart';

/// Day3：体征录入 + 7天趋势曲线 + PDF导出入口
/// v2.0：type=bp/bs/hr/weight；trend 返回对象 {bp:[{date,systolic,diastolic,value}]}
class VitalsTab extends StatefulWidget {
  final bool readOnly;
  const VitalsTab({super.key, this.readOnly = false});
  @override
  State<VitalsTab> createState() => _VitalsTabState();
}

class _VitalsTabState extends State<VitalsTab> {
  String type = 'bp';
  List trend = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() => loading = true);
    try {
      trend = await ApiService.vitalsTrend(vitalType: type, days: 7);
    } catch (_) {
      trend = [];
    }
    if (mounted) setState(() => loading = false);
  }

  double _val(dynamic e) {
    final m = Map<String, dynamic>.from(e as Map);
    if (type == 'bp' && m['systolic'] is num) {
      return (m['systolic'] as num).toDouble();
    }
    final v = m['value'];
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }

  Future<void> showAddDialog() async {
    final sysC = TextEditingController();
    final diaC = TextEditingController();
    final valC = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(type == 'bp' ? '记录血压' : '记录数值'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (type == 'bp') ...[
              TextField(controller: sysC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '收缩压*(高压 mmHg)')),
              TextField(controller: diaC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '舒张压*(低压 mmHg)')),
            ] else
              TextField(controller: valC, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: type == 'bs' ? '血糖*(mmol/L)' : type == 'hr' ? '心率*(次/分)' : '体重*(kg)')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          ElevatedButton(onPressed: () => Navigator.pop(c, true), child: const Text('保存')),
        ],
      ),
    );
    if (ok == true) {
      try {
        await ApiService.addVital(
          type: type,
          systolic: type == 'bp' ? int.tryParse(sysC.text) : null,
          diastolic: type == 'bp' ? int.tryParse(diaC.text) : null,
          value: type == 'bp' ? null : double.tryParse(valC.text),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已保存')));
        }
        load();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存失败：$e')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final spots = <FlSpot>[];
    for (var i = 0; i < trend.length; i++) {
      spots.add(FlSpot(i.toDouble(), _val(trend[i])));
    }
    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        const Text('体征趋势', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
        const Spacer(),
        if (!widget.readOnly)
          ElevatedButton.icon(onPressed: showAddDialog, icon: const Icon(Icons.add), label: const Text('记录')),
      ]),
      const SizedBox(height: 12),
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'bp', label: Text('血压')),
          ButtonSegment(value: 'bs', label: Text('血糖')),
          ButtonSegment(value: 'hr', label: Text('心率')),
          ButtonSegment(value: 'weight', label: Text('体重')),
        ],
        selected: {type},
        onSelectionChanged: (s) { type = s.first; load(); },
      ),
      const SizedBox(height: 12),
      SizedBox(
        height: 220,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : spots.isEmpty
                    ? const Center(child: Text('暂无数据，先记录一条'))
                    : LineChart(LineChartData(lineBarsData: [LineChartBarData(spots: spots, isCurved: true, dotData: const FlDotData(show: true))])),
          ),
        ),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('PDF地址：${ApiService.vitalsExportUrl(vitalType: type)}，浏览器打开下载')));
        },
        icon: const Icon(Icons.picture_as_pdf),
        label: const Text('导出PDF（浏览器打开链接下载）'),
      ),
    ]);
  }
}
