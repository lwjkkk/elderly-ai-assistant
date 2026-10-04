import 'package:flutter/material.dart';
import '../../afu/afu_theme.dart';
import '../../afu/afu_widgets.dart';
import '../../services/api.dart';
import 'consult_drug_chat_tab.dart';
import 'meds_tab.dart';
import 'vitals_tab.dart';
import 'hub_pages.dart';
class HealthOverviewTab extends StatefulWidget {
  final String role;
  const HealthOverviewTab({super.key, this.role = 'elder'});
  @override
  State<HealthOverviewTab> createState() => _HealthOverviewTabState();
}


class _HealthOverviewTabState extends State<HealthOverviewTab> {
  // 当前展示的健康模块：0总览卡片 1体征 2报告 3用药。
  // 顶部横排标签已移除，改由下方功能卡片点击切换。
  int mod = 0;
  // 家属端身份切换：true=看绑定长辈（自动同步），false=看本人（手动上传）。
  bool showElder = true;

  @override
  Widget build(BuildContext context) {
    // 数据来源：长辈端 mine=true（自己的记录，含后端从 AI 对话自动总结的数据）；
    // 家属端看长辈 mine=false（ApiService 自动带 elder_id 拉取）；
    // 家属端看本人 mine=true（手动上传模式）。
    // 注意：家属本人模式后端暂无独立存储，列表接口可能返回空或报错，属后端能力限制。
    final mine = widget.role != 'family' || !showElder;
    return Expanded(
      child: Column(children: [
        // 家属端身份切换：本人 / 绑定长辈
        if (widget.role == 'family') _roleSwitch(),
        // 子页面返回栏：点卡片进入子模块后，可一键返回健康总览主页
        if (mod != 0) _backBar(),
        Expanded(
          child: IndexedStack(
            index: mod,
            key: ValueKey('hub-$mine-$mod'),
            children: [
              _ElderDigest(onModule: (i) => setState(() => mod = i), mine: mine),
              VitalsTab(key: ValueKey('v-$mine'), mine: mine),
              ReportTab(key: ValueKey('r-$mine'), mine: mine),
              MedsTab(key: ValueKey('m-$mine'), readOnly: !mine, mine: mine),
            ],
          ),
        ),
      ]),
    );
  }

  /// 身份切换栏：本人 / 绑定长辈（仅家属端展示）。
  Widget _roleSwitch() {
    Widget seg(String label, bool active, VoidCallback onTap) {
      return Expanded(
        child: AfuPressable(
          onTap: onTap,
          borderRadius: 18,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 13),
            decoration: BoxDecoration(
              color: active
                  ? AfuColors.primaryDeep
                  : const Color(0xFFF2F6FD),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: active ? Colors.white : const Color(0xFF222222),
                )),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Row(children: [
        seg('本人', !showElder, () => setState(() => showElder = false)),
        const SizedBox(width: 12),
        seg('绑定长辈', showElder, () => setState(() => showElder = true)),
      ]),
    );
  }

  /// 子页面返回栏：返回健康总览主页。
  Widget _backBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: AfuPressable(
        onTap: () => setState(() => mod = 0),
        borderRadius: 16,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFDCE6F7)),
          ),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.arrow_back, size: 26, color: Color(0xFF222222)),
            SizedBox(width: 8),
            Text('返回健康总览',
                style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF222222))),
          ]),
        ),
      ),
    );
  }
}

