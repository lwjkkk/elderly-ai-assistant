import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../afu/afu_theme.dart';
import '../../afu/afu_widgets.dart';
import '../../services/api.dart';
import '../login_page.dart';
import 'hub_pages.dart' show chatScale, notifyEnabled;

/// 设置页（长辈端）：个人信息 + 亲人绑定 + 功能选项 + 退出登录。
/// 功能逻辑沿用旧版（邀请码/绑定列表/退出），只重做视觉。
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
  String avatarAsset = kAvatarAssets[0];
String nickname = '长辈';
  bool notifyOn = true;
  double fontScale = 1.0;

  @override
  void initState() {
    super.initState();
    load();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    try {
      nickname = await ApiService.getNickname() ?? '长辈';
      if (nickname.isEmpty) nickname = '长辈';
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      avatarAsset = prefs.getString('avatar') ?? kAvatarAssets[0];
notifyOn = prefs.getBool('notify_on') ?? true;
      fontScale = prefs.getDouble('chat_text_scale') ?? 1.0;
    } catch (_) {}
    if (mounted) setState(() {});
  }

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
    try {
      binds = await ApiService.bindList();
    } catch (_) {
      binds = [];
    }
    if (mounted) setState(() {});
  }

  Future<void> _editName() async {
    final c = TextEditingController(text: nickname);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('修改昵称', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: c,
          style: const TextStyle(fontSize: 20),
          decoration: const InputDecoration(hintText: '输入新昵称'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消', style: TextStyle(fontSize: 19))),
          TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('保存', style: TextStyle(fontSize: 19))),
        ],
      ),
    );
    if (ok == true && c.text.trim().isNotEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('nickname', c.text.trim());
      } catch (_) {}
      if (mounted) setState(() => nickname = c.text.trim());
    }
  }

  String get fontLabel =>
      fontScale >= 1.3 ? '大' : (fontScale > 1.05 ? '中' : '小');

  Future<void> _openFontPage() async {
    await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const _FontPage()));
    try {
      final prefs = await SharedPreferences.getInstance();
      fontScale = prefs.getDouble('chat_text_scale') ?? 1.0;
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('family_chat_v1');
    } catch (_) {}
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('缓存已清除')));
    }
  }

  void _about() {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('关于我们', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        content: const Text('老年数字辅助智能体，陪伴长辈跨越数字鸿沟。当前版本 v1.0。',
            style: TextStyle(fontSize: 19, height: 1.5)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('知道了', style: TextStyle(fontSize: 19))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: load,
      color: AfuColors.primaryDeep,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _profileCard(),
          const SizedBox(height: 16),
          _bindCard(),
          const SizedBox(height: 16),
          _optionsCard(),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () async {
                await ApiService.clearAuth();
                if (context.mounted) {
                  Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginPage()),
                      (r) => false);
                }
              },
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFA8BFE4), width: 1.5),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text('退出登录', style: TextStyle(fontSize: 20)),
            ),
          ),
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
          decoration: const BoxDecoration(
              color: Color(0xFFE8EFFD), shape: BoxShape.circle),
          child:
              ClipOval(child: Image.asset(avatarAsset, width: 72, height: 72, fit: BoxFit.cover)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(nickname,
              style: AfuElderText.body.copyWith(fontWeight: FontWeight.w700)),
        ),
        AfuPressable(
          onTap: _editName,
          borderRadius: 16,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFE8EFFD),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.edit_outlined,
                  size: 22, color: AfuColors.primaryDeep),
              SizedBox(width: 4),
              Text('编辑',
                  style: TextStyle(
                      fontSize: 18, color: AfuColors.primaryDeep)),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _bindCard() {
    return AfuCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('亲人绑定',
            style: AfuElderText.body.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        const Text('已绑定亲人，双方可互相查看健康信息与发送关怀提醒',
            style: AfuElderText.secondary),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: genInvite,
            icon: const Icon(Icons.qr_code_2_outlined, size: 26),
            label: const Text('生成邀请码'),
          ),
        ),
        if (inviteCode.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F8FD),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFDCE6F7)),
            ),
            child: Column(children: [
              SelectableText(inviteCode,
                  style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: AfuColors.primaryDeep)),
              const SizedBox(height: 4),
              const Text('30分钟内有效，把这串码告诉家人',
                  style: AfuElderText.secondary),
            ]),
          ),
        ],
        if (inviteMsg.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(inviteMsg,
              style: const TextStyle(fontSize: 18, color: Colors.red)),
        ],
        const SizedBox(height: 12),
        if (binds.isEmpty)
          const Text('暂无绑定', style: AfuElderText.secondary)
        else
          for (final b in binds) _bindRow(b),
      ]),
    );
  }

  Widget _bindRow(dynamic b) {
    final m =
        b is Map ? Map<String, dynamic>.from(b as Map) : <String, dynamic>{};
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
          decoration: const BoxDecoration(
              color: Color(0xFFE8EFFD), shape: BoxShape.circle),
          child: const Icon(Icons.person,
              size: 30, color: AfuColors.primaryDeep),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name,
                style: AfuElderText.body
                    .copyWith(fontWeight: FontWeight.w700)),
            if (code.isNotEmpty)
              Text('邀请码 $code', style: AfuElderText.secondary),
          ]),
        ),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: active
                ? const Color(0xFFE6F4EA)
                : const Color(0xFFF0F1F5),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(active ? '已绑定' : status,
              style: TextStyle(
                  fontSize: 17,
                  color: active
                      ? const Color(0xFF2E7D4F)
                      : const Color(0xFF555555))),
        ),
      ]),
    );
  }

  Widget _optionsCard() {
    return AfuCard(
      padding: EdgeInsets.zero,
      child: Column(children: [
        _optRow(Icons.notifications_outlined, '消息通知',
            trailing: ValueListenableBuilder<bool>(
              valueListenable: notifyEnabled,
              builder: (c, v, _) => Switch(
                value: v,
                onChanged: (on) async {
                  notifyEnabled.value = on;
                  notifyOn = on;
                  try {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('notify_on', on);
                  } catch (_) {}
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(on ? '消息通知已打开' : '消息通知已关闭')));
                  }
                },
              ),
            )),
        _optRow(Icons.text_fields_outlined, '字体大小调节',
            sub: fontLabel, onTap: _openFontPage),
        _optRow(Icons.cleaning_services_outlined, '清除缓存',
            onTap: _clearCache),
        _optRow(Icons.info_outline, '关于我们', onTap: _about, last: true),
      ]),
    );
  }

  Widget _optRow(IconData icon, String title,
      {String? sub, Widget? trailing, VoidCallback? onTap, bool last = false}) {
    return AfuPressable(
      onTap: onTap,
      borderRadius: 0,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
        decoration: BoxDecoration(
          border: last
              ? null
              : const Border(
                  bottom:
                      BorderSide(color: Color(0xFFEDF1F7), width: 1)),
        ),
        child: Row(children: [
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
                color: Color(0xFFE8EFFD), shape: BoxShape.circle),
            child: Icon(icon, size: 26, color: AfuColors.primaryDeep),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(title,
                style:
                    AfuElderText.body.copyWith(fontWeight: FontWeight.w600)),
          ),
          if (sub != null)
            Text(sub, style: AfuElderText.secondary),
          if (trailing != null)
            trailing
          else
            const Icon(Icons.chevron_right,
                color: AfuColors.secondary, size: 30),
        ]),
      ),
    );
  }
}

