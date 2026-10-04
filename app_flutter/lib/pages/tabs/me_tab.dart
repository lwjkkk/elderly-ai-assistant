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
  String avatarAsset = kAvatarAssets[0];
String nickname = '长辈';
  bool notifyOn = true;
  // 【对话记录同步家属】开关状态（后端接口待开发，先本地记住）
  bool syncToFamily = true;
  double fontScale = 1.0;

  @override
  void initState() {
    super.initState();
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
      syncToFamily = prefs.getBool('sync_to_family') ?? true;
    } catch (_) {}
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
      onRefresh: _loadPrefs,
      color: AfuColors.primaryDeep,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _profileCard(),
          const SizedBox(height: 24),
          // 隐私开关：对话摘要自动同步给家属
          _privacyCard(),
          const SizedBox(height: 24),
          _optionsCard(),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () async {
                await ApiService.clearAuth();
                if (context.mounted) {
                  Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginPage()),
                      (r) => false);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3478D9),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w700),
              ),
              child: const Text('退出登录'),
            ),
          ),
        ],
      ),
    );
  }

  /// 隐私开关：【对话记录同步家属】
  /// 开启后，AI 对话中自动提取的健康摘要会同步给已绑定家属。
  /// 注：对话摘要提取与自动同步均由后端完成。
  /// 【等待后端接口开发完成】目前后端尚无隐私开关接口，
  /// 此处先做本地状态与 UI 占位，接口就绪后改为调用即可。
  /// 语义已与后端确认：关闭 = 摘要照常生成、长者自己仍可见，仅“家属拉不到”（方案②）。
  /// 因此历史已生成的摘要不删除，家属端 /api/sync 的 chat_summaries 返回空即可。
  Widget _privacyCard() {
    return AfuCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
                color: Color(0xFFE8EFFD), shape: BoxShape.circle),
            child: const Icon(Icons.sync_outlined,
                size: 30, color: AfuColors.primaryDeep),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('对话记录同步家属',
                      style: AfuElderText.body
                          .copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  const Text('开启后，AI 对话中整理的健康摘要会同步给已绑定家属；关闭后仅自己可见，记录仍会保留',
                      style: TextStyle(
                          fontSize: 16, color: Color(0xFF6B7686), height: 1.4)),
                ]),
          ),
          Switch(
            value: syncToFamily,
            activeColor: AfuColors.primaryDeep,
            onChanged: (v) async {
              setState(() => syncToFamily = v);
              try {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('sync_to_family', v);
              } catch (_) {}
              // 【等待后端接口开发完成】后端开关接口就绪后，在此调用上报
            },
          ),
        ]),
      ]),
    );
  }

  /// 头像区：无白色卡片底板，直接放在页面底色上。
  Widget _profileCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
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
        _fontInline(),
        _optRow(Icons.cleaning_services_outlined, '清除缓存',
            onTap: _clearCache),
        _optRow(Icons.info_outline, '关于我们', onTap: _about, last: true),
      ]),
    );
  }

  /// 字体大小行内三胶囊：小/中/大横排，点击直接切换并即时生效，不跳二级页。
  Widget _fontInline() {
    const names = ['小', '中', '大'];
    const scales = [1.0, 1.15, 1.3];
    return AfuCard(
      child: Row(children: [
        const Text('字体大小',
            style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w700,
                color: Color(0xFF222222))),
        const SizedBox(width: 12),
        Expanded(
          child: ValueListenableBuilder<double>(
            valueListenable: chatScale,
            builder: (_, v, __) => Row(children: [
              for (var i = 0; i < names.length; i++) ...[
                Expanded(
                  child: AfuPressable(
                    onTap: () => _pickScale(scales[i]),
                    borderRadius: 18,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: (v - scales[i]).abs() < 0.01
                            ? const Color(0xFF2F6FD6)
                            : const Color(0xFFF0F1F5),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text(names[i],
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                            color: (v - scales[i]).abs() < 0.01
                                ? Colors.white
                                : const Color(0xFF555555),
                          )),
                    ),
                  ),
                ),
                if (i < names.length - 1) const SizedBox(width: 10),
              ],
            ]),
          ),
        ),
      ]),
    );
  }

  /// 选择字号：全局实时生效并本地持久化。
  Future<void> _pickScale(double v) async {
    chatScale.value = v;
    fontScale = v;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('chat_text_scale', v);
    } catch (_) {}
    if (mounted) setState(() {});
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
