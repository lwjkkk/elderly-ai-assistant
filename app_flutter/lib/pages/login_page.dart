import 'package:flutter/material.dart';

import '../afu/afu_theme.dart';
import '../afu/afu_widgets.dart';
import '../services/api.dart';
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
  bool useCode = false;
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
      if (mounted) setState(() => err = '发送失败：${ApiService.friendly(e)}，也可以改用密码登录');
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
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
            builder: (_) =>
                role == 'family' ? const FamilyHome() : const ElderHome()),
      );
    } catch (e) {
      setState(() => err =
          '登录失败：${ApiService.friendly(e)}\n请确认后端已启动且地址正确');
    } finally {
      if (mounted) setState(() => loading = false);
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
      backgroundColor: const Color(0xFFF7F9FD),
      appBar: AppBar(
        title: const Text('登录'),
        backgroundColor: const Color(0xFFF7F9FD),
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
                  border:
                      Border.all(color: const Color(0xFFDCE6F7), width: 3),
                ),
                padding: const EdgeInsets.all(6),
                child: ClipOval(
                    child: Image.asset('assets/assistant_face.png',
                        fit: BoxFit.cover)),
              ),
              const SizedBox(height: 10),
              const Text('欢迎回来',
                  style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF222222))),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: const Color(0xFFDCE6F7)),
                ),
                child: Row(children: [
                  for (final e in [
                    ('elder', '我是长辈'),
                    ('family', '我是家属')
                  ])
                    Expanded(
                      child: AfuPressable(
                        onTap: () => _pickRole(e.$1),
                        borderRadius: 22,
                        child: Container(
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: role == e.$1
                                ? AfuColors.primary
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: Text(e.$2,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: role == e.$1
                                      ? Colors.white
                                      : const Color(0xFF555555))),
                        ),
                      ),
                    ),
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
                  border: Border.all(color: const Color(0xFFDCE6F7)),
                ),
                child: Row(children: [
                  Expanded(
                  child: AfuPressable(
                    onTap: () =>
                        setState(() => useCode = false),
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
                Row(children: [
                  Expanded(
                    child: _field(
                      label: '短信验证码',
                      hint: '请输入短信里的数字',
                      controller: code,
                      keyboard: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 150,
                    height: 76,
                    child: ElevatedButton(
                      onPressed: (sending || cooldown > 0)
                          ? null
                          : _sendCode,
                      child: Text(
                          sending
                              ? '发送中…'
                              : (cooldown > 0
                                  ? '$cooldown秒后重发'
                                  : '获取验证码'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 18)),
                    ),
                  ),
                ])
              else
                _field(
                  label: '密码',
                  hint: isElder ? '请输入密码（已显示）' : '请输入密码（已隐藏）',
                  controller: pwd,
                  obscure: !showPwd,
                  suffix: AfuPressable(
                    onTap: () =>
                        setState(() => showPwd = !showPwd),
                    borderRadius: 24,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(
                          showPwd
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 32,
                          color: AfuColors.primaryDeep),
                    ),
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
                          fontSize: 19,
                          color: Color(0xFFB3261E),
                          height: 1.5)),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 64,
                child: ElevatedButton(
                  onPressed: loading ? null : _login,
                  child: Text(loading ? '登录中…' : '登录',
                      style: const TextStyle(fontSize: 22)),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const RegisterPage())),
                child: const Text('没有账号？去注册',
                    style: TextStyle(fontSize: 21)),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _modeChip(String text, bool active) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: active ? AfuColors.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Text(text,
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: active ? Colors.white : const Color(0xFF222222))),
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
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF222222))),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                    color:
                        AfuColors.primaryDeep.withOpacity(0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 3)),
              ],
            ),
            child: TextField(
              controller: controller,
              keyboardType: keyboard,
              obscureText: obscure,
              style:
                  const TextStyle(fontSize: 21, color: Color(0xFF222222)),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(
                    fontSize: 19, color: Color(0xFF8A94A6)),
                filled: true,
                fillColor: Colors.white,
                suffixIcon: suffix == null
                    ? null
                    : Padding(
                        padding:
                            const EdgeInsets.only(right: 8),
                        child: suffix,
                      ),
                suffixIconConstraints: const BoxConstraints(
                    minWidth: 56, minHeight: 56),
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
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: const BorderSide(
                      color: AfuColors.primary, width: 2),
                ),
              ),
            ),
          ),
        ]);
  }
}
