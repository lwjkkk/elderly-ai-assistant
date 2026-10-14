import 'package:flutter/material.dart';

/// 体征、报告共用个人中心的蓝色配色。
class HealthRecordStyle {
  static const background = Color(0xFFF7F9FD);
  static const primary = Color(0xFF345C87);
  static const soft = Color(0xFFEDF4FB);
  static const ink = Color(0xFF212936);
  static const secondary = Color(0xFF6B7280);
  static const border = Color(0xFFD8E6F3);

  static Widget button(String label, IconData icon, VoidCallback? onPressed) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 26),
      label: Text(label, textAlign: TextAlign.center),
      style: ElevatedButton.styleFrom(
        backgroundColor: soft,
        foregroundColor: primary,
        disabledBackgroundColor: soft,
        disabledForegroundColor: secondary,
        elevation: 0,
        minimumSize: const Size(0, 60),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  static Widget panel(Widget child) => Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 230),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(20),
        ),
        child: child,
      );

  static Widget empty(IconData icon, String text) => SizedBox(
        height: 190,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 58, color: primary),
          const SizedBox(height: 22),
          Text(text,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 19, color: secondary, height: 1.5)),
        ]),
      );
}

class HealthRecordPage extends StatelessWidget {
  final Widget child;
  const HealthRecordPage({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: HealthRecordStyle.primary, surface: Colors.white),
        ),
        child: Scaffold(
          backgroundColor: HealthRecordStyle.background,
          body: SafeArea(
              child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Align(
                  alignment: Alignment.centerLeft,
                  child: HealthRecordStyle.button('退出', Icons.arrow_back,
                      () => Navigator.of(context).pop())),
            ),
            Expanded(child: child),
          ])),
        ),
      );
}
