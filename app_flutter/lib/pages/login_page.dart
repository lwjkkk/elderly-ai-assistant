import 'package:flutter/material.dart';
import '../services/api.dart';
import '../theme.dart';
import 'elder_home.dart';
import 'family_home.dart';
import 'register_page.dart';

/// Day1 登录页：大字、大按钮、角色二选一
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final phone = TextEditingController();
  final pwd = TextEditingController();
  String role = 'elder';
  bool loading = false;
  String? err;

  Future<void> _login() async {
    setState(() { loading = true; err = null; });
    Map<String,dynamic>? r;
    try {
      r = await ApiService.login(phone: phone.text.trim(), password: pwd.text);
      role = (r['role'] ?? role).toString();
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => role == 'family' ? const FamilyHome() : const ElderHome()),
      );
    } catch (e) {
      setState(() => err = '登录失败：${ApiService.friendly(e)}\n请确认后端已启动且地址正确');
    } finally {
      setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('登录', style: TextStyle(fontSize: 26))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 12),
            const Text('老人用手机更简单', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'elder', label: Text('我是老人', style: TextStyle(fontSize: 20))),
                ButtonSegment(value: 'family', label: Text('我是家属', style: TextStyle(fontSize: 20))),
              ],
              selected: {role},
              onSelectionChanged: (s) => setState(() => role = s.first),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              style: const TextStyle(fontSize: 22),
              decoration: const InputDecoration(labelText: '手机号', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: pwd,
              obscureText: true,
              style: const TextStyle(fontSize: 22),
              decoration: const InputDecoration(labelText: '密码', border: OutlineInputBorder()),
            ),
            if (err != null) ...[
              const SizedBox(height: 12),
              Card(child: Padding(padding: const EdgeInsets.all(12), child: Text(err!, style: const TextStyle(color: AppColors.danger, fontSize: 18)))),
            ],
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: loading ? null : _login,
              child: Text(loading ? '登录中…' : '登录'),
            ),
            TextButton(
              onPressed: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => const RegisterPage())),
              child: const Text('没有账号？去注册', style: TextStyle(fontSize: 20)),
            ),
          ],
        ),
      ),
    );
  }
}
