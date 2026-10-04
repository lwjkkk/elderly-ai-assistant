import 'package:flutter/material.dart';
import '../../afu/afu_theme.dart';
import '../../afu/afu_widgets.dart';
import '../../services/api.dart';
import 'consult_drug_chat_tab.dart';
import 'meds_tab.dart';
import 'vitals_tab.dart';
import 'hub_pages.dart';
import '../bind_page.dart';
class HealthOverviewTab extends StatefulWidget {
  final String role;
  const HealthOverviewTab({super.key, this.role = 'elder'});
  @override
  State<HealthOverviewTab> createState() => _HealthOverviewTabState();
}

class _HealthOverviewTabState extends State<HealthOverviewTab> {
  int mod = 0;

  @override
  Widget build(BuildContext context) {
    final isElder = widget.role != 'family';
    final names = ['\u603b\u89c8', '\u4f53\u5f81', '\u62a5\u544a', '\u7528\u836f'];
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: const Color(0xFFDCE6F7)),
          ),
          child: Row(children: [
            for (var i = 0; i < names.length; i++)
              Expanded(
                child: AfuPressable(
                  onTap: () => setState(() => mod = i),
                  borderRadius: 22,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    decoration: BoxDecoration(
                      color: mod == i ? AfuColors.primaryDeep : Colors.transparent,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Text(names[i],
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: mod == i ? Colors.white : const Color(0xFF222222))),
                  ),
                ),
              ),
          ]),
        ),
      ),
      Expanded(
        child: IndexedStack(
          index: mod,
          children: [
            if (isElder) _ElderDigest(onModule: (i) => setState(() => mod = i)) else const _FamilyDigest(),
            if (isElder) const VitalsTab() else const _FamVitals(),
            if (isElder) const ReportTab() else const _FamReports(),
            if (isElder) const MedsTab() else const MedsTab(readOnly: true),
          ],
        ),
      ),
    ]);
  }
}
class _ElderDigest extends StatelessWidget {
  final void Function(int) onModule;
  const _ElderDigest({super.key, required this.onModule});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      children: [
        AfuCard(
          child: Row(children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(color: Color(0xFFE6F4EA), shape: BoxShape.circle),
              child: const Icon(Icons.family_restroom_outlined, size: 30, color: Color(0xFF2E7D4F)),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('\u5bb6\u5c5e\u5df2\u7ed1\u5b9a\uff0c\u5065\u5eb7\u8bb0\u5f55\u53ef\u4e00\u952e\u5206\u4eab\u7ed9\u5bb6\u4eba',
                  style: TextStyle(fontSize: 19, color: Color(0xFF222222), height: 1.5)),
            ),
            const SizedBox(width: 10),
            ElevatedButton(
              onPressed: () => HubNav.go(2),
              child: const Text('\u5206\u4eab\u8bb0\u5f55'),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 1.6,
          children: [
            _mod(context, Icons.search_outlined, '\u67e5\u836f', -3, const Color(0xFFE8EFFD), AfuColors.primaryDeep),
            _mod(context, Icons.medication_outlined, '\u7528\u836f', 3, const Color(0xFFE6F4EA), const Color(0xFF2E7D4F)),
            _mod(context, Icons.show_chart_outlined, '\u4f53\u5f81', 1, const Color(0xFFEFEAFA), const Color(0xFF7A63B8)),
            _mod(context, Icons.speed_outlined, '\u81ea\u67e5', -1, const Color(0xFFFFF3E2), const Color(0xFFB07A2A)),
            _mod(context, Icons.description_outlined, '\u62a5\u544a', 2, const Color(0xFFE8F4F4), const Color(0xFF2A7F7F)),
            _mod(context, Icons.chat_bubble_outline, '\u54a8\u8be2', -2, const Color(0xFFFDECEC), const Color(0xFFB3261E)),
          ],
        ),
        const SizedBox(height: 16),
        AfuCard(
          child: Row(children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(color: Color(0xFFFFF3E2), shape: BoxShape.circle),
              child: const Icon(Icons.lightbulb_outline, size: 30, color: Color(0xFFB07A2A)),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('\u5065\u5eb7\u5c0f\u8d34\u58eb\uff1a\u6309\u65f6\u5403\u836f\uff0c\u8eab\u4f53\u66f4\u597d',
                  style: TextStyle(fontSize: 19, color: Color(0xFF222222), height: 1.5)),
            ),
          ]),
        ),
      ],
    );
  }

  Widget _mod(BuildContext context, IconData icon, String title, int seg, Color tint, Color main) {
    return AfuPressable(
      onTap: () {
        if (seg >= 0) {
          onModule(seg);
          return;
        }
        Widget page = const SymptomTab();
        
        if (seg == -2) {
          page = const ConsultsTab();
        }
        if (seg == -3) {
          page = const DrugQueryTab();
        }
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => AfuSubPage(title: title, child: page)));
      },
      borderRadius: 20,
      child: AfuCard(
        child: Row(children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
            child: Icon(icon, size: 28, color: main),
          ),
          const SizedBox(width: 10),
          Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFF222222))),
        ]),
      ),
    );
  }
}
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

