import 'package:flutter/material.dart';
import '../../services/api.dart';
import '../../theme.dart';
import '../login_page.dart';

/// Day5：我的页 — v2.0 绑定列表对方昵称字段为 other_nickname
class MeTab extends StatefulWidget {
  final String role;
  const MeTab({super.key, required this.role});
  @override
  State<MeTab> createState() => _MeTabState();
}

class _MeTabState extends State<MeTab> {
  List binds = [];
  String inviteCode = '';
  String inviteMsg = '';
  @override
  void initState() { super.initState(); load(); }

  Future<void> genInvite() async {
    try {
      inviteCode = await ApiService.createInvite();
      inviteMsg = '';
    } catch (e) {
      inviteMsg = ApiService.friendly(e);
    }
    if (mounted) setState(() {});
  }
  Future<void> load() async {
    try { binds = await ApiService.bindList(); } catch (_) { binds = []; }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: load,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Text(widget.role == 'family' ? '家属 · 我的' : '我的', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('已绑定亲人（双方互见昵称）：', style: TextStyle(fontSize: 20)),
        const SizedBox(height: 8),
        if (widget.role == 'elder') ...[
          ElevatedButton.icon(onPressed: genInvite, icon: const Icon(Icons.qr_code), label: const Text('生成邀请码')),
          if (inviteCode.isNotEmpty)
            Card(
              child: ListTile(
                leading: const Icon(Icons.key, size: 36),
                title: SelectableText(inviteCode, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
                subtitle: const Text('30分钟内有效，把这串码告诉家人', style: TextStyle(fontSize: 18)),
              ),
            ),
          if (inviteMsg.isNotEmpty) Text(inviteMsg, style: const TextStyle(fontSize: 18, color: AppColors.danger)),
          const SizedBox(height: 8),
        ],
        if (binds.isEmpty) const Card(child: ListTile(title: Text('暂无绑定', style: TextStyle(fontSize: 20)))),
        ...binds.map((b) {          final m = b is Map ? Map<String, dynamic>.from(b as Map) : <String, dynamic>{};
          final name = (m['other_nickname'] ?? m['nickname'] ?? '对方').toString();
          final status = (m['status'] ?? '').toString();
          final code = (m['invite_code'] ?? '').toString();
          return Card(child: ListTile(leading: const Icon(Icons.person, size: 36), title: Text(name, style: const TextStyle(fontSize: 22)), subtitle: Text('$status 邀请码$code', style: const TextStyle(fontSize: 18))));
        }),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: () async {
            await ApiService.clearAuth();
            if (context.mounted) {
              Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const LoginPage()), (r) => false);
            }
          },
          child: const Text('退出登录'),
        ),
      ]),
    );
  }
}