/// 字体调节子页：小/中/大三档，全 App 实时生效。
/// Font size page: S/M/L, applies app-wide instantly.
class _FontOpt {
  final String name;
  final String desc;
  final double scale;
  final double demo;
  const _FontOpt(this.name, this.desc, this.scale, this.demo);
}

class _FontPage extends StatefulWidget {
  const _FontPage();
  @override
  State<_FontPage> createState() => _FontPageState();
}

class _FontPageState extends State<_FontPage> {
  static const _opts = [
    _FontOpt('小', '标准大小，看得清', 1.0, 16),
    _FontOpt('中', '稍大一点，更轻松', 1.15, 20),
    _FontOpt('大', '最大字号，专为老花眼', 1.3, 24),
  ];

  Future<void> _pick(double v) async {
    chatScale.value = v;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('chat_text_scale', v);
    } catch (_) {}
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FD),
      appBar: AppBar(
        title: const Text('字体大小调节'),
        backgroundColor: const Color(0xFFF7F9FD),
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          AfuCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              for (var i = 0; i < _opts.length; i++)
                _fontRow(_opts[i], i == _opts.length - 1),
            ]),
          ),
          const SizedBox(height: 16),
          const Text('切换后整个App的文字立即变化，所见即所得',
              style: TextStyle(fontSize: 18, color: Color(0xFF8A94A6), height: 1.6), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _fontRow(_FontOpt o, bool last) {
    return AfuPressable(
      onTap: () => _pick(o.scale),
      borderRadius: 0,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          border: last
              ? null
              : const Border(
                  bottom: BorderSide(color: Color(0xFFEDF1F7), width: 1)),
        ),
        child: Row(children: [
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
                color: Color(0xFFE8EFFD), shape: BoxShape.circle),
            child: Center(
              child: Text(o.name,
                  style: TextStyle(
                      fontSize: o.demo,
                      fontWeight: FontWeight.w800,
                      color: AfuColors.primaryDeep)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text('${o.name}' + '号字',
                style: AfuElderText.body
                    .copyWith(fontWeight: FontWeight.w700)),
          ),
          ValueListenableBuilder<double>(
            valueListenable: chatScale,
            builder: (c, v, _) {
              final sel = (v - o.scale).abs() < 0.01;
              return Icon(
                  sel ? Icons.check_circle : Icons.radio_button_unchecked,
                  size: 30,
                  color: sel
                      ? AfuColors.primaryDeep
                      : const Color(0xFFC9D4EA));
            },
          ),
        ]),
      ),
    );
  }
}
