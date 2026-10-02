import 'package:flutter/material.dart';
import 'tabs/meds_tab.dart';
import 'tabs/vitals_tab.dart';
import 'tabs/consult_drug_chat_tab.dart';
import 'tabs/me_tab.dart';

/// 老人端：问事 / 查药 / 用药 / 体征 / 自查 / 报告 / 咨询 / 我的
class ElderHome extends StatefulWidget {
  const ElderHome({super.key});
  @override
  State<ElderHome> createState() => _ElderHomeState();
}

class _ElderHomeState extends State<ElderHome> {
  int idx = 0;
  @override
  Widget build(BuildContext context) {
    final pages = const [
      ChatTab(),
      DrugQueryTab(),
      MedsTab(),
      VitalsTab(),
      SymptomTab(),
      ReportTab(),
      ConsultsTab(),
      MeTab(role: 'elder'),
    ];
    const titles = ['问事助手', '查药', '用药提醒', '体征记录', '症状自查', '体检报告', '咨询记录', '我的'];
    return Scaffold(
      appBar: AppBar(title: Text(titles[idx])),
      body: SafeArea(key: ValueKey(idx), child: pages[idx]),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: idx,
        type: BottomNavigationBarType.fixed,
        selectedFontSize: 16,
        unselectedFontSize: 14,
        onTap: (i) => setState(() => idx = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.chat, size: 28), label: '问事'),
          BottomNavigationBarItem(icon: Icon(Icons.search, size: 28), label: '查药'),
          BottomNavigationBarItem(icon: Icon(Icons.medication, size: 28), label: '用药'),
          BottomNavigationBarItem(icon: Icon(Icons.favorite, size: 28), label: '体征'),
          BottomNavigationBarItem(icon: Icon(Icons.health_and_safety, size: 28), label: '自查'),
          BottomNavigationBarItem(icon: Icon(Icons.description, size: 28), label: '报告'),
          BottomNavigationBarItem(icon: Icon(Icons.mic, size: 28), label: '咨询'),
          BottomNavigationBarItem(icon: Icon(Icons.person, size: 28), label: '我的'),
        ],
      ),
    );
  }
}
