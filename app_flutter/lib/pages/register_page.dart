import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
int avatarIdx = 0;
String? customPath;

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
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('avatar',
            customPath ?? kAvatarAssets[avatarIdx]);
      } catch (_) {}
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
      backgroundColor: const Color(0xFFF7FAFD),
      appBar: AppBar(
        title: const Text('注册', style: TextStyle(color: Color(0xFF182F4D), fontWeight: FontWeight.w700)),
        iconTheme: const IconThemeData(color: Color(0xFF182F4D)),
        backgroundColor: const Color(0xFFF7FAFD),
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
              cursorColor: const Color(0xFF40689B),
              keyboardType: TextInputType.phone,
              style: const TextStyle(fontSize: 21, color: Color(0xFF182F4D)),
              onChanged: (_) => setState(() {}),
              decoration: _dec('\u8bf7\u8f93\u516511\u4f4d\u624b\u673a\u53f7'),
            )),
            const SizedBox(height: 16),
            _label('\u5bc6\u7801' + ' ' + (role == 'elder' ? '(\u957f\u8f88\u6700\u5c116\u4f4d)' : '(\u5bb6\u5c5e\u6700\u5c118\u4f4d)')),
            _box(TextField(
              controller: pwd,
              cursorColor: const Color(0xFF40689B),
              obscureText: !showPwd,
              style: const TextStyle(fontSize: 21, color: Color(0xFF182F4D)),
              onChanged: (_) => setState(() {}),
              decoration: _dec('\u8bf7\u8f93\u5165\u5bc6\u7801').copyWith(
                suffixIcon: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: AfuPressable(
                    onTap: () => setState(() => showPwd = !showPwd),
                    borderRadius: 24,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(showPwd ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 32, color: const Color(0xFF40689B)),
                    ),
                  ),
                ),
              ),
            )),
            const SizedBox(height: 8),
            Row(children: [
              const Text('\u5bc6\u7801\u5f3a\u5ea6\uff1a', style: TextStyle(fontSize: 18, color: Color(0xFF6B7280))),
              Text(pwd.text.isEmpty ? '-' : _level(pwd.text), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: Color(0xFF6B7280))),
            ]),
            if (err != null && pwd.text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(err, style: const TextStyle(fontSize: 18, color: Color(0xFF6B7280))),
              ),
            const SizedBox(height: 16),
            _label('\u6635\u79f0\uff08\u53ef\u9009\uff09'),
            _box(TextField(
              controller: nick,
              cursorColor: const Color(0xFF40689B),
              style: const TextStyle(fontSize: 21, color: Color(0xFF182F4D)),
              decoration: _dec('\u53d6\u4e2a\u597d\u8bb0\u7684\u540d\u5b57'),
            )),
            _label('选择头像'),
            _avatarRow(),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 64,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF40689B),
                  foregroundColor: Colors.white,
                  elevation: 2,
                  shadowColor:
                      const Color(0xFF40689B).withOpacity(0.3),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22)),
                ),
                onPressed: ok ? _reg : null,
                child: Text(loading ? '\u6ce8\u518c\u4e2d\u2026' : '\u6ce8\u518c', style: const TextStyle(fontSize: 22)),
              ),
            ),
            const SizedBox(height: 12),
            Text(msg, style: const TextStyle(fontSize: 20, color: Color(0xFF182F4D)), textAlign: TextAlign.center),
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
        border: Border.all(color: const Color(0xFFAFC6E0)),
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
                  color: role == e.$1 ? const Color(0xFF40689B) : Colors.transparent,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Text(e.$2,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: role == e.$1 ? Colors.white : const Color(0xFF182F4D))),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _avatarRow() {
    final customSelected = avatarIdx == kAvatarAssets.length;
    return Wrap(
      spacing: 14,
      runSpacing: 14,
      children: [
        for (var i = 0; i < kAvatarAssets.length; i++)
          AfuPressable(
            onTap: () => setState(() => avatarIdx = i),
            borderRadius: 48,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: avatarIdx == i ? const Color(0xFF40689B) : const Color(0xFFAFC6E0),
                    width: avatarIdx == i ? 3 : 1.5),
              ),
              child: ClipOval(
                child: Image.asset(kAvatarAssets[i], width: 72, height: 72, fit: BoxFit.cover),
              ),
            ),
          ),
        // 自定义头像：加号圆圈，尺寸描边与预设一致
        AfuPressable(
          onTap: _pickCustomAvatar,
          borderRadius: 48,
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                  color: customSelected
                      ? const Color(0xFF40689B)
                      : const Color(0xFFAFC6E0),
                  width: customSelected ? 3 : 1.5),
            ),
            child: ClipOval(
              child: Container(
                width: 72,
                height: 72,
                color: const Color(0xFFFFFFFF),
                child: customPath != null
                    ? Image.file(
                        File(customPath!),
                        width: 72,
                        height: 72,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(
                            Icons.add,
                            size: 40,
                            color: const Color(0xFF40689B)),
                      )
                    : const Icon(Icons.add,
                        size: 40, color: const Color(0xFF40689B)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 自定义头像：拍照或从相册上传，存入应用目录并选中。
  Future<void> _pickCustomAvatar() async {
    final src = await showDialog<ImageSource>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('自定义头像',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Color(0xFF182F4D))),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            width: double.infinity,
            height: 60,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF40689B),
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(c, ImageSource.camera),
              icon: const Icon(Icons.photo_camera_outlined, size: 28),
              label: const Text('拍照', style: TextStyle(fontSize: 21)),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 60,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF40689B),
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(c, ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined, size: 28),
              label:
                  const Text('从相册上传图片', style: TextStyle(fontSize: 21)),
            ),
          ),
        ]),
      ),
    );
    if (src == null) return;
    try {
      final f =
          await ImagePicker().pickImage(source: src, maxWidth: 512);
      if (f == null) return;
      final dir = await getApplicationDocumentsDirectory();
      final saved = File('${dir.path}/avatar_custom.jpg');
      await saved.writeAsBytes(await f.readAsBytes());
      if (!mounted) return;
      setState(() {
        customPath = saved.path;
        avatarIdx = kAvatarAssets.length;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('头像保存失败：${ApiService.friendly(e)}')));
      }
    }
  }

Widget _label(String s) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(s, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFF182F4D))),
      ),
    );
  }

  Widget _box(Widget f) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(color: const Color(0xFF40689B).withOpacity(0.06), blurRadius: 10, offset: const Offset(0, 3)),
        ],
      ),
      child: f,
    );
  }

  InputDecoration _dec(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 19, color: Color(0xFF6B7280)),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 19),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: const BorderSide(color: Color(0xFFAFC6E0))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: const BorderSide(color: Color(0xFFAFC6E0))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: const BorderSide(color: const Color(0xFF40689B), width: 2)),
    );
  }
}
