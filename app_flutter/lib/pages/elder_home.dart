import 'package:flutter/material.dart';

import '../afu/afu_theme.dart';
import 'tabs/consult_drug_chat_tab.dart';
import 'tabs/hub_pages.dart';

/// 长辈端 4 Tab：问事 / 健康百事 / 家人相伴 / 设置。
class ElderHome extends StatefulWidget {
  const ElderHome({super.key});
  @override
  State<ElderHome> createState() => _ElderHomeState();
}

class _ElderHomeState extends State<ElderHome> {
  int idx = 0;

  @override
  void initState() {
    super.initState();
    HubNav.tab.addListener(_onHubTab);
  }

  @override
  void dispose() {
    HubNav.tab.removeListener(_onHubTab);
    super.dispose();
  }

  void _onHubTab() {
    if (mounted && HubNav.tab.value != idx) {
      setState(() => idx = HubNav.tab.value);
    }
  }

  @override
  Widget build(BuildContext context) {
    const pages = [
      ChatTab(),
      HealthHubTab(),
      FamilyTab(),
      SettingsTab(),
    ];
    const labels = ['问事', '健康百事', '家人相伴', '设置'];
    const icons = [Icons.chat_bubble, Icons.grid_view, Icons.family_restroom, Icons.settings];
    return Scaffold(
      body: IndexedStack(index: idx, children: pages),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: idx,
        type: BottomNavigationBarType.fixed,
        selectedFontSize: 16,
        unselectedFontSize: 16,
        iconSize: 30,
        onTap: (i) => setState(() => idx = i),
        items: [for (var i = 0; i < labels.length; i++) BottomNavigationBarItem(icon: Icon(icons[i]), label: labels[i])],
      ),
    );
  }
}
