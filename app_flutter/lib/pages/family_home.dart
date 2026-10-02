import 'package:flutter/material.dart';
import 'tabs/meds_tab.dart';
import 'tabs/vitals_tab.dart';
import 'tabs/consult_drug_chat_tab.dart';
import 'tabs/me_tab.dart';
import 'bind_page.dart';

/// 家属端：亲人用药 / 体征 / 自查 / 报告 / 绑定 / 我的
class FamilyHome extends StatefulWidget {
  const FamilyHome({super.key});
  @override
  State<FamilyHome> createState() => _FamilyHomeState();
}

class _FamilyHomeState extends State<FamilyHome> {
  int idx = 0;
  @override
  Widget build(BuildContext context) {
    final pages = const [
      MedsTab(readOnly: true),
      VitalsTab(readOnly: true),
      SymptomTab(),
      ReportTab(),
      BindPage(role: 'family'),
      MeTab(role: 'family'),
    ];
    const titles = ['亲人用药', '体征', '自查', '报告', '绑定', '我的'];
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
          BottomNavigationBarItem(icon: Icon(Icons.medication, size: 28), label: '用药'),
          BottomNavigationBarItem(icon: Icon(Icons.favorite, size: 28), label: '体征'),
          BottomNavigationBarItem(icon: Icon(Icons.health_and_safety, size: 28), label: '自查'),
          BottomNavigationBarItem(icon: Icon(Icons.description, size: 28), label: '报告'),
          BottomNavigationBarItem(icon: Icon(Icons.group, size: 28), label: '绑定'),
          BottomNavigationBarItem(icon: Icon(Icons.person, size: 28), label: '我的'),
        ],
      ),
    );
  }
}
