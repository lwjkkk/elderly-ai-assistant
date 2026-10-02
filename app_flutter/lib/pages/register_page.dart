import 'package:flutter/material.dart';
import '../services/api.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});
  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final phone = TextEditingController();
  final pwd = TextEditingController();
  final nick = TextEditingController();
  String role = 'elder';
  String msg = '';

  Future<void> _reg() async {
    try {
      await ApiService.register(
          phone: phone.text.trim(), password: pwd.text, role: role, nickname: nick.text.trim());
      setState(() => msg = '注册成功，请返回登录');
    } catch (e) {
      setState(() => msg = '注册失败：${ApiService.friendly(e)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('注册', style: TextStyle(fontSize: 26))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'elder', label: Text('老人', style: TextStyle(fontSize: 20))),
              ButtonSegment(value: 'family', label: Text('家属', style: TextStyle(fontSize: 20))),
            ],
            selected: {role},
            onSelectionChanged: (s) => setState(() => role = s.first),
          ),
          const SizedBox(height: 16),
          TextField(controller: phone, keyboardType: TextInputType.phone, style: const TextStyle(fontSize: 22), decoration: const InputDecoration(labelText: '手机号', border: OutlineInputBorder())),
          const SizedBox(height: 16),
          TextField(controller: pwd, obscureText: true, style: const TextStyle(fontSize: 22), decoration: const InputDecoration(labelText: '密码', border: OutlineInputBorder())),
          const SizedBox(height: 16),
          TextField(controller: nick, style: const TextStyle(fontSize: 22), decoration: const InputDecoration(labelText: '昵称（可选）', border: OutlineInputBorder())),
          const SizedBox(height: 20),
          ElevatedButton(onPressed: _reg, child: const Text('注册')),
          const SizedBox(height: 12),
          Text(msg, style: const TextStyle(fontSize: 20)),
        ]),
      ),
    );
  }
}
