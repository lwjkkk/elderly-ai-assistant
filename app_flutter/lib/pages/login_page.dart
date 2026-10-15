import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../afu/afu_theme.dart';
import '../afu/afu_widgets.dart';
import '../services/api.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'tabs/hub_pages.dart' show chatScale;
import 'elder_home.dart';
import 'family_home.dart';
import 'register_page.dart';

/// 登录页（阿福风）：长辈/家属切换 + 密码/验证码双登录 + 按角色默认显隐密码。
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final phone = TextEditingController();
  final pwd = TextEditingController();
  final code = TextEditingController();
  String role = 'elder';
  bool useCode = true;
  bool showPwd = true;
  bool loading = false;
  bool sending = false;
  int cooldown = 0;
  String? err;

  bool get isElder => role == 'elder';

  void _pickRole(String r) {
    setState(() {
      role = r;
      showPwd = r == 'elder';
    });
    _applyRoleFontDefault();
  }

  /// 按角色默认字号：长辈中(1.15)/家属小(1.0)，用户手动调过则不再覆盖。
  Future<void> _applyRoleFontDefault() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('font_explicit') == true) return;
      final v = role == 'elder' ? 1.15 : 1.0;
      await prefs.setDouble('chat_text_scale', v);
      chatScale.value = v;
    } catch (_) {}
  }

  Future<void> _sendCode() async {
    final p = phone.text.trim();
    if (p.length < 11) {
      setState(() => err = '请先输入正确的11位手机号，再点获取验证码');
      return;
    }
    setState(() {
      sending = true;
      err = null;
    });
    try {
      await ApiService.sendSmsCode(p);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('验证码已发送，请注意查收短信')));
        setState(() => cooldown = 60);
        _tick();
      }
    } catch (e) {
      if (mounted)
        setState(() => err = '发送失败：${ApiService.friendly(e)}，也可以改用密码登录');
    }
    if (mounted) setState(() => sending = false);
  }

  Future<void> _tick() async {
    while (cooldown > 0 && mounted) {
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!mounted) break;
      setState(() => cooldown--);
    }
  }

  Future<void> _login() async {
    if (phone.text.trim().length < 11) {
      setState(() => err = '手机号不对，请检查是不是11位数字');
      return;
    }
    if (useCode && code.text.trim().isEmpty) {
      setState(() => err = '验证码还没填，请看短信输入数字');
      return;
    }
    if (!useCode && pwd.text.isEmpty) {
      setState(() => err = '密码还没填，请输入密码');
      return;
    }
    setState(() {
      loading = true;
      err = null;
    });
    Map<String, dynamic>? r;
    try {
      r = useCode
          ? await ApiService.loginSms(
              phone: phone.text.trim(), code: code.text.trim())
          : await ApiService.login(
              phone: phone.text.trim(), password: pwd.text);
      role = (r['role'] ?? role).toString();
      await _syncLegacyAvatar();
      if (!mounted) return;
      await _applyRoleFontDefault();
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
            builder: (_) =>
                role == 'family' ? const FamilyHome() : const ElderHome()),
      );
    } catch (e) {
      setState(() => err = '登录失败：${ApiService.friendly(e)}\n请确认后端已启动且地址正确');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  /// 兼容旧版本：以前注册头像只保存在本机，首次登录后补传到服务端。
  Future<void> _syncLegacyAvatar() async {
    try {
      final profile = await ApiService.getProfile();
      if ((profile['avatar_url'] ?? '').toString().isNotEmpty) return;
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('avatar_${phone.text.trim()}') ??
          prefs.getString('avatar');
      if (saved == null || saved.isEmpty) return;
      final bytes = saved.startsWith('assets/')
          ? (await rootBundle.load(saved)).buffer.asUint8List()
          : (!kIsWeb ? await File(saved).readAsBytes() : null);
      if (bytes != null && bytes.isNotEmpty) {
        await ApiService.updateProfile(avatarBytes: bytes);
      }
    } catch (_) {
      // 头像补传不影响正常登录。
    }
  }

  @override
  void dispose() {
    phone.dispose();
    pwd.dispose();
    code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFD),
      appBar: AppBar(
        title: const Text('登录',
            style: TextStyle(
                color: Color(0xFF182F4D), fontWeight: FontWeight.w700)),
        backgroundColor: const Color(0xFFF7FAFD),
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              const SizedBox(height: 4),
              Container(
                width: 108,
                height: 108,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  border: Border.all(color: const Color(0xFFDCE7F5), width: 2),
                ),
                padding: const EdgeInsets.all(6),
                child: ClipOval(
                    child: Image.asset('assets/assistant_face.png',
                        fit: BoxFit.cover)),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: const Color(0xFFAFC6E0))),
                child: Row(children: [
                  for (var _i = 0; _i < 2; _i++) ...[
                    Expanded(
                      child: AfuPressable(
                        onTap: () => _pickRole(_i == 0 ? 'elder' : 'family'),
                        borderRadius: 22,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: role == (_i == 0 ? 'elder' : 'family')
                                ? const Color(0xFF40689B)
                                : const Color(0xFFFFFFFF),
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: Text(_i == 0 ? '我是长辈' : '我是家属',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: role == (_i == 0 ? 'elder' : 'family')
                                      ? const Color(0xFFFFFFFF)
                                      : const Color(0xFF182F4D))),
                        ),
                      ),
                    ),
                    if (_i == 0) const SizedBox(width: 10),
                  ],
                ]),
              ),
              const SizedBox(height: 16),
              _field(
                label: '手机号',
                hint: '请输入11位手机号',
                controller: phone,
                keyboard: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: const Color(0xFFAFC6E0)),
                ),
                child: Row(children: [
                  Expanded(
                    child: AfuPressable(
                      onTap: () => setState(() => useCode = false),
                      borderRadius: 22,
                      child: _modeChip('密码登录', !useCode),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: AfuPressable(
                      onTap: () => setState(() => useCode = true),
                      borderRadius: 22,
                      child: _modeChip('验证码登录', useCode),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 12),
              if (useCode)
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: _field(
                      label: '短信验证码',
                      hint: '在这里输入',
                      controller: code,
                      keyboard: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(children: [
                    const SizedBox(height: 30),
                    SizedBox(
                      width: 150,
                      height: 72,
                      child: ElevatedButton(
                        onPressed: (sending || cooldown > 0) ? null : _sendCode,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFDCE7F5),
                          foregroundColor: const Color(0xFF40689B),
                          elevation: 2,
                          shadowColor:
                              const Color(0xFF40689B).withOpacity(0.25),
                          disabledBackgroundColor: const Color(0xFFE9ECEF),
                          disabledForegroundColor: const Color(0xFF6B7280),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(22)),
                        ),
                        child: Text(
                            sending
                                ? '发送中…'
                                : (cooldown > 0 ? '$cooldown秒后重发' : '获取验证码'),
                            textAlign: TextAlign.center,
                            softWrap: false,
                            style: const TextStyle(
                                fontSize: 17, fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ]),
                ])
              else
                _field(
                  label: '密码',
                  hint: isElder ? '请输入密码（已显示）' : '请输入密码（已隐藏）',
                  controller: pwd,
                  obscure: !showPwd,
                  suffix: IconButton(
                    onPressed: () => setState(() => showPwd = !showPwd),
                    icon: Icon(
                        showPwd
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 32,
                        color: const Color(0xFF40689B)),
                  ),
                ),
              if (err != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFDECEC),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(err!,
                      style: const TextStyle(
                          fontSize: 19, color: Color(0xFFB3261E), height: 1.5)),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 64,
                child: ElevatedButton(
                  onPressed: loading ? null : _login,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF40689B),
                    foregroundColor: Colors.white,
                    elevation: 3,
                    shadowColor: const Color(0xFF40689B).withOpacity(0.35),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24)),
                  ),
                  child: Text(loading ? '登录中…' : '登录',
                      style: const TextStyle(
                          fontSize: 24, fontWeight: FontWeight.w700)),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('没有账号？',
                      style: TextStyle(fontSize: 21, color: Color(0xFF6B7280))),
                  TextButton(
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const RegisterPage())),
                    child: const Text('去注册',
                        style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF40689B))),
                  ),
                ],
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _modeChip(String text, bool active) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: active ? const Color(0xFF40689B) : const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(text,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: active
                    ? const Color(0xFFFFFFFF)
                    : const Color(0xFF6B7280))),
        if (active) ...[
          const SizedBox(height: 4),
          Container(
            width: 28,
            height: 3,
            decoration: BoxDecoration(
              color: const Color(0xFFFFFFFF),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _field({
    required String label,
    required String hint,
    required TextEditingController controller,
    TextInputType? keyboard,
    bool obscure = false,
    Widget? suffix,
  }) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: const TextStyle(
              fontSize: 22,
              height: 1.0,
              fontWeight: FontWeight.w700,
              color: Color(0xFF182F4D))),
      const SizedBox(height: 8),
      Container(
        height: 72,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
                color: const Color(0xFF40689B).withOpacity(0.06),
                blurRadius: 10,
                offset: const Offset(0, 3)),
          ],
        ),
        child: TextField(
          controller: controller,
          keyboardType: keyboard,
          obscureText: obscure,
          cursorColor: const Color(0xFF40689B),
          expands: !obscure,
          maxLines: obscure ? 1 : null,
          textAlignVertical: TextAlignVertical.center,
          style: const TextStyle(fontSize: 22, color: Color(0xFF182F4D)),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Color(0xFF6B7280)),
            filled: true,
            fillColor: Colors.white,
            suffixIcon: suffix == null
                ? null
                : Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: suffix,
                  ),
            suffixIconConstraints:
                const BoxConstraints(minWidth: 56, minHeight: 56),
            contentPadding: const EdgeInsets.symmetric(horizontal: 22),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(22),
              borderSide: const BorderSide(color: Color(0xFFAFC6E0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(22),
              borderSide: const BorderSide(color: Color(0xFFAFC6E0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(22),
              borderSide: const BorderSide(color: Color(0xFF40689B), width: 2),
            ),
          ),
        ),
      ),
    ]);
  }
}
