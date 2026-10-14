import 'package:flutter/material.dart';
import '../afu/afu_theme.dart';
import 'tabs/consult_drug_chat_tab.dart';
import 'tabs/hub_pages.dart';
import 'tabs/meds_tab.dart';

/// 长辈端 4 Tab：用药提醒 / AI问事 / 家人互动 / 个人中心。
/// 说明：已移除「健康总览」Tab，用药功能独立成 Tab，不再嵌入 AI问事 页面。
class ElderHome extends StatefulWidget {
  const ElderHome({super.key});
  @override
  State<ElderHome> createState() => _ElderHomeState();
}

class _ElderHomeState extends State<ElderHome> {
  int idx = 1; // 默认 AI问事

  @override
  void initState() {
    super.initState();
    HubNav.tab.addListener(_onHubTab);
    HubNav.request.addListener(_onHubTab);
  }

  @override
  void dispose() {
    HubNav.tab.removeListener(_onHubTab);
    HubNav.request.removeListener(_onHubTab);
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
      MedsTab(), // 0 用药提醒
      ChatTab(), // 1 AI问事
      FamilyTab(), // 2 家人互动
      SettingsTab(), // 3 个人中心
    ];
    const labels = ['\u7528\u836f\u63d0\u9192', 'AI\u95ee\u4e8b', '\u5bb6\u4eba\u4e92\u52a8', '\u4e2a\u4eba\u4e2d\u5fc3'];
    const icons = [Icons.alarm_outlined, Icons.chat_bubble_outline, Icons.family_restroom_outlined, Icons.person_outline];
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFD),
      body: SafeArea(key: ValueKey(idx), child: pages[idx]),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: idx,
        type: BottomNavigationBarType.fixed,
        selectedFontSize: 15,
        unselectedFontSize: 14,
        selectedItemColor: const Color(0xFF345C87),
        unselectedItemColor: const Color(0xFF6B7280),
        onTap: (i) => setState(() => idx = (i == 1 && idx == 1) ? 0 : i),
        items: [
          for (var i = 0; i < labels.length; i++)
            BottomNavigationBarItem(icon: Icon(icons[i], size: 30), label: labels[i]),
        ],
      ),
    );
  }
}
