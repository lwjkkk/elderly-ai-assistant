import 'package:flutter/material.dart';

/// 占位页：Day2~Day5 再填充具体功能，Day1 先保证空壳可切换
class PlaceholderTab extends StatelessWidget {
  final String title;
  final String desc;
  const PlaceholderTab({super.key, required this.title, required this.desc});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title, style: const TextStyle(fontSize: 26))),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.construction, size: 80, color: Colors.orange),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text(desc, textAlign: TextAlign.center, style: const TextStyle(fontSize: 20)),
          ]),
        ),
      ),
    );
  }
}
