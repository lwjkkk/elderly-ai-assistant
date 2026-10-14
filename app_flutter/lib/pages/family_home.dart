import 'dart:io';

import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    HubNav.request.addListener(_onHubTab);
  }

  @override
  void dispose() {
    HubNav.tab.removeListener(_onHubTab);
    HubNav.request.removeListener(_onHubTab);
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
      backgroundColor: const Color(0xFFF7FAFD),
      // 全局规则：不再显示页面顶部标题栏，各页面内容直接铺满
      body: SafeArea(key: ValueKey(idx), child: pages[idx]),
      bottomNavigationBar: ValueListenableBuilder<Color?>(
        valueListenable: HubNav.accent,
        builder: (_, accent, __) => BottomNavigationBar(
              currentIndex: idx,
              type: BottomNavigationBarType.fixed,
              selectedFontSize: 15,
              unselectedFontSize: 14,
              selectedItemColor: accent ?? const Color(0xFF345C87),
              unselectedItemColor: const Color(0xFF6B7280),
              onTap: (i) => setState(() => idx = (i == 1 && idx == 1) ? 0 : i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard_outlined, size: 30), label: '健康总览'),
          BottomNavigationBarItem(icon: Icon(Icons.chat_bubble_outline, size: 30), label: 'AI问事'),
          BottomNavigationBarItem(icon: Icon(Icons.family_restroom_outlined, size: 30), label: '家人互动'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline, size: 30), label: '个人中心'),
                ],
              ),
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
  String? inviteCode;
  bool generating = false;
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

  Future<void> _genInvite() async {
    if (generating) return;
    setState(() => generating = true);
    try {
      inviteCode = await ApiService.createInvite();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('生成失败：${ApiService.friendly(e)}')));
      }
    }
    if (mounted) setState(() => generating = false);
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
      color: const Color(0xFF345C87),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _profileCard(),
          const SizedBox(height: 16),
          _fontEntry(),
          const SizedBox(height: 16),
          _bindCard(),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _logout,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF345C87),
                foregroundColor: Colors.white,
                elevation: 2,
                shadowColor:
                    const Color(0xFF345C87).withOpacity(0.3),
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
                color: Color(0xFFEDF4FB), shape: BoxShape.circle),
            child: const Icon(Icons.text_fields_outlined,
                size: 30, color: Color(0xFF345C87)),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text('字体大小',
                style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF212936))),
          ),
          ValueListenableBuilder<double>(
            valueListenable: chatScale,
            builder: (_, v, __) => Text(
              v >= 1.3 ? '大' : (v > 1.05 ? '中' : '小'),
              style: const TextStyle(fontSize: 19, color: Color(0xFF6B7280)),
            ),
          ),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right, size: 28, color: Color(0xFF6B7280)),
        ]),
      ),
    );
  }


  /// 头像信息区：左侧圆形头像（水波纹环绕）+ 右侧用户名与编辑入口。
  /// 头像信息区：无白色卡片底，与长辈端一致，直接放在页面底色上，配波浪动态背景。
  Widget _profileCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(children: [
        _FamRippleAvatar(asset: avatarAsset),
        const SizedBox(width: 14),
        Expanded(
          child: Text(nickname,
              style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF212936))),
        ),
        AfuPressable(
          onTap: () async {
            await Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => _EditProfilePage(
                    nickname: nickname, asset: avatarAsset)));
            await _load();
            if (mounted) setState(() {});
          },
          borderRadius: 16,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFEDF4FB),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Text('编辑',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF345C87))),
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
          style: const TextStyle(fontSize: 21, color: Color(0xFF212936)),
          decoration: InputDecoration(
            hintText: '\u8bf7\u8f93\u51656\u4f4d\u9080\u8bf7\u7801',
            hintStyle: const TextStyle(fontSize: 19, color: Color(0xFF6B7280)),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 19),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(22),
              borderSide: const BorderSide(color: Color(0xFFD8E6F3)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(22),
              borderSide: const BorderSide(color: Color(0xFFD8E6F3)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(22),
              borderSide: const BorderSide(color: Color(0xFF345C87), width: 2),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF345C87),
              foregroundColor: Colors.white,
              elevation: 2,
              shadowColor:
                  const Color(0xFF345C87).withOpacity(0.3),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              padding: const EdgeInsets.symmetric(vertical: 16),
              textStyle: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w700),
            ),
            onPressed: binding ? null : _doBind,
            child: Text(binding ? '\u7ed1\u5b9a\u4e2d\u2026' : '\u786e\u8ba4\u7ed1\u5b9a'),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEDF4FB),
              foregroundColor: const Color(0xFF345C87),
              elevation: 2,
              shadowColor:
                  const Color(0xFF345C87).withOpacity(0.25),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              padding: const EdgeInsets.symmetric(vertical: 16),
              textStyle: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w700),
            ),
            onPressed: generating ? null : _genInvite,
            child: Text(generating ? '生成中…' : '生成邀请码'),
          ),
        ),
        if (inviteCode != null && inviteCode!.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
                horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFEDF4FB),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(children: [
              Expanded(
                child: Text('邀请码：$inviteCode',
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF212936))),
              ),
              AfuPressable(
                onTap: () {
                  Clipboard.setData(
                      ClipboardData(text: inviteCode!));
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('邀请码已复制')));
                },
                borderRadius: 12,
                child: const Padding(
                  padding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text('复制',
                      style: TextStyle(
                          fontSize: 18, color: const Color(0xFF345C87))),
                ),
              ),
            ]),
          ),
        ],
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
        color: const Color(0xFFEDF4FB),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(children: [
        Container(
          width: 52,
          height: 52,
          decoration: const BoxDecoration(color: Color(0xFFFFFFFF), shape: BoxShape.circle),
          child: const Icon(Icons.person, size: 30, color: Color(0xFF345C87)),
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
            color: active ? const Color(0xFFFFFFFF) : const Color(0xFFFFFFFF),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(active ? '\u5df2\u7ed1\u5b9a' : status,
              style: TextStyle(
                  fontSize: 17,
                  color: active ? const Color(0xFF345C87) : const Color(0xFF6B7280))),
        ),
      ]),
    );
  }
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
      await prefs.setBool('font_explicit', true);
    } catch (_) {}
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFD),
      appBar: AppBar(
        title: const Text('字体大小', style: TextStyle(color: Color(0xFF212936))),
        backgroundColor: const Color(0xFFF7FAFD),
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
                                  color: Color(0xFFEDF4FB), width: 1)),
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
                                      color: Color(0xFF212936))),
                              const SizedBox(height: 4),
                              Text(_descs[i],
                                  style: const TextStyle(
                                      fontSize: 16,
                                      color: Color(0xFF6B7280))),
                            ]),
                      ),
                      ValueListenableBuilder<double>(
                        valueListenable: chatScale,
                        builder: (_, v, __) => (v - _scales[i]).abs() < 0.01
                            ? const Icon(Icons.check_circle,
                                size: 28, color: Color(0xFF345C87))
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
  String _remoteAvatar = '';
  bool _avatarChanged = false;
  String _gender = '';
  String _birthYm = '';
  bool _busyAvatar = false;
  bool _loadingProfile = true;

  @override
  void initState() {
    super.initState();
    _loadLocal();
  }

  Future<void> _loadLocal() async {
    // 远端优先：GET /api/users/profile，失败则用本地。
    try {
      final r = await ApiService.getProfile();
      if (!mounted) return;
      final nick = (r['nickname'] ?? '').toString();
      final url = (r['avatar_url'] ?? '').toString();
      setState(() {
        if (nick.isNotEmpty) _nameC.text = nick;
        _gender = (r['gender'] ?? '').toString();
        _birthYm = (r['birth_ym'] ?? '').toString();
        _remoteAvatar = url;
        _loadingProfile = false;
      });
      try {
        final prefs = await SharedPreferences.getInstance();
        if (nick.isNotEmpty) {
          await prefs.setString('nickname', nick);
        }
        await prefs.setString('gender', _gender);
        await prefs.setString('birth_ym', _birthYm);
        await prefs.setString('avatar_url', url);
      } catch (_) {}
      await _syncAvatarFile(url);
    } catch (_) {
      try {
        final prefs = await SharedPreferences.getInstance();
        if (!mounted) return;
        setState(() {
          final a = prefs.getString('avatar');
          if (a != null && a.isNotEmpty) _picked = a;
          _gender = prefs.getString('gender') ?? '';
          _birthYm = prefs.getString('birth_ym') ?? '';
          final n = prefs.getString('nickname');
          if (n != null && n.isNotEmpty) _nameC.text = n;
          _remoteAvatar = prefs.getString('avatar_url') ?? '';
          _loadingProfile = false;
        });
      } catch (_) {
        if (mounted) {
          setState(() => _loadingProfile = false);
        }
      }
    }
  }

  /// 远端头像落本地文件，各处头像（个人中心/聊天）同步更新。
  Future<void> _syncAvatarFile(String url) async {
    if (url.isEmpty) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final dest = File('${dir.path}/avatar.jpg');
      if (await dest.exists()) {
        if (mounted) setState(() => _picked = dest.path);
        return;
      }
      final bytes = await ApiService.avatarBytes(
          ApiService.avatarFullUrl(url));
      if (bytes.isEmpty) return;
      await dest.writeAsBytes(bytes, flush: true);
      if (mounted) setState(() => _picked = dest.path);
    } catch (_) {}
  }

  @override
  void dispose() {
    _nameC.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameC.text.trim();
    List<int>? avatarBytes;
    if (_avatarChanged && _picked != null) {
      try {
        avatarBytes = await File(_picked!).readAsBytes();
      } catch (_) {}
    }
    try {
      final r = await ApiService.updateProfile(
        nickname: name.isEmpty ? null : name,
        gender: _gender,
        birthYm: _birthYm.isEmpty ? null : _birthYm,
        avatarBytes: avatarBytes,
      );
      final prefs = await SharedPreferences.getInstance();
      final nick = (r['nickname'] ?? '').toString();
      if (nick.isNotEmpty) {
        await prefs.setString('nickname', nick);
      }
      await prefs.setString(
          'gender', (r['gender'] ?? '').toString());
      await prefs.setString(
          'birth_ym', (r['birth_ym'] ?? '').toString());
      final url = (r['avatar_url'] ?? '').toString();
      await prefs.setString('avatar_url', url);
      if (_picked != null) {
        await prefs.setString('avatar', _picked!);
      }
      if (mounted) {
        setState(() {
          _remoteAvatar = url;
          _avatarChanged = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('资料已保存，多端已同步')));
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                '保存失败：${ApiService.friendly(e)}')));
      }
    }
  }

  /// 头像：拍照/相册 -> 圆形裁剪（可缩放移动）-> 存应用目录。
  Future<void> _pickAvatar() async {
    if (_busyAvatar) return;
    final src = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(24))),
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.camera_alt_outlined,
                color: Color(0xFF345C87)),
            title: const Text('拍照',
                style: TextStyle(fontSize: 20)),
            onTap: () => Navigator.pop(c, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_outlined,
                color: Color(0xFF345C87)),
            title: const Text('从相册选择',
                style: TextStyle(fontSize: 20)),
            onTap: () => Navigator.pop(c, ImageSource.gallery),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (src == null || !mounted) return;
    setState(() => _busyAvatar = true);
    try {
      final f = await ImagePicker()
          .pickImage(source: src, maxWidth: 1600);
      if (f == null) {
        if (mounted) setState(() => _busyAvatar = false);
        return;
      }
      final cropped = await ImageCropper().cropImage(
        sourcePath: f.path,
        aspectRatio:
            const CropAspectRatio(ratioX: 1, ratioY: 1),
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: '裁剪头像',
            toolbarColor: const Color(0xFF345C87),
            toolbarWidgetColor: Colors.white,
            cropStyle: CropStyle.circle,
            lockAspectRatio: true,
            hideBottomControls: false,
          ),
          IOSUiSettings(
            title: '裁剪头像',
            cropStyle: CropStyle.circle,
            aspectRatioLockEnabled: true,
          ),
          WebUiSettings(context: context),
        ],
      );
      if (cropped == null) {
        if (mounted) setState(() => _busyAvatar = false);
        return;
      }
      final dir = await getApplicationDocumentsDirectory();
      final dest = File('${dir.path}/avatar.jpg');
      await File(cropped.path).copy(dest.path);
      if (mounted) {
        setState(() {
          _picked = dest.path;
          _avatarChanged = true;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content:
                    Text('头像设置失败：${ApiService.friendly(e)}')));
      }
    }
    if (mounted) setState(() => _busyAvatar = false);
  }

  /// 表单行：左侧标签 + 右侧内容区（固定间距），整行可点。
  Widget _row(String label, String value, VoidCallback onTap) {
    return AfuPressable(
      onTap: onTap,
      borderRadius: 16,
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 6, vertical: 18),
        child: Row(children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF212936))),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
                value.isEmpty ? '未设置' : value,
                textAlign: TextAlign.right,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 21,
                    color: value.isEmpty
                        ? const Color(0xFF9AA5B5)
                        : const Color(0xFF345C87))),
          ),
        ]),
      ),
    );
  }

  /// 昵称编辑弹窗。
  Future<void> _editNick() async {
    final c = TextEditingController(text: _nameC.text);
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('修改昵称',
            style: TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.w700,
                color: Color(0xFF212936))),
        content: TextField(
          controller: c,
          autofocus: true,
          style:
              const TextStyle(fontSize: 21, color: Color(0xFF212936)),
          decoration: InputDecoration(
            hintText: '输入新昵称',
            hintStyle: const TextStyle(
                fontSize: 20, color: Color(0xFF6B7280)),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 22, vertical: 19),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(22),
              borderSide:
                  const BorderSide(color: Color(0xFFD8E6F3)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(22),
              borderSide:
                  const BorderSide(color: Color(0xFFD8E6F3)),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('取消',
                  style: TextStyle(
                      fontSize: 20, color: Color(0xFF6B7280)))),
          ElevatedButton(
              onPressed: () => Navigator.pop(d, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor:
                      const Color(0xFF345C87),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(16))),
              child: const Text('确定',
                  style: TextStyle(fontSize: 20))),
        ],
      ),
    );
    if (ok == true && mounted) {
      setState(() => _nameC.text = c.text.trim());
    }
  }

  /// 性别选择弹窗。
  Future<void> _editGender() async {
    final v = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('选择性别',
            style: TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.w700,
                color: Color(0xFF212936))),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final g in ['男', '女'])
            ListTile(
              title: Text(g,
                  style: const TextStyle(fontSize: 21)),
              trailing: _gender == g
                  ? const Icon(Icons.check_circle,
                      color: Color(0xFF345C87))
                  : null,
              onTap: () => Navigator.pop(d, g),
            ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d),
              child: const Text('取消',
                  style: TextStyle(
                      fontSize: 20, color: Color(0xFF6B7280)))),
        ],
      ),
    );
    if (v != null && mounted) setState(() => _gender = v);
  }

  /// 出生年月滚轮选择。
  Future<void> _editBirth() async {
    final now = DateTime.now();
    var y = now.year - 60;
    var mo = 1;
    if (_birthYm.length >= 7) {
      y = int.tryParse(_birthYm.substring(0, 4)) ?? y;
      mo = int.tryParse(_birthYm.substring(5, 7)) ?? mo;
    }
    final ok = await showModalBottomSheet<bool>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(24))),
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Row(children: [
                TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: const Text('取消',
                        style: TextStyle(
                            fontSize: 20,
                            color: Color(0xFF6B7280)))),
                const Expanded(
                  child: Text('选择出生年月',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF212936))),
                ),
                TextButton(
                    onPressed: () => Navigator.pop(c, true),
                    child: const Text('确定',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF345C87)))),
              ]),
            ),
            SizedBox(
              height: 220,
              child: Row(children: [
                Expanded(
                  child: CupertinoPicker(
                    itemExtent: 48,
                    scrollController: FixedExtentScrollController(
                        initialItem: (y - 1900).clamp(
                            0, now.year - 1900)),
                    onSelectedItemChanged: (i) =>
                        setD(() => y = 1900 + i),
                    children: [
                      for (var yy = 1900; yy <= now.year; yy++)
                        Center(
                            child: Text('$yy年',
                                style: const TextStyle(
                                    fontSize: 22))),
                    ],
                  ),
                ),
                Expanded(
                  child: CupertinoPicker(
                    itemExtent: 48,
                    scrollController:
                        FixedExtentScrollController(
                            initialItem: (mo - 1).clamp(0, 11)),
                    onSelectedItemChanged: (i) =>
                        setD(() => mo = i + 1),
                    children: [
                      for (var mm = 1; mm <= 12; mm++)
                        Center(
                            child: Text('$mm月',
                                style: const TextStyle(
                                    fontSize: 22))),
                    ],
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 12),
          ]),
        ),
      ),
    );
    if (ok == true && mounted) {
      setState(() => _birthYm =
          '$y-${mo.toString().padLeft(2, '0')}');
    }
  }

  String get _birthText {
    if (_birthYm.length < 7) return '';
    return '${_birthYm.substring(0, 4)}年${_birthYm.substring(5, 7)}月';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFD),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back,
              color: Color(0xFF212936)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('编辑资料',
            style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: Color(0xFF212936))),
        backgroundColor: const Color(0xFFF7FAFD),
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          // 头像模块：居中头像 + 上传
          AfuCard(
            padding:
                const EdgeInsets.symmetric(vertical: 32),
            child: Column(children: [
              Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                    color: const Color(0xFFEDF4FB),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                          color: const Color(0xFF345C87)
                              .withOpacity(0.12),
                          blurRadius: 12,
                          offset: const Offset(0, 4)),
                    ]),
                child: ClipOval(
                    child: _busyAvatar ||
                            _loadingProfile
                        ? const Center(
                            child: CircularProgressIndicator(
                                color: Color(0xFF345C87)))
                        : _remoteAvatar.isNotEmpty
                            ? Image.network(
                                ApiService.avatarFullUrl(
                                    _remoteAvatar),
                                width: 106,
                                height: 106,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    Image(
                                        image: avatarImage(
                                            _picked ??
                                                widget.asset),
                                        width: 106,
                                        height: 106,
                                        fit: BoxFit.cover),
                              )
                            : Image(
                                image: avatarImage(
                                    _picked ??
                                        widget.asset),
                                width: 106,
                                height: 106,
                                fit: BoxFit.cover)),
              ),
              const SizedBox(height: 16),
              AfuPressable(
                onTap: _busyAvatar ? () {} : _pickAvatar,
                borderRadius: 14,
                child: const Padding(
                  padding:
                      EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Text('上传头像',
                      style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF345C87))),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 20),
          // 资料表单：一行一编辑
          AfuCard(
            padding: const EdgeInsets.symmetric(
                horizontal: 18, vertical: 8),
            child: Column(children: [
              _row('昵称', _nameC.text.trim(), _editNick),
              const Divider(
                  height: 1, color: Color(0xFFEDF4FB)),
              _row('性别', _gender, _editGender),
              const Divider(
                  height: 1, color: Color(0xFFEDF4FB)),
              _row('出生年月', _birthText, _editBirth),
            ]),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _save,
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    const Color(0xFF345C87),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(vertical: 19),
                shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(22)),
                textStyle: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w700),
              ),
              child: const Text('保存'),
            ),
          ),
        ],
      ),
    );
  }
}


