import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';

import '../afu/afu_theme.dart';
import '../afu/afu_widgets.dart';
import '../services/api.dart';
 
import 'tabs/health_overview.dart';
 
 
import 'login_page.dart';
import 'tabs/consult_drug_chat_tab.dart' show ChatTab;
import 'tabs/hub_pages.dart' show FamilyTab;

/// 家属端 4Tab：健康总览 / 体征 / 报告 / 我的（阿福风统一视觉）。
class FamilyHome extends StatefulWidget {
  const FamilyHome({super.key});
  @override
  State<FamilyHome> createState() => _FamilyHomeState();
}

class _FamilyHomeState extends State<FamilyHome> {
  int idx = 0;

    @override
  Widget build(BuildContext context) {
    const titles = ['健康总览', 'AI问事', '家人互动', '个人中心'];
    const pages = [
      HealthOverviewTab(role: 'family'),
      ChatTab(),
      FamilyTab(),
      FamMe(),
    ];
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FD),
      appBar: AppBar(
        title: Text(titles[idx]),
        backgroundColor: const Color(0xFFF7F9FD),
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(key: ValueKey(idx), child: pages[idx]),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: idx,
        type: BottomNavigationBarType.fixed,
        selectedFontSize: 16,
        unselectedFontSize: 16,
        selectedItemColor: AfuColors.primaryDeep,
        unselectedItemColor: const Color(0xFF5A6472),
        onTap: (i) => setState(() => idx = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard_outlined, size: 30), label: '健康总览'),
          BottomNavigationBarItem(icon: Icon(Icons.chat_bubble_outline, size: 30), label: 'AI问事'),
          BottomNavigationBarItem(icon: Icon(Icons.family_restroom_outlined, size: 30), label: '家人互动'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline, size: 30), label: '个人中心'),
        ],
      ),
    );
  }
}


/// 4) Me page: profile + bind management + logout.
class FamMe extends StatefulWidget {
  const FamMe({super.key});
  @override
  State<FamMe> createState() => _FamMeState();
}

class _FamMeState extends State<FamMe> {
  String avatarAsset = kAvatarAssets[0];
  String nickname = '\u5bb6\u5c5e';
  List binds = [];
  final codeC = TextEditingController();
  String msg = '';
  bool binding = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    codeC.dispose();
    super.dispose();
  }

  bool get bound => binds.any((b) {
    final m = b is Map ? Map<String, dynamic>.from(b as Map) : <String, dynamic>{};
    return (m['status'] ?? '').toString() == 'active';
  });

  Future<void> _load() async {
    try {
        nickname = await ApiService.getNickname() ?? '\u5bb6\u5c5e';
      binds = await ApiService.bindList();
      try {
        final prefs = await SharedPreferences.getInstance();
        avatarAsset = prefs.getString('avatar') ?? avatarAsset;
      } catch (_) {}
    } catch (_) {
      binds = [];
    }
    if (mounted) setState(() {});
  }

  Future<void> _doBind() async {
    final c = codeC.text.trim();
    if (c.isEmpty) {
      setState(() => msg = '\u5148\u8f93\u5165\u9080\u8bf7\u7801');
      return;
    }
    setState(() { binding = true; msg = ''; });
    try {
      await ApiService.acceptInvite(c);
      codeC.clear();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('\u7ed1\u5b9a\u6210\u529f')));
      }
    } catch (e) {
      if (mounted) setState(() => msg = ApiService.friendly(e));
    }
    if (mounted) setState(() => binding = false);
  }

  Future<void> _logout() async {
    await ApiService.clearAuth();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginPage()), (r) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      color: AfuColors.primaryDeep,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _profileCard(),
          if (!bound) ...[
            const SizedBox(height: 16),
            _bindCard(),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _logout,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFA8BFE4), width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text('\u9000\u51fa\u767b\u5f55', style: TextStyle(fontSize: 20)),
            ),
          ),
          if (bound) ...[
            const SizedBox(height: 16),
            _bindCard(),
          ],
        ],
      ),
    );
  }

  Widget _profileCard() {
    return AfuCard(
      child: Row(children: [
        Container(
          width: 76,
          height: 76,
          decoration: const BoxDecoration(color: Color(0xFFEBF1FB), shape: BoxShape.circle),
          child: ClipOval(child: Image.asset(avatarAsset, width: 72, height: 72, fit: BoxFit.cover)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(nickname, style: AfuElderText.body.copyWith(fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }

  Widget _bindCard() {
    return AfuCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('\u4eb2\u5c5e\u7ed1\u5b9a\u7ba1\u7406', style: AfuElderText.body.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        const Text('\u8f93\u5165\u9080\u8bf7\u7801\u53ef\u7ed1\u5b9a\u957f\u8f88', style: AfuElderText.secondary),
        const SizedBox(height: 12),
        TextField(
          controller: codeC,
          style: const TextStyle(fontSize: 21, color: Color(0xFF222222)),
          decoration: InputDecoration(
            hintText: '\u8bf7\u8f93\u51656\u4f4d\u9080\u8bf7\u7801',
            hintStyle: const TextStyle(fontSize: 19, color: Color(0xFF6B7686)),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 19),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(22),
              borderSide: const BorderSide(color: Color(0xFFDCE6F7)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(22),
              borderSide: const BorderSide(color: Color(0xFFDCE6F7)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(22),
              borderSide: const BorderSide(color: AfuColors.primary, width: 2),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: binding ? null : _doBind,
            child: Text(binding ? '\u7ed1\u5b9a\u4e2d\u2026' : '\u786e\u8ba4\u7ed1\u5b9a'),
          ),
        ),
        if (msg.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(msg, style: const TextStyle(fontSize: 18, color: Color(0xFFB3261E))),
        ],
        const SizedBox(height: 12),
        if (binds.isEmpty)
          const Text('\u6682\u65e0\u7ed1\u5b9a', style: AfuElderText.secondary)
        else
          for (final b in binds) _bindRow(b),
      ]),
    );
  }

  Widget _bindRow(dynamic b) {
    final m = b is Map ? Map<String, dynamic>.from(b as Map) : <String, dynamic>{};
    final name = (m['other_nickname'] ?? m['nickname'] ?? '对方').toString();
    final status = (m['status'] ?? '').toString();
    final code = (m['invite_code'] ?? '').toString();
    final active = status == 'active';
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FD),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(children: [
        Container(
          width: 52,
          height: 52,
          decoration: const BoxDecoration(color: Color(0xFFEBF1FB), shape: BoxShape.circle),
          child: const Icon(Icons.person, size: 30, color: AfuColors.primaryDeep),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: AfuElderText.body.copyWith(fontWeight: FontWeight.w700)),
            if (code.isNotEmpty)
              Text('\u9080\u8bf7\u7801 ' + code, style: AfuElderText.secondary.copyWith(fontSize: 16)),
          ]),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: active ? const Color(0xFFE6F4EA) : const Color(0xFFF0F1F5),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(active ? '\u5df2\u7ed1\u5b9a' : status,
              style: TextStyle(
                  fontSize: 17,
                  color: active ? const Color(0xFF2E7D4F) : const Color(0xFF5A6472))),
        ),
      ]),
    );
  }
}
