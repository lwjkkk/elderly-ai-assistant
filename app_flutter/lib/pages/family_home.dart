import 'package:flutter/material.dart';

import '../afu/afu_theme.dart';
import '../afu/afu_widgets.dart';
import '../services/api.dart';
import 'tabs/consult_drug_chat_tab.dart' show SymptomTab, ReportTab, ChatTab;
import 'tabs/meds_tab.dart';
import 'tabs/vitals_tab.dart';
 
import 'login_page.dart';
import 'bind_page.dart';

/// 家属端 4Tab：健康总览 / 体征 / 报告 / 我的（阿福风统一视觉）。
class FamilyHome extends StatefulWidget {
  const FamilyHome({super.key});
  @override
  State<FamilyHome> createState() => _FamilyHomeState();
}

class _FamilyHomeState extends State<FamilyHome> {
  int idx = 0;

  @override
  Widget build(BuildContext context) {
    const titles = ['健康总览', '体征', '报告', '我的'];
    const pages = [
      FamOverview(),
      FamVitals(),
      FamReports(),
      FamMe(),
    ];
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FD),
      appBar: AppBar(
        title: Text(titles[idx]),
        backgroundColor: const Color(0xFFF7F9FD),
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(key: ValueKey(idx), child: pages[idx]),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: idx,
        type: BottomNavigationBarType.fixed,
        selectedFontSize: 16,
        unselectedFontSize: 16,
        selectedItemColor: AfuColors.primaryDeep,
        unselectedItemColor: AfuColors.secondary,
        onTap: (i) => setState(() => idx = i),
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_outlined, size: 30),
              activeIcon: Icon(Icons.dashboard, size: 30),
              label: '健康总览'),
          BottomNavigationBarItem(
              icon: Icon(Icons.show_chart_outlined, size: 30),
              activeIcon: Icon(Icons.show_chart, size: 30),
              label: '体征'),
          BottomNavigationBarItem(
              icon: Icon(Icons.description_outlined, size: 30),
              activeIcon: Icon(Icons.description, size: 30),
              label: '报告'),
          BottomNavigationBarItem(
              icon: Icon(Icons.person_outline, size: 30),
              activeIcon: Icon(Icons.person, size: 30),
              label: '我的'),
        ],
      ),
    );
  }
}

/// 子页壳：标题栏 + 内容，健康总览快捷入口跳入。
class FamSubPage extends StatelessWidget {
  final String title;
  final Widget child;
  const FamSubPage({super.key, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FD),
      appBar: AppBar(
        title: Text(title),
        backgroundColor: const Color(0xFFF7F9FD),
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(child: child),
    );
  }
}

/// 1) 健康总览：我的健康 / 长辈健康两张隔离卡 + 快捷入口。
class FamOverview extends StatefulWidget {
  const FamOverview({super.key});
  @override
  State<FamOverview> createState() => _FamOverviewState();
}

class _FamOverviewState extends State<FamOverview> {
  String mineMeds = '加载中…';
  String elderMeds = '加载中…';
  String mineBp = '加载中…';
  String elderBp = '加载中…';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final mm = await ApiService.medsToday(mine: true);
      final em = await ApiService.medsToday();
      if (mounted) {
        setState(() {
          mineMeds = _medLine(mm);
          elderMeds = _medLine(em);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          mineMeds = '暂无数据';
          elderMeds = '暂无数据';
        });
      }
    }
    try {
      final mb = await ApiService.vitalsTrend(
          vitalType: 'bp', days: 7, mine: true);
      final eb =
          await ApiService.vitalsTrend(vitalType: 'bp', days: 7);
      if (mounted) {
        setState(() {
          mineBp = _bpLine(mb);
          elderBp = _bpLine(eb);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          mineBp = '暂无数据';
          elderBp = '暂无数据';
        });
      }
    }
  }

  String _medLine(List meds) {
    var total = 0, taken = 0;
    for (final m in meds) {
      final map = m is Map
          ? Map<String, dynamic>.from(m as Map)
          : <String, dynamic>{};
      final slots =
          map['slots'] is List ? List.from(map['slots']) : [];
      for (final s in slots) {
        total++;
        final sm = s is Map
            ? Map<String, dynamic>.from(s as Map)
            : <String, dynamic>{};
        if ((sm['status'] ?? '').toString() == 'taken') taken++;
      }
    }
    if (total == 0) return '今日暂无用药安排';
    return '今日已打卡 $taken / $total 次';
  }

  String _bpLine(List trend) {
    if (trend.isEmpty) return '暂无血压记录';
    try {
      final m = Map<String, dynamic>.from(trend.last as Map);
      final s = (m['systolic'] ?? m['value'] ?? '--').toString();
      final d = (m['diastolic'] ?? '').toString();
      return d.isEmpty ? '最近一次 $s' : '最近一次 $s/$d';
    } catch (_) {
      return '最近有血压记录';
    }
  }

  void _open(BuildContext context, String title, Widget page) {
    Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => FamSubPage(title: title, child: page)));
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      color: AfuColors.primaryDeep,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _personCard(
            context,
            title: '我的健康',
            icon: Icons.person_outline,
            tint: const Color(0xFFE8EFFD),
            main: AfuColors.primaryDeep,
            lines: ['用药：$mineMeds', '血压：$mineBp'],
          ),
          Center(
            child: AfuPressable(
              onTap: () => _open(context, '问事问事',
                  const ChatTab()),
              borderRadius: 60,
              child: Column(children: [
                Container(
                  width: 104,
                  height: 104,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AfuColors.primary,
                    boxShadow: [
                      BoxShadow(color: AfuColors.primary.withOpacity(0.30), blurRadius: 18, offset: const Offset(0, 6)),
                    ],
                  ),
                  child: const Icon(Icons.smart_toy_outlined, size: 52, color: Colors.white),
                ),
                const SizedBox(height: 8),
                Text('智能问事', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFF222222))),
              ]),
            ),
          ),
          const SizedBox(height: 16),
