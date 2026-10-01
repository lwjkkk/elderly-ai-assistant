import 'package:flutter/material.dart';
import 'tabs/placeholder_tab.dart';
import 'bind_page.dart';

/// 家属端 4 Tab：亲人用药 / 体征 / 绑定管理 / 我的
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
      PlaceholderTab(title: '亲人用药', desc: 'Day2：查看老人打卡，漏服红色提醒'),
      PlaceholderTab(title: '体征', desc: 'Day3：查看老人曲线和 PDF'),
      BindPage(role: 'family'),
      PlaceholderTab(title: '我的', desc: '账号与设置'),
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
          BottomNavigationBarItem(icon: Icon(Icons.medication, size: 32), label: '用药'),
          BottomNavigationBarItem(icon: Icon(Icons.favorite, size: 32), label: '体征'),
          BottomNavigationBarItem(icon: Icon(Icons.group, size: 32), label: '绑定'),
          BottomNavigationBarItem(icon: Icon(Icons.person, size: 32), label: '我的'),
        ],
      ),
    );
  }
}