/// 总览页主体：6 张正方形功能卡 + 今日小贴士。家属端原样复用此页。
class _ElderDigest extends StatelessWidget {
  final void Function(int) onModule;
  final bool mine;
  const _ElderDigest({super.key, required this.onModule, this.mine = true});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      children: [
        // 顶部提示卡：与现有卡片风格统一
        AfuCard(
          child: Row(children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                  color: Color(0xFFE8EFFD), shape: BoxShape.circle),
              child: const Icon(Icons.info_outline,
                  size: 30, color: AfuColors.primaryDeep),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('可查看本人或已绑定长辈的健康记录；长辈数据自动同步，本人记录需手动上传',
                  style: TextStyle(
                      fontSize: 19, color: Color(0xFF222222), height: 1.5)),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        // 6 张正方形功能卡片：图标 + 主标题 + 小字副标题 + 底部简易装饰图形
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 1.0,
          children: [
            _mod(context, Icons.medication_outlined, '\u67e5\u836f', '\u836f\u54c1\u4fe1\u606f\u67e5\u8be2', -3,
                const Color(0xFFE8EFFD), AfuColors.primaryDeep, 'drug'),
            _mod(context, Icons.alarm_outlined, '\u7528\u836f', '\u7528\u836f\u63d0\u9192\u7ba1\u7406', 3,
                const Color(0xFFE6F4EA), const Color(0xFF2E7D4F), 'med'),
            _mod(context, Icons.show_chart_outlined, '\u4f53\u5f81', '\u4f53\u5f81\u6570\u636e\u8bb0\u5f55', 1,
                const Color(0xFFEFEAFA), const Color(0xFF7A63B8), 'vitals'),
            _mod(context, Icons.speed_outlined, '\u81ea\u67e5', '\u5065\u5eb7\u81ea\u6d4b\u8bc4\u4f30', -1,
                const Color(0xFFFFF3E2), const Color(0xFFB07A2A), 'selfcheck'),
            _mod(context, Icons.description_outlined, '\u62a5\u544a', '\u4f53\u68c0\u62a5\u544a\u89e3\u8bfb', 2,
                const Color(0xFFE8F4F4), const Color(0xFF2A7F7F), 'report'),
            _mod(context, Icons.chat_bubble_outline, '\u54a8\u8be2', '\u5728\u7ebf\u95ee\u533b\u751f', -2,
                const Color(0xFFFDECEC), const Color(0xFFB3261E), 'chat'),
          ],
        ),
        const SizedBox(height: 16),
        // 健康小贴士：优先用药提醒，否则展示天气 + 穿衣建议
        const _HealthTip(),
      ],
    );
  }

  /// 单个功能卡片：柔和圆底图标 + 主标题 + 小字副标题 + 底部装饰图形。
  /// 装饰图形用 Expanded 占满剩余高度，解决正方形卡片底部留白过多的问题。
  Widget _mod(BuildContext context, IconData icon, String title, String subtitle,
      int seg, Color tint, Color main, String deco) {
    return AfuPressable(
      onTap: () {
        if (seg >= 0) {
          onModule(seg);
          return;
        }
        Widget page = SymptomTab(mine: mine);
        if (seg == -2) {
          page = ConsultsTab(mine: mine);
        }
        if (seg == -3) {
          // 查药为即时问答（后端不落库），本人/长辈视角一致，无需区分
          page = const DrugQueryTab();
        }
        Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => AfuSubPage(title: title, child: page)));
      },
      borderRadius: 22,
      child: AfuCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 左上角：图标 与 右侧两字功能标题
            Row(children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
                child: Icon(icon, size: 30, color: main),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF222222))),
              ),
            ]),
            const SizedBox(height: 8),
            // 标题下方：灰色小字功能说明
            Text(subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 16, color: Color(0xFF6B7686))),
            const SizedBox(height: 6),
            // 卡片下半部分：配套装饰图画填满，不留大面积空白
            Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 64),
                  child: _CardDeco(kind: deco, color: main),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 卡片底部的简易装饰图形底衬（浅色圆角方块 + 简笔图形）。
class _CardDeco extends StatelessWidget {
  final String kind;
  final Color color;
  const _CardDeco({required this.kind, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: CustomPaint(
        painter: _DecoPainter(kind, color.withOpacity(0.55)),
        size: Size.infinite,
      ),
    );
  }
}

/// 六种简笔装饰：查药(药盒+放大镜)、用药(闹钟+滑杆)、体征(折线)、
/// 自查(刻度盘)、报告(单据+对勾)、咨询(双气泡)。
class _DecoPainter extends CustomPainter {
  final String kind;
  final Color color;
  const _DecoPainter(this.kind, this.color);

