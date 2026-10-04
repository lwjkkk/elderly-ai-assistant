import 'package:flutter/material.dart';
import '../services/api.dart';
import '../afu/afu_theme.dart';
import '../afu/afu_widgets.dart';

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
  bool showPwd = false;
  bool loading = false;

  int get minLen => role == 'elder' ? 6 : 8;

  bool _hasRepeat(String v) {
    for (var i = 0; i + 2 < v.length; i++) {
      if (v[i] == v[i + 1] && v[i + 1] == v[i + 2]) return true;
    }
    return false;
  }

  bool _hasSeq(String v) {
    const seqs = ['0123456789', '9876543210'];
    for (final s in seqs) {
      for (var i = 0; i + 5 < s.length; i++) {
        if (v.contains(s.substring(i, i + 6))) return true;
      }
    }
    return false;
  }

  String? _pwdError(String v) {
    if (v.length < minLen) return '\u5bc6\u7801\u6700\u5c11' + ' ' + minLen.toString() + ' \u4f4d';
    if (_hasRepeat(v)) return '\u4e0d\u80fd\u5168\u662f\u91cd\u590d\u5b57\u7b26';
    if (_hasSeq(v)) return '\u4e0d\u80fd\u662f123456\u8fd9\u6837\u7684\u8fde\u53f7';
    if (role != 'elder') {
      if (RegExp(r'^[0-9]+$').hasMatch(v)) return '\u6570\u5b57\u548c\u5b57\u6bcd\u642d\u914d\u66f4\u5b89\u5168';
      if (RegExp(r'^[A-Za-z]+$').hasMatch(v)) return '\u6570\u5b57\u548c\u5b57\u6bcd\u642d\u914d\u66f4\u5b89\u5168';
    }
    return null;
  }

  String _level(String v) {
    if (_pwdError(v) != null) return '\u5f31';
    var kinds = 0;
    if (RegExp(r'[0-9]').hasMatch(v)) kinds++;
    if (RegExp(r'[A-Za-z]').hasMatch(v)) kinds++;
    if (RegExp(r'[^0-9A-Za-z]').hasMatch(v)) kinds++;
    if (v.length >= minLen + 4 && kinds >= 2) return '\u826f\u597d';
    return '\u4e2d\u7b49';
  }

  Future<void> _reg() async {
    if (phone.text.trim().length < 11) {
      setState(() => msg = '\u624b\u673a\u53f7\u4e0d\u5bf9\uff0c\u8bf7\u68c0\u67e511\u4f4d\u6570\u5b57');
      return;
    }
    final err = _pwdError(pwd.text);
    if (err != null) {
      setState(() => msg = err);
      return;
    }
    setState(() { loading = true; msg = ''; });
    try {
      await ApiService.register(phone: phone.text.trim(), password: pwd.text, role: role, nickname: nick.text.trim());
      if (mounted) setState(() => msg = '\u6ce8\u518c\u6210\u529f\uff0c\u8bf7\u8fd4\u56de\u767b\u5f55');
    } catch (e) {
      if (mounted) setState(() => msg = '\u6ce8\u518c\u5931\u8d25\uff1a' + ApiService.friendly(e));
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  void dispose() {
    phone.dispose();
    pwd.dispose();
    nick.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final err = _pwdError(pwd.text);
    final ok = err == null && phone.text.trim().length >= 11 && !loading;
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FD),
      appBar: AppBar(
        title: const Text('\u6ce8\u518c'),
        backgroundColor: const Color(0xFFF7F9FD),
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            _roleRow(),
            const SizedBox(height: 16),
            _label('\u624b\u673a\u53f7'),
            _box(TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              style: const TextStyle(fontSize: 21, color: Color(0xFF222222)),
              onChanged: (_) => setState(() {}),
              decoration: _dec('\u8bf7\u8f93\u516511\u4f4d\u624b\u673a\u53f7'),
            )),
            const SizedBox(height: 16),
            _label('\u5bc6\u7801' + ' ' + (role == 'elder' ? '(\u957f\u8f88\u6700\u5c116\u4f4d)' : '(\u5bb6\u5c5e\u6700\u5c118\u4f4d)')),
            _box(TextField(
              controller: pwd,
              obscureText: !showPwd,
              style: const TextStyle(fontSize: 21, color: Color(0xFF222222)),
              onChanged: (_) => setState(() {}),
              decoration: _dec('\u8bf7\u8f93\u5165\u5bc6\u7801').copyWith(
                suffixIcon: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: AfuPressable(
                    onTap: () => setState(() => showPwd = !showPwd),
                    borderRadius: 24,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(showPwd ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 32, color: AfuColors.primaryDeep),
                    ),
                  ),
                ),
              ),
            )),
            const SizedBox(height: 8),
            Row(children: [
              const Text('\u5bc6\u7801\u5f3a\u5ea6\uff1a', style: TextStyle(fontSize: 18, color: Color(0xFF5A6472))),
              Text(pwd.text.isEmpty ? '-' : _level(pwd.text), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: Color(0xFF5A6472))),
            ]),
            if (err != null && pwd.text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(err, style: const TextStyle(fontSize: 18, color: Color(0xFF5A6472))),
              ),
            const SizedBox(height: 16),
            _label('\u6635\u79f0\uff08\u53ef\u9009\uff09'),
            _box(TextField(
              controller: nick,
              style: const TextStyle(fontSize: 21, color: Color(0xFF222222)),
              decoration: _dec('\u53d6\u4e2a\u597d\u8bb0\u7684\u540d\u5b57'),
            )),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 64,
              child: ElevatedButton(
                onPressed: ok ? _reg : null,
                child: Text(loading ? '\u6ce8\u518c\u4e2d\u2026' : '\u6ce8\u518c', style: const TextStyle(fontSize: 22)),
              ),
            ),
            const SizedBox(height: 12),
            Text(msg, style: const TextStyle(fontSize: 20, color: Color(0xFF222222)), textAlign: TextAlign.center),
          ]),
        ),
      ),
    );
  }

  Widget _roleRow() {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFDCE6F7)),
      ),
      child: Row(children: [
        for (final e in [('elder', '\u6211\u662f\u957f\u8f88'), ('family', '\u6211\u662f\u5bb6\u5c5e')])
          Expanded(
            child: AfuPressable(
              onTap: () => setState(() => role = e.$1),
              borderRadius: 22,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: role == e.$1 ? AfuColors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Text(e.$2,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: role == e.$1 ? Colors.white : const Color(0xFF222222))),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _label(String s) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(s, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFF222222))),
      ),
    );
  }

  Widget _box(Widget f) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(color: AfuColors.primaryDeep.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, 3)),
        ],
      ),
      child: f,
    );
  }

  InputDecoration _dec(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 19, color: Color(0xFF6B7686)),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 19),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: const BorderSide(color: Color(0xFFDCE6F7))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: const BorderSide(color: Color(0xFFDCE6F7))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: const BorderSide(color: AfuColors.primary, width: 2)),
    );
  }
}
