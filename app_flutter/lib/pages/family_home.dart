import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';

import '../afu/afu_theme.dart';
import '../afu/afu_widgets.dart';
import '../services/api.dart';
 
import 'tabs/health_overview.dart';
 
 
import 'login_page.dart';
import 'tabs/consult_drug_chat_tab.dart' show ChatTab;
import 'tabs/hub_pages.dart' show FamilyTab, chatScale, HubNav;

/// 家属端 4Tab：健康总览 / 体征 / 报告 / 我的（阿福风统一视觉）。
class FamilyHome extends StatefulWidget {
  const FamilyHome({super.key});
  @override
  State<FamilyHome> createState() => _FamilyHomeState();
}

class _FamilyHomeState extends State<FamilyHome> {
  int idx = 1;

  @override
  void initState() {
    super.initState();
    // 响应跨 Tab 跳转（如总览页「分享记录」→ 家人互动）
    HubNav.tab.addListener(_onHubTab);
  }

  @override
  void dispose() {
    HubNav.tab.removeListener(_onHubTab);
    super.dispose();
  }

  void _onHubTab() {
    if (mounted && HubNav.tab.value != idx) {
      setState(() => idx = HubNav.tab.value);
    }
  }

    @override
  Widget build(BuildContext context) {
    const pages = [
      HealthOverviewTab(role: 'family'),
      ChatTab(),
      FamilyTab(),
      FamMe(),
    ];
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FD),
      // 全局规则：不再显示页面顶部标题栏，各页面内容直接铺满
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
          const SizedBox(height: 24),
          _fontEntry(),
          const SizedBox(height: 24),
          _bindCard(),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _logout,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3478D9),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              child: const Text('\u9000\u51fa\u767b\u5f55'),
            ),
          ),
        ],
      ),
    );
  }

  /// 字体大小入口：点击跳转新页面，小/中/大三档（与长辈端同一套设置）。
  Widget _fontEntry() {
    return AfuCard(
      child: AfuPressable(
        onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const _FontSizePage())),
        borderRadius: 18,
        child: Row(children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
                color: Color(0xFFE8EFFD), shape: BoxShape.circle),
            child: const Icon(Icons.text_fields_outlined,
                size: 30, color: AfuColors.primaryDeep),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text('字体大小',
                style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF222222))),
          ),
          ValueListenableBuilder<double>(
            valueListenable: chatScale,
            builder: (_, v, __) => Text(
              v >= 1.3 ? '大' : (v > 1.05 ? '中' : '小'),
              style: const TextStyle(fontSize: 19, color: Color(0xFF6B7686)),
            ),
          ),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right, size: 28, color: Color(0xFF8A94A6)),
        ]),
      ),
    );
  }


  /// 头像信息区：左侧圆形头像（水波纹环绕）+ 右侧用户名与编辑入口。
  Widget _profileCard() {
    return AfuCard(
      child: Row(children: [
        _RippleAvatar(asset: avatarAsset),
        const SizedBox(width: 14),
        Expanded(
          child: Text(nickname,
              style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF222222))),
        ),
        AfuPressable(
          onTap: () async {
            await Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => _EditProfilePage(
                    nickname: nickname, asset: avatarAsset)));
            await _load();
            if (mounted) setState(() {});
          },
          borderRadius: 14,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Text('编辑',
                style: TextStyle(fontSize: 17, color: Color(0xFF6B7686))),
          ),
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
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3478D9),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
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

/// 左侧圆形头像：淡淡水波纹环绕动画。
class _RippleAvatar extends StatefulWidget {
  final String asset;
  const _RippleAvatar({required this.asset});
  @override
  State<_RippleAvatar> createState() => _RippleAvatarState();
}

class _RippleAvatarState extends State<_RippleAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2400))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 84,
      height: 84,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => CustomPaint(
          painter: _RipplePainter(_c.value),
          child: Center(
            child: Container(
              width: 68,
              height: 68,
              decoration: const BoxDecoration(
                  color: Color(0xFFEBF1FB), shape: BoxShape.circle),
              child: ClipOval(
                  child: Image.asset(widget.asset,
                      width: 64, height: 64, fit: BoxFit.cover)),
            ),
          ),
        ),
      ),
    );
  }
}

