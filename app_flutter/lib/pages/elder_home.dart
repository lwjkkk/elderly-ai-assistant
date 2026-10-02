import 'package:flutter/material.dart';
import '../services/api.dart';
import 'tabs/placeholder_tab.dart';
import 'bind_page.dart';

/// 老人端 5 Tab：问事 / 用药提醒 / 体征记录 / 咨询记录 / 我的
class ElderHome extends StatefulWidget {
  const ElderHome({super.key});
  @override
  State<ElderHome> createState() => _ElderHomeState();
}

class _ElderHomeState extends State<ElderHome> {
  int idx = 0;
  @override
  Widget build(BuildContext context) {
    final pages = [
      const PlaceholderTab(title: '问事助手', desc: 'Day5 迁移原有 RAG 问答 + 截图 + 方言语音到此页'),
      const PlaceholderTab(title: '用药提醒', desc: 'Day2：录药、打卡、推送'),
      const PlaceholderTab(title: '体征记录', desc: 'Day3：血压血糖曲线 + PDF'),
      const PlaceholderTab(title: '咨询记录', desc: 'Day3：录音上传同步'),
      BindPage(role: 'elder', onLogout: () async {
        await ApiService.clearAuth();
      }),
    ];
    return Scaffold(
      body: pages[idx],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: idx,
        type: BottomNavigationBarType.fixed,
        selectedFontSize: 18,
        unselectedFontSize: 16,
        onTap: (i) => setState(() => idx = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.chat, size: 32), label: '问事'),
          BottomNavigationBarItem(icon: Icon(Icons.medication, size: 32), label: '用药'),
          BottomNavigationBarItem(icon: Icon(Icons.favorite, size: 32), label: '体征'),
          BottomNavigationBarItem(icon: Icon(Icons.mic, size: 32), label: '咨询'),
          BottomNavigationBarItem(icon: Icon(Icons.person, size: 32), label: '我的'),
        ],
      ),
    );
  }
}