  @override
  void paint(Canvas canvas, Size s) {
    if (s.isEmpty) return;
    final stroke = Paint()
      ..color = color
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    switch (kind) {
      case 'drug':
        // 左侧小药盒
        final box = RRect.fromRectAndRadius(
            Rect.fromLTWH(s.width * 0.03, s.height * 0.20, s.width * 0.34,
                s.height * 0.60),
            const Radius.circular(6));
        canvas.drawRRect(box, Paint()..color = color.withOpacity(0.35));
        canvas.drawRRect(box, stroke);
        // 右侧胶囊 + 放大镜
        final cap = RRect.fromRectAndRadius(
            Rect.fromLTWH(s.width * 0.46, s.height * 0.22, s.width * 0.50,
                s.height * 0.56),
            Radius.circular(s.height * 0.30));
        canvas.drawRRect(cap, stroke);
        canvas.drawCircle(
            Offset(s.width * 0.78, s.height * 0.46), s.height * 0.13, stroke);
        canvas.drawLine(Offset(s.width * 0.855, s.height * 0.585),
            Offset(s.width * 0.925, s.height * 0.70), stroke);
        break;
      case 'med':
        // 闹钟
        final c = Offset(s.width * 0.17, s.height * 0.52);
        canvas.drawCircle(c, s.height * 0.27, stroke);
        canvas.drawLine(c, Offset(c.dx, c.dy - s.height * 0.15), stroke);
        canvas.drawLine(c, Offset(c.dx + s.width * 0.07, c.dy), stroke);
        canvas.drawLine(Offset(c.dx - s.height * 0.19, c.dy - s.height * 0.30),
            Offset(c.dx - s.height * 0.05, c.dy - s.height * 0.22), stroke);
        // 滑杆 + 圆点
        final y = s.height * 0.58;
        canvas.drawLine(
            Offset(s.width * 0.44, y), Offset(s.width * 0.95, y), stroke);
        canvas.drawCircle(Offset(s.width * 0.64, y), s.height * 0.12, fill);
        break;
      case 'vitals':
        // 折线 + 数据点
        final pts = <Offset>[
          Offset(0, s.height * 0.62),
          Offset(s.width * 0.20, s.height * 0.44),
          Offset(s.width * 0.40, s.height * 0.30),
          Offset(s.width * 0.60, s.height * 0.52),
          Offset(s.width * 0.80, s.height * 0.34),
          Offset(s.width, s.height * 0.18),
        ];
        final path = Path()..moveTo(pts.first.dx, pts.first.dy);
        for (final o in pts.skip(1)) {
          path.lineTo(o.dx, o.dy);
        }
        canvas.drawPath(path, stroke);
        for (final o in pts) {
          canvas.drawCircle(o, 2.6, fill);
        }
        break;
      case 'selfcheck':
        // 刻度盘（半圆）+ 指针
        canvas.drawArc(
            Rect.fromLTWH(s.width * 0.14, s.height * 0.10, s.width * 0.72,
                s.height * 1.50),
            3.14159,
            3.14159,
            false,
            Paint()
              ..color = color
              ..strokeWidth = 4
              ..style = PaintingStyle.stroke
              ..strokeCap = StrokeCap.round);
        canvas.drawLine(Offset(s.width * 0.50, s.height * 0.86),
            Offset(s.width * 0.72, s.height * 0.38), stroke);
        canvas.drawCircle(Offset(s.width * 0.50, s.height * 0.86), 3.2, fill);
        break;
      case 'report':
        // 单据 + 右侧对勾
        final page = RRect.fromRectAndRadius(
            Rect.fromLTWH(s.width * 0.06, s.height * 0.10, s.width * 0.42,
                s.height * 0.80),
            const Radius.circular(6));
        canvas.drawRRect(page, stroke);
        for (var i = 0; i < 3; i++) {
          final y = s.height * (0.30 + i * 0.20);
          canvas.drawLine(Offset(s.width * 0.14, y),
              Offset(s.width * (0.40 - i * 0.06), y), stroke);
        }
        final cc = Offset(s.width * 0.75, s.height * 0.52);
        canvas.drawCircle(cc, s.height * 0.25, stroke);
        final tick = Path()
          ..moveTo(cc.dx - s.height * 0.13, cc.dy)
          ..lineTo(cc.dx - s.height * 0.03, cc.dy + s.height * 0.10)
          ..lineTo(cc.dx + s.height * 0.14, cc.dy - s.height * 0.11);
        canvas.drawPath(tick, stroke);
        break;
      case 'chat':
        // 两个对话气泡
        final b1 = RRect.fromRectAndRadius(
            Rect.fromLTWH(s.width * 0.04, s.height * 0.10, s.width * 0.56,
                s.height * 0.44),
            const Radius.circular(10));
        canvas.drawRRect(b1, stroke);
        for (var i = 0; i < 3; i++) {
          canvas.drawCircle(
              Offset(s.width * (0.20 + i * 0.13), s.height * 0.32), 2.2, fill);
        }
        final b2 = RRect.fromRectAndRadius(
            Rect.fromLTWH(s.width * 0.38, s.height * 0.48, s.width * 0.56,
                s.height * 0.42),
            const Radius.circular(10));
        canvas.drawRRect(b2, Paint()..color = color.withOpacity(0.18));
        canvas.drawRRect(b2, stroke);
        break;
      default:
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _DecoPainter old) =>
      old.kind != kind || old.color != color;
}

/// 健康小贴士：有用药提醒优先显示药名与时间；否则调用天气，展示温度与穿衣建议。
class _HealthTip extends StatefulWidget {
  const _HealthTip();
  @override
  State<_HealthTip> createState() => _HealthTipState();
}

class _HealthTipState extends State<_HealthTip> {
  String _line = '\u6b63\u5728\u67e5\u770b\u63d0\u9192\u2026';
  IconData _icon = Icons.lightbulb_outline;
  Color _color = const Color(0xFFB07A2A);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // 1) 优先：今日是否有用药提醒
    try {
      final meds = await ApiService.medsToday();
      final tip = _medsTip(meds);
      if (tip != null) {
        if (mounted) {
          setState(() {
            _line = tip;
            _icon = Icons.medication_outlined;
            _color = const Color(0xFF2E7D4F);
          });
        }
        return;
      }
    } catch (_) {}
    // 2) 无用药提醒 -> 调用天气，展示温度 + 穿衣建议
    try {
      final w =
          await ApiService.weatherRemind(); // 不传位置，由后端用默认城市
      if (mounted) {
        final tex = (w['text'] ?? '').toString();
        final tip = (w['tip'] ?? '').toString();
        final warn = (w['warning'] ?? '').toString();
        final body = tex.isEmpty
            ? '\u4eca\u65e5\u5929\u6c14\u67e5\u8be2\u4e2d\uff0c\u8bf7\u7a0d\u540e\u518d\u8bd5'
            : (tip.isEmpty ? tex : tex + '\uff0c' + tip);
        setState(() {
          _line = warn.isNotEmpty ? body + '\uff1b' + warn : body;
          _icon = Icons.wb_sunny_outlined;
          _color = const Color(0xFFB07A2A);
        });
      }
      return;
    } catch (_) {}
    if (mounted) {
      setState(() => _line = '\u6682\u65e0\u63d0\u9192\uff0c\u8bb0\u5f97\u6309\u65f6\u4f5c\u606f\u3001\u5747\u8861\u996e\u98df');
    }
  }

  /// 从今日用药列表中找第一档，返回如 "氢氯噻嗪片 08:00" 的提示。
  String? _medsTip(List meds) {
    for (final m in meds) {
      final map = m is Map
          ? Map<String, dynamic>.from(m as Map)
          : <String, dynamic>{};
      final name = (map['drug_name'] ??
              map['med_name'] ??
              map['name'] ??
              '\u7528\u836f')
          .toString();
      final slots = map['slots'] is List ? List.from(map['slots']) : [];
      for (final s in slots) {
        final sm = s is Map
            ? Map<String, dynamic>.from(s as Map)
            : <String, dynamic>{};
        final time =
            (sm['time'] ?? sm['scheduled_at'] ?? '\u4eca\u65e5').toString();
        return '\u7528\u836f\u63d0\u9192\uff1a$name $time\uff0c\u8bb0\u5f97\u6309\u65f6\u670d\u7528';
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AfuCard(
      child: Row(children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(color: _color, shape: BoxShape.circle),
          child: Icon(_icon, size: 30, color: Colors.white),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(_line,
              style: const TextStyle(
                  fontSize: 19, color: Color(0xFF222222), height: 1.5)),
        ),
      ]),
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
