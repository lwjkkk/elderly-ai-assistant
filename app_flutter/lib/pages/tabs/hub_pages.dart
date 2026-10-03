import 'package:flutter/material.dart';

import '../../afu/afu_theme.dart';
import '../../afu/afu_widgets.dart';
import '../../afu/afu_chat_page.dart' show AfuMessage, AfuBubble;
import '../../services/api.dart';
import 'consult_drug_chat_tab.dart';
import 'meds_tab.dart';
import 'vitals_tab.dart';
import 'me_tab.dart';

/// 跨 Tab 跳转总线：问事页快捷入口调用 HubNav.go(1, 'drugs') 即切到健康百事并滚到对应板块。
class HubNav {
  static final tab = ValueNotifier<int>(0);
  static String? pendingSection;

  static void go(int index, [String? section]) {
    pendingSection = section;
    tab.value = index;
  }
}

/// 子页通用壳：标题栏 + 内容，统一由健康百事卡片跳入。
class AfuSubPage extends StatelessWidget {
  final String title;
  final Widget child;
  const AfuSubPage({super.key, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AfuColors.bg,
      appBar: AppBar(title: Text(title)),
      body: SafeArea(child: child),
    );
  }
}

class _HubItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget page;
  const _HubItem(this.title, this.subtitle, this.icon, this.page);
}

/// 健康百事：6 张大圆角功能卡 + 药品知识库 + 健康科普。
class HealthHubTab extends StatefulWidget {
  const HealthHubTab({super.key});
  @override
  State<HealthHubTab> createState() => _HealthHubTabState();
}

class _HealthHubTabState extends State<HealthHubTab> {
  final _scroll = ScrollController();
  final _drugsKey = GlobalKey();
  final _newsKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _consumePending());
  }

  @override
  void didUpdateWidget(HealthHubTab old) {
    super.didUpdateWidget(old);
    _consumePending();
  }

  void _consumePending() {
    final s = HubNav.pendingSection;
    if (s == null) return;
    HubNav.pendingSection = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = s == 'drugs' ? _drugsKey : _newsKey;
      final ctx = key.currentContext;
      if (ctx != null && mounted) {
        Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 400), alignment: 0.05);
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const items = [
      _HubItem('查药', '输药名或拍照识别', Icons.search, DrugQueryTab()),
      _HubItem('用药', '今日清单与打卡', Icons.medication, MedsTab()),
      _HubItem('体征', '血压血糖曲线', Icons.favorite, VitalsTab()),
      _HubItem('自查', '症状风险评估', Icons.health_and_safety, SymptomTab()),
      _HubItem('报告', '体检报告解读', Icons.description, ReportTab()),
      _HubItem('咨询', '问诊录音记录', Icons.mic, ConsultsTab()),
    ];
    return Scaffold(
      backgroundColor: AfuColors.bg,
      appBar: AppBar(title: const Text('健康百事')),
      body: SafeArea(
        child: ListView(
          controller: _scroll,
          padding: const EdgeInsets.all(AfuSpace.page),
          children: [
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: AfuSpace.gap,
                crossAxisSpacing: AfuSpace.gap,
                childAspectRatio: 1.15,
              ),
              itemCount: items.length,
              itemBuilder: (c, i) {
                final it = items[i];
                return AfuCard(
                  onTap: () =>
                      Navigator.of(context).push(afuFadeRoute(AfuSubPage(title: it.title, child: it.page))),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration:
                            const BoxDecoration(color: AfuColors.primarySoft, shape: BoxShape.circle),
                        child: Icon(it.icon, size: 34, color: AfuColors.primaryDeep),
                      ),
                      const SizedBox(height: 12),
                      Text(it.title, style: AfuElderText.body.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(it.subtitle, style: AfuElderText.secondary, textAlign: TextAlign.center),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: AfuSpace.section),
            _SectionTitle(key: _drugsKey, icon: Icons.menu_book, text: '药品知识库'),
            const SizedBox(height: 8),
            const _InfoCard(
                title: '感冒药怎么选',
                body: '风寒风热用药不同，多种感冒药别叠着吃，具体遵医嘱。'),
            const _InfoCard(
                title: '降压药服用提醒',
                body: '每天固定时间吃，不要血压正常就停药，定期复查。'),
            const _InfoCard(
                title: '维生素要补吗',
                body: '饮食均衡一般不缺，缺了再补，过量反而有害。'),
            const SizedBox(height: AfuSpace.section),
            _SectionTitle(key: _newsKey, icon: Icons.newspaper, text: '健康科普'),
            const SizedBox(height: 8),
            const _InfoCard(
                title: '秋冬防感冒',
                body: '早晚添衣、勤通风，流感季尽量少去人多的地方。'),
            const _InfoCard(
                title: '控盐小窍门',
                body: '每天盐别超一小勺，酱油蚝油也算盐。'),
            const _InfoCard(
                title: '睡个好觉',
                body: '固定时间睡，睡前少看手机，白天适当晒太阳。'),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('以上内容仅供参考，具体用药请遵医嘱', style: AfuElderText.secondary,
                  textAlign: TextAlign.center),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final String body;
  const _InfoCard({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AfuCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: AfuElderText.body.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(body, style: AfuElderText.secondary),
        ]),
      ),
    );
  }
}