const SizedBox(height: 16),
          _personCard(
            context,
            title: '长辈健康',
            icon: Icons.family_restroom_outlined,
            tint: const Color(0xFFEFEAFA),
            main: const Color(0xFF7A63B8),
            lines: ['用药：$elderMeds', '血压：$elderBp'],
          ),
        ],
      ),
    );
  }

  Widget _personCard(BuildContext context,
      {required String title,
      required IconData icon,
      required Color tint,
      required Color main,
      required List<String> lines}) {
    return AfuCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 56,
            height: 56,
            decoration:
                BoxDecoration(color: tint, shape: BoxShape.circle),
            child: Icon(icon, size: 30, color: main),
          ),
          const SizedBox(width: 12),
          Text(title,
              style:
                  AfuElderText.body.copyWith(fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: main.withOpacity(0.10),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final line in lines)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(line,
                        style: const TextStyle(
                            fontSize: 19,
                            color: Color(0xFF222222),
                            height: 1.5)),
                  ),
              ]),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 10, runSpacing: 10, children: [
          _quick(context, Icons.medication_outlined, '用药详情', tint,
              main, const MedsTab(readOnly: true)),
          _quick(context, Icons.speed_outlined, '症状自查', tint, main,
              const SymptomTab()),
          _quick(context, Icons.group_outlined, '亲属绑定管理', tint,
              main, const BindPage(role: 'family')),
        ]),
      ]),
    );
  }

  Widget _quick(BuildContext context, IconData icon, String text,
      Color tint, Color main, Widget page) {
    return AfuPressable(
      onTap: () => _open(context, text, page),
      borderRadius: 16,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(
          color: tint,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 24, color: main),
          const SizedBox(width: 6),
          Text(text,
              style: TextStyle(
                  fontSize: 18, color: main, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }
}

/// 2) 体征：我的 / 长辈切换，封装白卡。
class FamVitals extends StatefulWidget {
  const FamVitals({super.key});
  @override
  State<FamVitals> createState() => _FamVitalsState();
}

class _FamVitalsState extends State<FamVitals> {
  bool mine = true;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: const Color(0xFFDCE6F7)),
          ),
          child: Row(children: [
            for (final e in [(true, '我的体征'), (false, '长辈体征')])
              Expanded(
                child: AfuPressable(
                  onTap: () => setState(() => mine = e.$1),
                  borderRadius: 22,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(vertical: 13),
                    decoration: BoxDecoration(
                      color: mine == e.$1
                          ? AfuColors.primaryDeep
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Text(e.$2,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: mine == e.$1
                                ? Colors.white
                                : const Color(0xFF555555))),
                  ),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 16),
        AfuCard(
          padding: const EdgeInsets.all(8),
          child: SizedBox(
            height: 560,
            child: VitalsTab(
                key: ValueKey(mine), readOnly: !mine, mine: mine),
          ),
        ),
      ],
    );
  }
}

/// 3) 报告：我的 / 长辈切换。
class FamReports extends StatefulWidget {
  const FamReports({super.key});
  @override
  State<FamReports> createState() => _FamReportsState();
}

class _FamReportsState extends State<FamReports> {
  bool mine = true;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: const Color(0xFFDCE6F7)),
          ),
          child: Row(children: [
            for (final e in [(true, '我的报告'), (false, '长辈报告')])
              Expanded(
                child: AfuPressable(
                  onTap: () => setState(() => mine = e.$1),
                  borderRadius: 22,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(vertical: 13),
                    decoration: BoxDecoration(
                      color: mine == e.$1
                          ? AfuColors.primaryDeep
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Text(e.$2,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: mine == e.$1
                                ? Colors.white
                                : const Color(0xFF555555))),
                  ),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 16),
        AfuCard(
          padding: const EdgeInsets.all(8),
          child: SizedBox(
            height: 560,
            child:
                ReportTab(key: ValueKey(mine), mine: mine),
          ),
        ),
      ],
    );
  }
}

/// 4) Me page: profile + bind management + logout.
class FamMe extends StatefulWidget {
  const FamMe({super.key});
  @override
  State<FamMe> createState() => _FamMeState();
}