/// 家属个人中心头像水波纹：浅蓝半透明圆环，柔和循环向外扩散。
class _FamRippleAvatar extends StatefulWidget {
  final String asset;
  const _FamRippleAvatar({required this.asset});
  @override
  State<_FamRippleAvatar> createState() => _FamRippleAvatarState();
}

class _FamRippleAvatarState extends State<_FamRippleAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2600))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 88,
      height: 88,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => CustomPaint(
          painter: _FamRipplePainter(_c.value),
          child: Center(
            child: Container(
              width: 68,
              height: 68,
              decoration: const BoxDecoration(
                  color: Color(0xFFEDF4FB), shape: BoxShape.circle),
              child: ClipOval(
                  child: Image(image: avatarImage(widget.asset),
                      width: 64, height: 64, fit: BoxFit.cover)),
            ),
          ),
        ),
      ),
    );
  }
}

class _FamRipplePainter extends CustomPainter {
  final double t;
  const _FamRipplePainter(this.t);
  @override
  void paint(Canvas canvas, Size s) {
    final c = Offset(s.width / 2, s.height / 2);
    for (var i = 0; i < 2; i++) {
      final p = (t + i * 0.5) % 1.0;
      canvas.drawCircle(
          c,
          30 + p * 14,
          Paint()
            ..color =
                const Color(0xFF345C87).withOpacity(0.35 * (1 - p))
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4);
    }
  }

  @override
  bool shouldRepaint(covariant _FamRipplePainter old) => old.t != t;
}
