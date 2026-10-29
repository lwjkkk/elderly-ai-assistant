import 'package:flutter/material.dart';
import 'package:elderly_ai_assistant/services/api.dart';
import 'package:elderly_ai_assistant/services/beijing_time.dart';

class VitalAlertsPage extends StatefulWidget {
  final bool mine;
  const VitalAlertsPage({super.key, this.mine = true});
  @override
  State<VitalAlertsPage> createState() => _VitalAlertsPageState();
}

class _VitalAlertsPageState extends State<VitalAlertsPage> {
  List _items = [];
  bool _loading = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await ApiService.vitalAlerts(mine: widget.mine);
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted)
        setState(
            () => _error = ApiService.errorDetail(e) ?? ApiService.friendly(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.mine ? '本人体征异常提醒' : '长辈体征异常提醒')),
        body: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              children: [
                const Text('以下为服务器保存的近90天异常事件。家属可见范围由绑定和共享权限决定；记录存在不代表手机推送已送达。',
                    style: TextStyle(fontSize: 18, height: 1.5)),
                const SizedBox(height: 16),
                if (_loading)
                  const Center(child: CircularProgressIndicator())
                else if (_error != null) ...[
                  Text('提醒读取失败：$_error',
                      style: const TextStyle(fontSize: 18, color: Colors.red)),
                  TextButton(onPressed: _load, child: const Text('重新加载')),
                ] else if (_items.isEmpty)
                  const Text('近90天暂无可见的异常事件', style: TextStyle(fontSize: 20))
                else
                  for (final item in _items.whereType<Map>())
                    Card(
                        child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                '事件 #${item['id']} · ${item['vital_type'] == 'bp' ? '血压' : '血糖'} · ${item['level'] ?? '提醒'}',
                                style: const TextStyle(
                                    fontSize: 21,
                                    color: Color(0xFFB3261E),
                                    fontWeight: FontWeight.bold)),
                            Text(
                                item['vital_type'] == 'bp'
                                    ? '${item['systolic'] ?? '—'}/${item['diastolic'] ?? '—'} mmHg'
                                    : '${item['value'] ?? '—'} mmol/L',
                                style: const TextStyle(fontSize: 22)),
                            if (item['measurement_context'] != null)
                              Text('测量场景：${{
                                    'fasting': '空腹',
                                    'postprandial': '餐后',
                                    'random': '随机'
                                  }[item['measurement_context']] ?? '未注明'}'),
                            Text('${item['message'] ?? '请复查测量结果'}',
                                style:
                                    const TextStyle(fontSize: 19, height: 1.5)),
                            Text(
                                '记录时间：${formatBeijingDateTime(item['created_at'])}'),
                            SelectableText(
                                '阈值依据：${item['source'] ?? '未提供，请核对'}'),
                            const Text('状态：服务端已记录；送达状态未提供'),
                          ]),
                    )),
                const SizedBox(height: 16),
                const Text(ApiService.disclaimer),
              ],
            )),
      );
}