class _RipplePainter extends CustomPainter {
  final double t;
  const _RipplePainter(this.t);
  @override
  void paint(Canvas canvas, Size s) {
    final c = Offset(s.width / 2, s.height / 2);
    for (var i = 0; i < 2; i++) {
      final p = (t + i * 0.5) % 1.0;
      canvas.drawCircle(
          c,
          30 + p * 12,
          Paint()
            ..color = const Color(0xFF3478D9).withOpacity(0.18 * (1 - p))
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3);
    }
  }

  @override
  bool shouldRepaint(covariant _RipplePainter old) => old.t != t;
}

/// 字体大小选择页：小/中/大三档，全 App 实时生效。
class _FontSizePage extends StatefulWidget {
  const _FontSizePage();
  @override
  State<_FontSizePage> createState() => _FontSizePageState();
}

class _FontSizePageState extends State<_FontSizePage> {
  static const _names = ['小', '中', '大'];
  static const _descs = ['标准大小，看得清', '稍大一点，更轻松', '最大字号，专为老花眼'];
  static const _scales = [1.0, 1.15, 1.3];

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
        title: const Text('字体大小', style: TextStyle(color: Color(0xFF222222))),
        backgroundColor: const Color(0xFFF7F9FD),
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          AfuCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              for (var i = 0; i < _names.length; i++)
                AfuPressable(
                  onTap: () => _pick(_scales[i]),
                  borderRadius: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 18),
                    decoration: BoxDecoration(
                      border: i == _names.length - 1
                          ? null
                          : const Border(
                              bottom: BorderSide(
                                  color: Color(0xFFEDF1F7), width: 1)),
                    ),
                    child: Row(children: [
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_names[i],
                                  style: const TextStyle(
                                      fontSize: 21,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF222222))),
                              const SizedBox(height: 4),
                              Text(_descs[i],
                                  style: const TextStyle(
                                      fontSize: 16,
                                      color: Color(0xFF6B7686))),
                            ]),
                      ),
                      ValueListenableBuilder<double>(
                        valueListenable: chatScale,
                        builder: (_, v, __) => (v - _scales[i]).abs() < 0.01
                            ? const Icon(Icons.check_circle,
                                size: 28, color: Color(0xFF3478D9))
                            : const SizedBox(width: 28),
                      ),
                    ]),
                  ),
                ),
            ]),
          ),
        ],
      ),
    );
  }
}

/// 编辑资料页：修改昵称、上传自定义头像。
class _EditProfilePage extends StatefulWidget {
  final String nickname;
  final String asset;
  const _EditProfilePage({required this.nickname, required this.asset});
  @override
  State<_EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<_EditProfilePage> {
  late final TextEditingController _nameC =
      TextEditingController(text: widget.nickname);
  String? _picked;

  @override
  void dispose() {
    _nameC.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameC.text.trim();
    try {
      final prefs = await SharedPreferences.getInstance();
      if (name.isNotEmpty) {
        await prefs.setString('nickname', name);
      }
      if (_picked != null) await prefs.setString('avatar', _picked!);
    } catch (_) {}
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FD),
      appBar: AppBar(
        title: const Text('编辑资料', style: TextStyle(color: Color(0xFF222222))),
        backgroundColor: const Color(0xFFF7F9FD),
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          AfuCard(
            child: Column(children: [
              Container(
                width: 96,
                height: 96,
                decoration: const BoxDecoration(
                    color: Color(0xFFEBF1FB), shape: BoxShape.circle),
                child: ClipOval(
                    child: Image.asset(widget.asset,
                        width: 92, height: 92, fit: BoxFit.cover)),
              ),
              const SizedBox(height: 12),
              AfuPressable(
                onTap: () {
                  // 【等待后端接口开发完成】头像上传接口就绪后在此接入
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('头像上传功能即将上线')));
                },
                borderRadius: 14,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Text('上传头像',
                      style: TextStyle(fontSize: 18, color: Color(0xFF3478D9))),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          AfuCard(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('昵称',
                      style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF222222))),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _nameC,
                    style: const TextStyle(
                        fontSize: 20, color: Color(0xFF222222)),
                    decoration: InputDecoration(
                      hintText: '输入新昵称',
                      hintStyle: const TextStyle(
                          fontSize: 19, color: Color(0xFF6B7686)),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 22, vertical: 19),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide:
                            const BorderSide(color: Color(0xFFDCE6F7)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide:
                            const BorderSide(color: Color(0xFFDCE6F7)),
                      ),
                    ),
                  ),
                ]),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3478D9),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w700),
              ),
              child: const Text('保存'),
            ),
          ),
        ],
      ),
    );
  }
}
