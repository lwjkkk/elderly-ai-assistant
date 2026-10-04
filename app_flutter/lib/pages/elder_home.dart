import 'package:flutter/material.dart';
import '../afu/afu_theme.dart';
import 'tabs/consult_drug_chat_tab.dart';
import 'tabs/hub_pages.dart';
import 'tabs/health_overview.dart';

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
      HealthOverviewTab(role: 'elder'),
      ChatTab(),
      FamilyTab(),
      SettingsTab(),
    ];
    const labels = ['\u5065\u5eb7\u603b\u89c8', 'AI\u95ee\u4e8b', '\u5bb6\u4eba\u4e92\u52a8', '\u4e2a\u4eba\u4e2d\u5fc3'];
    const icons = [Icons.dashboard_outlined, Icons.chat_bubble_outline, Icons.family_restroom_outlined, Icons.person_outline];
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FD),
      body: SafeArea(key: ValueKey(idx), child: pages[idx]),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: idx,
        type: BottomNavigationBarType.fixed,
        selectedFontSize: 16,
        unselectedFontSize: 16,
        selectedItemColor: AfuColors.primaryDeep,
        unselectedItemColor: const Color(0xFF5A6472),
        onTap: (i) => setState(() => idx = i),
        items: [
          for (var i = 0; i < labels.length; i++)
            BottomNavigationBarItem(icon: Icon(icons[i], size: 30), label: labels[i]),
        ],
      ),
    );
  }
}