class _FamilyDigest extends StatefulWidget {
  const _FamilyDigest();
  @override
  State<_FamilyDigest> createState() => _FamilyDigestState();
}

class _FamilyDigestState extends State<_FamilyDigest> {
  String mineMeds = '...';
  String elderMeds = '...';
  String mineBp = '...';
  String elderBp = '...';

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
          mineMeds = '\u6682\u65e0\u6570\u636e';
          elderMeds = '\u6682\u65e0\u6570\u636e';
        });
      }
    }
    try {
      final mb = await ApiService.vitalsTrend(vitalType: 'bp', days: 7, mine: true);
      final eb = await ApiService.vitalsTrend(vitalType: 'bp', days: 7);
      if (mounted) {
        setState(() {
          mineBp = _bpLine(mb);
          elderBp = _bpLine(eb);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          mineBp = '\u6682\u65e0\u6570\u636e';
          elderBp = '\u6682\u65e0\u6570\u636e';
        });
      }
    }
  }

  String _medLine(List meds) {
    var total = 0, taken = 0;
    for (final m in meds) {
      final map = m is Map ? Map<String, dynamic>.from(m as Map) : <String, dynamic>{};
      final slots = map['slots'] is List ? List.from(map['slots']) : [];
      for (final s in slots) {
        total++;
        final sm = s is Map ? Map<String, dynamic>.from(s as Map) : <String, dynamic>{};
        if ((sm['status'] ?? '').toString() == 'taken') taken++;
      }
    }
    if (total == 0) return '\u4eca\u65e5\u6682\u65e0\u7528\u836f\u5b89\u6392';
    return '\u4eca\u65e5\u5df2\u6253\u5361 ' + taken.toString() + ' / ' + total.toString() + ' \u6b21';
  }

  String _bpLine(List trend) {
    if (trend.isEmpty) return '\u6682\u65e0\u8840\u538b\u8bb0\u5f55';
    try {
      final m = Map<String, dynamic>.from(trend.last as Map);
      final s = (m['systolic'] ?? m['value'] ?? '--').toString();
      final d = (m['diastolic'] ?? '').toString();
      return '\u6700\u8fd1\u4e00\u6b21 ' + s + (d.isEmpty ? '' : '/' + d);
    } catch (_) {
      return '\u6700\u8fd1\u6709\u8840\u538b\u8bb0\u5f55';
    }
  }
  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      color: AfuColors.primaryDeep,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        children: [
          _personCard(
            context,
            title: '\u6211\u7684\u5065\u5eb7',
            icon: Icons.person_outline,
            tint: const Color(0xFFE8EFFD),
            main: AfuColors.primaryDeep,
            lines: ['\u7528\u836f\uff1a' + mineMeds, '\u8840\u538b\uff1a' + mineBp],
          ),
          const SizedBox(height: 16),
          _personCard(
            context,
            title: '\u957f\u8f88\u5065\u5eb7',
            icon: Icons.family_restroom_outlined,
            tint: const Color(0xFFEFEAFA),
            main: const Color(0xFF7A63B8),
            lines: ['\u7528\u836f\uff1a' + elderMeds, '\u8840\u538b\uff1a' + elderBp],
          ),
        ],
      ),
    );
  }
  void _open(BuildContext context, String title, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => FamSubPage(title: title, child: page)));
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
            decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
            child: Icon(icon, size: 30, color: main),
          ),
          const SizedBox(width: 12),
          Text(title, style: AfuElderText.body.copyWith(fontWeight: FontWeight.w700)),
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
                        style: const TextStyle(fontSize: 19, color: Color(0xFF222222), height: 1.5)),
                  ),
              ]),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 10, runSpacing: 10, children: [
          _quick(context, Icons.medication_outlined, '\u7528\u836f\u8be6\u60c5', tint, main, const MedsTab(readOnly: true)),
          _quick(context, Icons.speed_outlined, '\u75c7\u72b6\u81ea\u67e5', tint, main, const SymptomTab()),
          _quick(context, Icons.group_outlined, '\u4eb2\u5c5e\u7ed1\u5b9a\u7ba1\u7406', tint, main, const BindPage(role: 'family')),
        ]),
      ]),
    );
  }
  Widget _quick(BuildContext context, IconData icon, String text, Color tint, Color main, Widget page) {
    return AfuPressable(
      onTap: () => _open(context, text, page),
      borderRadius: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(16)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 24, color: main),
          const SizedBox(width: 6),
          Text(text, style: TextStyle(fontSize: 18, color: main, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }
}

class _FamVitals extends StatefulWidget {
  const _FamVitals();
  @override
  State<_FamVitals> createState() => _FamVitalsState();
}

class _FamVitalsState extends State<_FamVitals> {
  bool mine = true;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      children: [
        _seg(['\u6211\u7684\u4f53\u5f81', '\u957f\u8f88\u4f53\u5f81']),
        const SizedBox(height: 16),
        AfuCard(
          padding: const EdgeInsets.all(8),
          child: SizedBox(
            height: 560,
            child: VitalsTab(key: ValueKey(mine), readOnly: !mine, mine: mine),
          ),
        ),
      ],
    );
  }

  Widget _seg(List<String> names) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFDCE6F7)),
      ),
      child: Row(children: [
        for (var i = 0; i < names.length; i++)
          Expanded(
            child: AfuPressable(
              onTap: () => setState(() => mine = i == 0),
              borderRadius: 22,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  color: mine == (i == 0) ? AfuColors.primaryDeep : Colors.transparent,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Text(names[i],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: mine == (i == 0) ? Colors.white : const Color(0xFF555555))),
              ),
            ),
          ),
      ]),
    );
  }
}
class _FamReports extends StatefulWidget {
  const _FamReports();
  @override
  State<_FamReports> createState() => _FamReportsState();
}

class _FamReportsState extends State<_FamReports> {
  bool mine = true;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: const Color(0xFFDCE6F7)),
          ),
          child: Row(children: [
            for (final e in ['\u6211\u7684\u62a5\u544a', '\u957f\u8f88\u62a5\u544a'])
              Expanded(
                child: AfuPressable(
                  onTap: () => setState(() => mine = e.startsWith('\u6211')),
                  borderRadius: 22,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    decoration: BoxDecoration(
                      color: mine == e.startsWith('\u6211') ? AfuColors.primaryDeep : Colors.transparent,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Text(e,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: mine == e.startsWith('\u6211') ? Colors.white : const Color(0xFF555555))),
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
            child: ReportTab(key: ValueKey(mine), mine: mine),
          ),
        ),
      ],
    );
  }
}
