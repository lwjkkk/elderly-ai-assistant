import 'package:flutter/material.dart';
import '../services/api.dart';

/// 绑定页：老人生成邀请码 / 家属输入邀请码绑定，GET /api/bind/list 展示
class BindPage extends StatefulWidget {
  final String role;
  final Future<void> Function()? onLogout;
  const BindPage({super.key, this.role = 'elder', this.onLogout});
  @override
  State<BindPage> createState() => _BindPageState();
}

class _BindPageState extends State<BindPage> {
  final codeCtrl = TextEditingController();
  String inviteCode = '';
  String msg = '';
  List binds = [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      binds = await ApiService.bindList();
    } catch (e) {
      msg = '查询绑定列表失败（A 后端 Day1 未完成时正常）: $e';
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('绑定管理', style: TextStyle(fontSize: 26))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ElevatedButton(
            onPressed: () async {
              try {
                inviteCode = await ApiService.createInvite();
                setState(() => msg = '邀请码已生成，告诉家人：$inviteCode');
              } catch (e) {
                setState(() => msg = '生成失败：$e');
              }
            },
            child: const Text('生成邀请码（老人点我）'),
          ),
          if (inviteCode.isNotEmpty)
            SelectableText('邀请码：$inviteCode', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          const Text('输入邀请码绑定（家属填）：', style: TextStyle(fontSize: 20)),
          TextField(controller: codeCtrl, style: const TextStyle(fontSize: 24), decoration: const InputDecoration(border: OutlineInputBorder(), hintText: '6位邀请码')),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () async {
              try {
                await ApiService.acceptInvite(codeCtrl.text.trim());
                setState(() => msg = '绑定成功');
                _refresh();
              } catch (e) {
                setState(() => msg = '绑定失败：$e');
              }
            },
            child: const Text('确认绑定'),
          ),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: _refresh, child: const Text('刷新绑定列表')),
          ...binds.map((b) => Card(child: ListTile(title: Text(b.toString(), style: const TextStyle(fontSize: 20))))),
          const SizedBox(height: 12),
          Text(msg, style: const TextStyle(fontSize: 20)),
        ]),
      ),
    );
  }
}