/// 家人相伴：上半问答历史，下半家属联动，两类信息一眼区分。
class FamilyTab extends StatefulWidget {
  const FamilyTab({super.key});
  @override
  State<FamilyTab> createState() => _FamilyTabState();
}

class _FamilyTabState extends State<FamilyTab> {
  List binds = [];
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      binds = await ApiService.bindList();
    } catch (_) {
      binds = [];
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final history = ChatHistory.items;
    return Scaffold(
      backgroundColor: AfuColors.bg,
      appBar: AppBar(title: const Text('家人相伴')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(AfuSpace.page),
            children: [
              const _SectionTitle(icon: Icons.chat_bubble, text: '我的问答'),
              const SizedBox(height: 8),
              if (history.isEmpty)
                const AfuCard(child: Text('还没有提问，去问事页问第一句吧', style: AfuElderText.secondary))
              else
                ...history.take(3).map((m) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: AfuBubble(text: m.text, isMe: m.isMe),
                    )),
              const SizedBox(height: AfuSpace.section),
              const _SectionTitle(icon: Icons.family_restroom, text: '家属联动'),
              const SizedBox(height: 4),
              const Text('以下来自子女家人的关联信息', style: AfuElderText.secondary),
              const SizedBox(height: 8),
              if (binds.isEmpty)
                const AfuCard(child: Text('还没有绑定家人，去设置页生成邀请码', style: AfuElderText.secondary))
              else
                ...binds.map((b) {
                  final m = b is Map ? Map<String, dynamic>.from(b as Map) : <String, dynamic>{};
                  final name = (m['other_nickname'] ?? m['nickname'] ?? '家人').toString();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AfuCard(
                      child: Row(children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: const BoxDecoration(color: AfuColors.primarySoft, shape: BoxShape.circle),
                          child: const Icon(Icons.person, size: 32, color: AfuColors.primaryDeep),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(name, style: AfuElderText.body.copyWith(fontWeight: FontWeight.w700)),
                            const Text('已绑定，可互看健康记录', style: AfuElderText.secondary),
                          ]),
                        ),
                      ]),
                    ),
                  );
                }),
              const _LinkRow(icon: Icons.message, title: '家属留言', subtitle: '暂无新留言'),
              const _LinkRow(icon: Icons.notifications, title: '共享提醒', subtitle: '用药与复诊提醒同步中'),
              const _LinkRow(icon: Icons.sync, title: '用药同步', subtitle: '家属可查看打卡情况'),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String text;
  const _SectionTitle({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(
        width: 44,
        height: 44,
        decoration: const BoxDecoration(color: AfuColors.primarySoft, shape: BoxShape.circle),
        child: Icon(icon, size: 26, color: AfuColors.primaryDeep),
      ),
      const SizedBox(width: 10),
      Text(text, style: AfuElderText.appTitle.copyWith(fontSize: 22)),
    ]);
  }
}

class _LinkRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  const _LinkRow({required this.icon, required this.title, required this.subtitle, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AfuCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Row(children: [
          Icon(icon, size: 32, color: AfuColors.primaryDeep),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: AfuElderText.body.copyWith(fontWeight: FontWeight.w700)),
              Text(subtitle, style: AfuElderText.secondary),
            ]),
          ),
          const Icon(Icons.chevron_right, color: AfuColors.secondary, size: 30),
        ]),
      ),
    );
  }
}

/// 设置页：沿用我的页内容（邀请码、绑定列表、退出）。
class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AfuColors.bg,
      appBar: AppBar(title: const Text('设置')),
      body: const SafeArea(child: MeTab(role: 'elder')),
    );
  }
}