class _FamMeState extends State<FamMe> {
  String nickname = '\u5bb6\u5c5e';
  List binds = [];
  final codeC = TextEditingController();
  String msg = '';
  bool binding = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    codeC.dispose();
    super.dispose();
  }

  bool get bound => binds.any((b) {
    final m = b is Map ? Map<String, dynamic>.from(b as Map) : <String, dynamic>{};
    return (m['status'] ?? '').toString() == 'active';
  });

  Future<void> _load() async {
    try {
      nickname = await ApiService.getNickname() ?? '\u5bb6\u5c5e';
      binds = await ApiService.bindList();
    } catch (_) {
      binds = [];
    }
    if (mounted) setState(() {});
  }

  Future<void> _doBind() async {
    final c = codeC.text.trim();
    if (c.isEmpty) {
      setState(() => msg = '\u5148\u8f93\u5165\u9080\u8bf7\u7801');
      return;
    }
    setState(() { binding = true; msg = ''; });
    try {
      await ApiService.acceptInvite(c);
      codeC.clear();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('\u7ed1\u5b9a\u6210\u529f')));
      }
    } catch (e) {
      if (mounted) setState(() => msg = ApiService.friendly(e));
    }
    if (mounted) setState(() => binding = false);
  }

  Future<void> _logout() async {
    await ApiService.clearAuth();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginPage()), (r) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      color: AfuColors.primaryDeep,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _profileCard(),
          if (!bound) ...[
            const SizedBox(height: 16),
            _bindCard(),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _logout,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFA8BFE4), width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text('\u9000\u51fa\u767b\u5f55', style: TextStyle(fontSize: 20)),
            ),
          ),
          if (bound) ...[
            const SizedBox(height: 16),
            _bindCard(),
          ],
        ],
      ),
    );
  }

  Widget _profileCard() {
    return AfuCard(
      child: Row(children: [
        Container(
          width: 76,
          height: 76,
          decoration: const BoxDecoration(color: Color(0xFFEBF1FB), shape: BoxShape.circle),
          child: const Icon(Icons.person, size: 44, color: AfuColors.primaryDeep),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(nickname, style: AfuElderText.body.copyWith(fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }

  Widget _bindCard() {
    return AfuCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('\u4eb2\u5c5e\u7ed1\u5b9a\u7ba1\u7406', style: AfuElderText.body.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        const Text('\u8f93\u5165\u9080\u8bf7\u7801\u53ef\u7ed1\u5b9a\u957f\u8f88', style: AfuElderText.secondary),
        const SizedBox(height: 12),
        TextField(
          controller: codeC,
          style: const TextStyle(fontSize: 21, color: Color(0xFF222222)),
          decoration: InputDecoration(
            hintText: '\u8bf7\u8f93\u51656\u4f4d\u9080\u8bf7\u7801',
            hintStyle: const TextStyle(fontSize: 19, color: Color(0xFF6B7686)),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 19),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(22),
              borderSide: const BorderSide(color: Color(0xFFDCE6F7)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(22),
              borderSide: const BorderSide(color: Color(0xFFDCE6F7)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(22),
              borderSide: const BorderSide(color: AfuColors.primary, width: 2),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: binding ? null : _doBind,
            child: Text(binding ? '\u7ed1\u5b9a\u4e2d\u2026' : '\u786e\u8ba4\u7ed1\u5b9a'),
          ),
        ),
        if (msg.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(msg, style: const TextStyle(fontSize: 18, color: Color(0xFFB3261E))),
        ],
        const SizedBox(height: 12),
        if (binds.isEmpty)
          const Text('\u6682\u65e0\u7ed1\u5b9a', style: AfuElderText.secondary)
        else
          for (final b in binds) _bindRow(b),
      ]),
    );
  }

  Widget _bindRow(dynamic b) {
    final m = b is Map ? Map<String, dynamic>.from(b as Map) : <String, dynamic>{};
    final name = (m['other_nickname'] ?? m['nickname'] ?? '对方').toString();
    final status = (m['status'] ?? '').toString();
    final code = (m['invite_code'] ?? '').toString();
    final active = status == 'active';
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FD),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(children: [
        Container(
          width: 52,
          height: 52,
          decoration: const BoxDecoration(color: Color(0xFFEBF1FB), shape: BoxShape.circle),
          child: const Icon(Icons.person, size: 30, color: AfuColors.primaryDeep),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: AfuElderText.body.copyWith(fontWeight: FontWeight.w700)),
            if (code.isNotEmpty)
              Text('\u9080\u8bf7\u7801 ' + code, style: AfuElderText.secondary.copyWith(fontSize: 16)),
          ]),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: active ? const Color(0xFFE6F4EA) : const Color(0xFFF0F1F5),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(active ? '\u5df2\u7ed1\u5b9a' : status,
              style: TextStyle(
                  fontSize: 17,
                  color: active ? const Color(0xFF2E7D4F) : const Color(0xFF5A6472))),
        ),
      ]),
    );
  }
}
