import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import '../../afu/afu_theme.dart';
import '../../afu/afu_widgets.dart';
import '../../afu/afu_chat_page.dart' show AfuMessage, AfuBubble;
import '../../services/api.dart';
import 'consult_drug_chat_tab.dart';
import '../bind_page.dart';
import 'meds_tab.dart';
import 'vitals_tab.dart';
import 'me_tab.dart';

/// 跨 Tab 跳转总线：问事页快捷入口调用 HubNav.go(1, 'drugs') 即切到健康百事并滚到对应板块。
/// 问事页字号总线：设置页调节后问事页实时跟随。
/// 全局字号总线：小1.0 / 中1.15 / 大1.3，main 的 MediaQuery 全局跟随。
final chatScale = ValueNotifier<double>(1.0);
/// 消息通知总开关：关闭后 App 内提醒横幅不再弹出。
final notifyEnabled = ValueNotifier<bool>(true);

class HubNav {
  static final tab = ValueNotifier<int>(0);

  /// 底部 Tab 高亮：进入本人功能内页时，健康总览 Tab 切为功能同系色，离开恢复。
  static final accent = ValueNotifier<Color?>(null);
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

/// 健康百事：家属关怀横幅 + 6 张单色可视化功能卡 + 动态健康科普。
class HealthHubTab extends StatefulWidget {
  const HealthHubTab({super.key});
  @override
  State<HealthHubTab> createState() => _HealthHubTabState();
}

/// 科普条目模型：后端接口返回同名 JSON 即可直接替换数据源。
class HealthTip {
  final String title;
  final String body;
  final IconData icon;
  final List<String> tags;
  const HealthTip({required this.title, required this.body, required this.icon, required this.tags});
}

/// 预留的后端拉取位置：接口就绪后把本函数体换成 dio GET 解析即可，
/// 返回 List<HealthTip>，UI 层不用改。
Future<List<HealthTip>> fetchHealthTips() async {
  await Future<void>.delayed(const Duration(milliseconds: 300));
  const pool = [
    HealthTip(
        title: '多喝温开水',
        body: '每天七八杯水，少喝甜饮料和浓茶。',
        icon: Icons.local_drink_outlined,
        tags: ['补充水分']),
    HealthTip(
        title: '饭后走一走',
        body: '饭后半小时散步一刻钟，血糖更平稳。',
        icon: Icons.directions_walk_outlined,
        tags: ['适度锻炼']),
    HealthTip(
        title: '睡个好觉',
        body: '固定时间睡，睡前少看手机，白天适当晒太阳。',
        icon: Icons.nightlight_outlined,
        tags: ['规律作息']),
    HealthTip(
        title: '秋冬防感冒',
        body: '早晚添衣、勤通风，流感季尽量少去人多的地方。',
        icon: Icons.thermostat_outlined,
        tags: ['保暖', '少聚集']),
    HealthTip(
        title: '控盐小窍门',
        body: '每天盐别超一小勺，酱油蚝油也算盐。',
        icon: Icons.soup_kitchen_outlined,
        tags: ['清淡饮食']),
    HealthTip(
        title: '定期量血压',
        body: '每天固定时间量一次，数值记下来复诊带给医生。',
        icon: Icons.favorite_outline,
        tags: ['血压管理']),
  ];
  final list = List<HealthTip>.from(pool)..shuffle();
  return list.take(3).toList();
}

class _HealthHubTabState extends State<HealthHubTab> {
  final _scroll = ScrollController();
  final _topKey = GlobalKey();
  final _newsKey = GlobalKey();
  late Future<List<HealthTip>> _tips = fetchHealthTips();

  @override
  void initState() {
    super.initState();
    HubNav.tab.addListener(_onTab);
    WidgetsBinding.instance.addPostFrameCallback((_) => _consumePending());
  }

  void _onTab() {
    if (HubNav.tab.value == 1) {
      setState(() => _tips = fetchHealthTips());
      _consumePending();
    }
  }

  void _consumePending() {
    final s = HubNav.pendingSection;
    if (s == null) return;
    HubNav.pendingSection = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = (s == 'news' ? _newsKey : _topKey).currentContext;
      if (ctx != null && mounted) {
        Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 400), alignment: 0.05);
      }
    });
  }

  @override
  void didUpdateWidget(HealthHubTab old) {
    super.didUpdateWidget(old);
    _consumePending();
  }

  @override
  void dispose() {
    HubNav.tab.removeListener(_onTab);
    _scroll.dispose();
    super.dispose();
  }

  void _open(BuildContext context, String title, Widget page) {
    Navigator.of(context).push(afuFadeRoute(AfuSubPage(title: title, child: page)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FD),
      appBar: AppBar(title: const Text('健康百事'), backgroundColor: const Color(0xFFF7F9FD), scrolledUnderElevation: 0),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => setState(() => _tips = fetchHealthTips()),
          child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.all(AfuSpace.page),
            children: [
              _CareBanner(key: _topKey),
              const SizedBox(height: 16),
              GridView.count(
                key: const ValueKey('hub-grid'),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 0.8,
                children: [
                  _FuncCard(
                    title: '查药',
                    subtitle: '药品信息查询',
                    icon: Icons.medication_outlined,
                    tint: const Color(0xFFE6F4EA),
                    main: const Color(0xFF6FAF87),
                    onTap: () => _open(context, '查药', const DrugQueryTab()),
                    art: const _DrugArt(color: Color(0xFF6FAF87)),
                  ),
                  _FuncCard(
                    title: '用药',
                    subtitle: '用药提醒管理',
                    icon: Icons.alarm_outlined,
                    tint: const Color(0xFFFDEFF3),
                    main: const Color(0xFFE08CAD),
                    onTap: () => _open(context, '用药', const MedsTab()),
                    art: const _MedArt(color: Color(0xFFE08CAD)),
                  ),
                  _FuncCard(
                    title: '体征',
                    subtitle: '体征数据记录',
                    icon: Icons.show_chart_outlined,
                    tint: const Color(0xFFE8EFFD),
                    main: const Color(0xFF7AA5F0),
                    onTap: () => _open(context, '体征', const VitalsTab()),
                    art: const _VitalArt(color: Color(0xFF7AA5F0)),
                  ),
                  _FuncCard(
                    title: '自查',
                    subtitle: '健康自测评估',
                    icon: Icons.speed_outlined,
                    tint: const Color(0xFFEFEAFA),
                    main: const Color(0xFFA58FD6),
                    onTap: () => _open(context, '自查', const SymptomTab()),
                    art: const _GaugeArt(color: Color(0xFFA58FD6)),
                  ),
                  _FuncCard(
                    title: '报告',
                    subtitle: '体检报告解读',
                    icon: Icons.description_outlined,
                    tint: const Color(0xFFEFF0F4),
                    main: const Color(0xFF9AA0AE),
                    onTap: () => _open(context, '报告', const ReportTab()),
                    art: const _ReportArt(color: Color(0xFF9AA0AE)),
                  ),
                  _FuncCard(
                    title: '咨询',
                    subtitle: '问诊录音记录',
                    icon: Icons.mic_none_outlined,
                    tint: const Color(0xFFFDECEC),
                    main: const Color(0xFFE08B8B),
                    onTap: () => _open(context, '咨询', const ConsultsTab()),
                    art: const _WaveArt(color: Color(0xFFE08B8B)),
                  ),
                ],
              ),
              const SizedBox(height: AfuSpace.section),
              _SectionTitle(key: _newsKey, icon: Icons.newspaper_outlined, text: '健康科普'),
              const SizedBox(height: 8),
              FutureBuilder<List<HealthTip>>(
                future: _tips,
                builder: (c, s) {
                  if (!s.hasData) {
                    return const Column(children: [
                      _TipSkeleton(),
                      _TipSkeleton(),
                      _TipSkeleton(),
                    ]);
                  }
                  return Column(children: [for (final t in s.data!) _TipCard(tip: t)]);
                },
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('以上内容仅供参考，具体请遵医嘱',
                    style: TextStyle(fontSize: 18, color: Color(0xFF9AA5B8)),
                    textAlign: TextAlign.center),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 家属关怀横幅：低饱和浅紫，一键跳家人相伴。
/// 健康信息打包为消息卡片待发送：家人相伴页有留言入口后，把当日用药/体征摘要拼成文本接过去即可。
class _CareBanner extends StatelessWidget {
  const _CareBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2D9F5)),
        boxShadow: [
          BoxShadow(color: const Color(0xFFA58FD6).withOpacity(0.10), blurRadius: 14, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(children: [
        Container(
          width: 60,
          height: 60,
          decoration: const BoxDecoration(color: Color(0xFFEFEAFA), shape: BoxShape.circle),
          child: const Icon(Icons.favorite, size: 32, color: Color(0xFFA58FD6)),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('家属关怀', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: Color(0xFF222222))),
            SizedBox(height: 4),
            Text('家属已绑定，健康记录可一键分享给家人',
                style: TextStyle(fontSize: 18, color: Color(0xFF555555), height: 1.4)),
          ]),
        ),
        const SizedBox(width: 8),
        AfuPressable(
          onTap: () => HubNav.go(2),
          borderRadius: 22,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
            decoration: BoxDecoration(
              color: const Color(0xFFA58FD6),
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Text('分享记录', style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ),
      ]),
    );
  }
}

/// 白色大圆角功能卡：单主题色图标底 + 标题 + 说明 + 装饰画。
class _FuncCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color tint;
  final Color main;
  final VoidCallback onTap;
  final Widget art;
  const _FuncCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.tint,
    required this.main,
    required this.onTap,
    required this.art,
  });

  @override
  Widget build(BuildContext context) {
    return AfuCard(
      onTap: onTap,
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
          child: Icon(icon, size: 27, color: main),
        ),
        const SizedBox(height: 6),
        Text(title, style: AfuElderText.body.copyWith(fontWeight: FontWeight.w700)),
        Text(subtitle, style: AfuElderText.secondary.copyWith(fontSize: 17)),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: main.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: SizedBox(
            height: 30,
            width: double.infinity,
            child: Opacity(opacity: 0.85, child: art),
          ),
        ),
      ]),
    );
  }
}

class _Stroke {
  static Paint of(Color c, [double w = 3]) => Paint()
    ..color = c
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeCap = StrokeCap.round;
  static Paint fill(Color c) => Paint()..color = c;
}

/// 查药：药盒 + 搜索线框。
class _DrugArt extends StatelessWidget {
  final Color color;
  const _DrugArt({required this.color});
  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _DrugPainter(color));
  }
}

class _DrugPainter extends CustomPainter {
  final Color color;
  _DrugPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    canvas.drawRRect(
      RRect.fromLTRBR(w * 0.04, h * 0.25, w * 0.38, h * 0.95, const Radius.circular(6)),
      _Stroke.fill(color.withOpacity(0.18)),
    );
    canvas.drawLine(Offset(w * 0.10, h * 0.45), Offset(w * 0.32, h * 0.45), _Stroke.of(color, 3));
    canvas.drawLine(Offset(w * 0.10, h * 0.65), Offset(w * 0.26, h * 0.65), _Stroke.of(color, 3));
    canvas.drawRRect(
      RRect.fromLTRBR(w * 0.44, h * 0.18, w * 0.96, h * 0.70, const Radius.circular(10)),
      _Stroke.of(color, 2.5),
    );
    canvas.drawCircle(Offset(w * 0.78, h * 0.44), h * 0.12, _Stroke.of(color, 2.5));
    canvas.drawLine(Offset(w * 0.84, h * 0.52), Offset(w * 0.90, h * 0.62), _Stroke.of(color, 3));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}


/// 用药：时钟 + 药瓶 + 打卡进度条。
class _MedArt extends StatelessWidget {
  final Color color;
  const _MedArt({required this.color});
  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _MedPainter(color));
  }
}

class _MedPainter extends CustomPainter {
  final Color color;
  _MedPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final c = Offset(w * 0.18, h * 0.42);
    final r = h * 0.32;
    canvas.drawCircle(c, r, _Stroke.of(color, 2.5));
    canvas.drawLine(c, c + Offset(0, -r * 0.6), _Stroke.of(color, 2.5));
    canvas.drawLine(c, c + Offset(r * 0.5, r * 0.25), _Stroke.of(color, 2.5));
    canvas.drawRRect(
      RRect.fromLTRBR(w * 0.38, h * 0.18, w * 0.58, h * 0.72, const Radius.circular(5)),
      _Stroke.fill(color.withOpacity(0.18)),
    );
    canvas.drawLine(Offset(w * 0.48, h * 0.10), Offset(w * 0.48, h * 0.18), _Stroke.of(color, 3));
    final y = h * 0.88;
    canvas.drawLine(Offset(w * 0.64, y), Offset(w * 0.96, y), _Stroke.of(color.withOpacity(0.3), 5));
    canvas.drawLine(Offset(w * 0.64, y), Offset(w * 0.86, y), _Stroke.of(color, 5));
    canvas.drawCircle(Offset(w * 0.86, y), 4, _Stroke.fill(color));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}


/// 体征：淡色折线 + 数据点。
class _VitalArt extends StatelessWidget {
  final Color color;
  const _VitalArt({required this.color});
  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _VitalPainter(color));
  }
}

class _VitalPainter extends CustomPainter {
  final Color color;
  _VitalPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final frac = [(0.05, 0.75), (0.22, 0.45), (0.40, 0.60), (0.58, 0.25), (0.76, 0.45), (0.95, 0.20)];
    final pts = [for (final f in frac) Offset(w * f.$1, h * f.$2)];
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final q in pts.skip(1)) {
      path.lineTo(q.dx, q.dy);
    }
    canvas.drawPath(path, _Stroke.of(color, 3));
    for (final q in pts) {
      canvas.drawCircle(q, 3.5, _Stroke.fill(Colors.white));
      canvas.drawCircle(q, 3.5, _Stroke.of(color, 2));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}


/// 自查：简易仪表盘。
class _GaugeArt extends StatelessWidget {
  final Color color;
  const _GaugeArt({required this.color});
  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _GaugePainter(color));
  }
}

class _GaugePainter extends CustomPainter {
  final Color color;
  _GaugePainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final c = Offset(w * 0.5, h * 0.92);
    final r = w * 0.38 < h * 0.85 ? w * 0.38 : h * 0.85;
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), 3.14159, 3.14159, false, _Stroke.of(color.withOpacity(0.35), 6));
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), 3.14159, 3.14159 * 0.65, false, _Stroke.of(color, 6));
    const a = 3.14159 + 3.14159 * 0.65;
    const dx = -0.454, dy = -0.891;
    canvas.drawLine(c, c + Offset(r * 0.65 * dx, r * 0.65 * dy), _Stroke.of(color, 3.5));
    canvas.drawCircle(c, 4, _Stroke.fill(color));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}


/// 报告：文档 + 数据示意线。
class _ReportArt extends StatelessWidget {
  final Color color;
  const _ReportArt({required this.color});
  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _ReportPainter2(color));
  }
}

class _ReportPainter2 extends CustomPainter {
  final Color color;
  _ReportPainter2(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    canvas.drawRRect(
      RRect.fromLTRBR(w * 0.05, h * 0.08, w * 0.42, h * 0.94, const Radius.circular(6)),
      _Stroke.fill(color.withOpacity(0.15)),
    );
    for (var i = 0; i < 3; i++) {
      final y = h * (0.28 + i * 0.22);
      canvas.drawLine(Offset(w * 0.11, y), Offset(w * 0.36, y), _Stroke.of(color, 3));
    }
    final bars = [0.5, 0.8, 0.4, 0.65];
    for (var i = 0; i < bars.length; i++) {
      final x = w * (0.50 + i * 0.125);
      final bh = (h * 0.78) * bars[i];
      canvas.drawRRect(
        RRect.fromLTRBR(x, h * 0.86 - bh, x + w * 0.075, h * 0.86, const Radius.circular(3)),
        _Stroke.fill(color.withOpacity(0.45)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}


/// 咨询：麦克风 + 波形。
class _WaveArt extends StatelessWidget {
  final Color color;
  const _WaveArt({required this.color});
  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _WavePainter2(color));
  }
}

class _WavePainter2 extends CustomPainter {
  final Color color;
  _WavePainter2(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    canvas.drawRRect(
        RRect.fromLTRBR(w * 0.06, h * 0.12, w * 0.22, h * 0.70, const Radius.circular(7)),
        _Stroke.of(color, 2.5));
    canvas.drawLine(Offset(w * 0.14, h * 0.70), Offset(w * 0.14, h * 0.90), _Stroke.of(color, 2.5));
    canvas.drawLine(Offset(w * 0.07, h * 0.90), Offset(w * 0.21, h * 0.90), _Stroke.of(color, 2.5));
    final midY = h * 0.5;
    final amps = [0.10, 0.22, 0.34, 0.22, 0.40, 0.22, 0.30, 0.16, 0.10, 0.06];
    for (var i = 0; i < amps.length; i++) {
      final x = w * (0.30 + i * 0.065);
      final a = h * amps[i];
      canvas.drawLine(Offset(x, midY - a), Offset(x, midY + a), _Stroke.of(color.withOpacity(0.6), 2.5));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}


/// 科普图文卡：左圆图标 + 右标题说明 + 底部浅色标签。
class _TipCard extends StatelessWidget {
  final HealthTip tip;
  const _TipCard({required this.tip});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AfuCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: const Color(0xFFE8EFFD),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                    color: Colors.white, shape: BoxShape.circle),
                child: Icon(tip.icon, size: 30, color: AfuColors.primaryDeep),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tip.title, style: AfuElderText.body.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(tip.body, style: AfuElderText.secondary),
              ]),
            ),
          ]),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              for (final tag in tip.tags)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8EFFD),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(tag, style: const TextStyle(fontSize: 16, color: AfuColors.primaryDeep)),
                ),
            ],
          ),
        ]),
      ),
    );
  }
}

class _TipSkeleton extends StatelessWidget {
  const _TipSkeleton();
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: AfuCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AfuSkeleton(width: 160, height: 24),
          SizedBox(height: 8),
          AfuSkeleton(width: double.infinity, height: 20),
        ]),
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
/// 家人相伴 V2：已绑定直接进聊天窗口，未绑定显示引导卡。
/// 家人相伴 V3：人物头图 + 引用分享 + 问事同款输入栏。
/// 健康数据自动同步家属端（后端原有接口），本页卡片只做引用到对话，不推送。
/// 记录本地持久化；后端家属消息接口就绪后替换 _loadHistory/_saveHistory 即可。
/// 家人互动：会话列表（借鉴微信"先选人、再进对话"的交互思路，不复刻UI）。
/// 展示已绑定的所有亲属，点击某条再进入与TA的单独对话页。
class FamilyTab extends StatefulWidget {
  const FamilyTab({super.key});
  @override
  State<FamilyTab> createState() => _FamilyTabState();
}

/// 会话列表里一条绑定关系的展示信息。
class _FamConvItem {
  final String name; // 对方昵称
  final String key; // 该会话的本地存储键（按人区分）
  final String preview; // 最后一条消息预览
  final String avatar; // 后端返回的自定义头像（URL/路径），空则用默认占位
  final bool active; // 是否已确认绑定
  const _FamConvItem({
    required this.name,
    required this.key,
    this.preview = '',
    this.avatar = '',
    this.active = true,
  });
}

class _FamilyTabState extends State<FamilyTab> {
  bool _loading = true;
  List<_FamConvItem> _convs = [];
  String _role = 'elder';

  /// 打开绑定页：长辈生成邀请码、家属输入邀请码完成绑定。
  /// （个人中心已按要求不再承载亲属绑定/邀请码模块，绑定入口统一放在「家人互动」）
  void _openBind() {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) =>
            AfuSubPage(title: '添加家人', child: BindPage(role: _role))));
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = <_FamConvItem>[];
    try {
      _role = await ApiService.getRole() ?? 'elder';
      final binds = await ApiService.bindList();
      var idx = 0;
      for (final b in binds) {
        final m = b is Map
            ? Map<String, dynamic>.from(b as Map)
            : <String, dynamic>{};
        final active = (m['status'] ?? '').toString() == 'active';
        final name = (m['other_nickname'] ??
                m['nickname'] ??
                m['elder_nickname'] ??
                m['family_nickname'] ??
                '家人 $idx')
            .toString();
        final key = 'family_chat_${name}_$idx';
        final avatar = (m['avatar'] ?? m['avatar_url'] ?? m['other_avatar'] ?? '').toString();
        final item = _FamConvItem(name: name, key: key, active: active, avatar: avatar);
        items.add(item);
        idx++;
      }
      // 读取每个会话的最后一条消息作预览
      for (var i = 0; i < items.length; i++) {
        try {
          final prefs = await SharedPreferences.getInstance();
          final raw = prefs.getString(items[i].key);
          if (raw != null && raw.isNotEmpty) {
            final list = jsonDecode(raw) as List;
            if (list.isNotEmpty) {
              final last =
                  Map<String, dynamic>.from(list.last as Map);
              final kind = (last['kind'] ?? 'text').toString();
              final txt = (last['text'] ?? (last['title'] ?? '')).toString();
              final preview = kind == 'image'
                  ? '[图片]'
                  : (kind == 'audio' ? '[语音]' : txt);
              items[i] = _FamConvItem(
                  name: items[i].name,
                  key: items[i].key,
                  preview: preview,
                  active: items[i].active,
                  avatar: items[i].avatar);
            }
          }
        } catch (_) {}
      }
    } catch (_) {}
    if (mounted) setState(() { _convs = items; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFD),
      appBar: AppBar(
        // 全局规则：不再显示页面顶部标题
        backgroundColor: const Color(0xFFF7FAFD),
        scrolledUnderElevation: 0
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          color: const Color(0xFF345C87),
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(
                      color: const Color(0xFF345C87)))
              : _convs.isEmpty
                  ? ListView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                      children: [
                        _guideBox(),
                        // 长辈健康动态 / 家人互联小提示仅家属端展示，长辈视角不出现
                        if (_role == 'family') ...[
                          const SizedBox(height: 16),
                          _helpCard(),
                        ],
                      ],
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                      children: [
                        for (final c in _convs) _convTile(c),
                        // 长辈健康动态 / 家人互联小提示仅家属端展示，长辈视角只保留家人列表与去对话
                        if (_role == 'family') ...[
                          const SizedBox(height: 16),
                          _dynamicCard(),
                          const SizedBox(height: 16),
                          _helpCard(),
                        ],
                        // 长辈视角：列表下方补充家人互联小贴士，填充空白
                        // 间距：tiles 自带底部 12 + 此处 4 = 16；底部 padding 20 + 4 = 24
                        if (_role != 'family') ...[
                          const SizedBox(height: 4),
                          const _ElderTipCard(),
                          const SizedBox(height: 4),
                        ],
                      ],
                    ),
        ),
      ),
    );
  }

  /// 单个亲戚条目卡片：点击进入与该亲属的对话。
  Widget _convTile(_FamConvItem c) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AfuPressable(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => FamConversationPage(
                name: c.name, storeKey: c.key))),
        borderRadius: 22,
        child: AfuCard(
          child: Row(children: [
          _FamAvatar(avatar: c.avatar),
          const SizedBox(width: 14),
          Expanded(
            child: Text(c.name,
                style:
                    AfuElderText.body.copyWith(fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 10),
          const Text('去对话 >',
              style: TextStyle(fontSize: 17, color: Color(0xFF6B7280))),
          ]),
        ),
      ),
    );
  }

  /// 家人互动空状态：简约对话插图 + 友好提示。
  /// 家人互动空状态内容：简约对话插图 + 友好提示（白色圆角卡）。
  Widget _guideBox() {
    return Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(28, 36, 28, 32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: const Color(0xFFD8E6F3)),
            boxShadow: [
              BoxShadow(
                  color: const Color(0xFF345C87).withOpacity(0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 6)),
            ],
          ),
          child: Column(children: [
            // 简约插图：两个对话气泡
            Container(
              width: 120,
              height: 96,
              decoration: BoxDecoration(
                color: const Color(0xFFEDF4FB),
                borderRadius: BorderRadius.circular(24),
              ),
              padding: const EdgeInsets.all(16),
              child: CustomPaint(painter: _FamEmptyPainter()),
            ),
            const SizedBox(height: 20),
            const Text('还没有聊天记录',
                style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF212936))),
            const SizedBox(height: 12),
            const Text('点击下方卡片，引用一条健康记录到对话中，\n和家人一起讨论',
                style: TextStyle(
                    fontSize: 19, color: Color(0xFF6B7280), height: 1.6),
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF345C87),
                  foregroundColor: Colors.white,
                ),
                onPressed: _openBind,
                child: const Text('去绑定家人'),
              ),
            ),
          ]),
    );
  }

  /// 长辈健康动态卡：最新用药提醒 + 最新体征记录。
  /// 数据走现有列表接口自动读取（绑定长辈自动同步，无需新后端接口）。
  Widget _dynamicCard() {
    return const _ElderDynamic();
  }

  /// 家人互联帮助提示卡。
  Widget _helpCard() {
    return AfuCard(
      child: Row(children: [
        Container(
          width: 56,
          height: 56,
          decoration: const BoxDecoration(
              color: Color(0xFFEDF4FB), shape: BoxShape.circle),
          child: const Icon(Icons.handshake_outlined,
              size: 30, color: const Color(0xFF345C87)),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('家人互联小提示',
                    style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF212936))),
                SizedBox(height: 6),
                Text('绑定长辈后，可查看长辈健康记录，及时收到用药提醒',
                    style: TextStyle(
                        fontSize: 18,
                        color: Color(0xFF6B7280),
                        height: 1.5)),
              ]),
        ),
      ]),
    );
  }
}

/// 家人互动空状态简约插图：两个对话气泡。
class _FamEmptyPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final stroke = Paint()
      ..color = const Color(0xFF345C87)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()
      ..color = const Color(0xFF345C87)
      ..style = PaintingStyle.fill;
    final b1 = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, s.width * 0.58, s.height * 0.46),
        const Radius.circular(12));
    canvas.drawRRect(b1, stroke);
    for (var i = 0; i < 3; i++) {
      canvas.drawCircle(
          Offset(s.width * (0.16 + i * 0.13), s.height * 0.23), 3, fill);
    }
    final b2 = RRect.fromRectAndRadius(
        Rect.fromLTWH(s.width * 0.36, s.height * 0.52, s.width * 0.64,
            s.height * 0.48),
        const Radius.circular(12));
    canvas.drawRRect(
        b2, Paint()..color = const Color(0xFF345C87).withOpacity(0.18));
    canvas.drawRRect(b2, stroke);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// 单条消息的数据模型（本地持久化）。
class _FamMsg {
  final bool isMe;
  final String kind;
  final String text;
  final String title;
  final List<String> lines;
  final String image;
  final int dur;
  const _FamMsg({
    required this.isMe,
    this.kind = 'text',
    this.text = '',
    this.title = '',
    this.lines = const [],
    this.image = '',
    this.dur = 0,
  });

  Map<String, dynamic> toJson() => {
        'isMe': isMe,
        'kind': kind,
        'text': text,
        'title': title,
        'lines': lines,
        'image': image,
        'dur': dur,
      };

  static _FamMsg fromJson(Map<String, dynamic> j) => _FamMsg(
        isMe: j['isMe'] == true,
        kind: (j['kind'] ?? 'text').toString(),
        text: (j['text'] ?? '').toString(),
        title: (j['title'] ?? '').toString(),
        lines: [
          for (final e in (j['lines'] as List? ?? [])) e.toString()
        ],
        image: (j['image'] ?? '').toString(),
        dur: (j['dur'] as num? ?? 0).toInt(),
      );
}

/// 与某一亲属的单聊页面。storeKey 用于按人区分本地消息。
class FamConversationPage extends StatefulWidget {
  final String name;
  final String storeKey;

  /// 健康总览一键询问：prefill 预填输入框，autoText 进页自动发送一条业务记录。
  final String? prefill;
  final String? autoText;
  const FamConversationPage(
      {super.key,
      required this.name,
      required this.storeKey,
      this.prefill,
      this.autoText});
  @override
  State<FamConversationPage> createState() => _FamConversationState();
}

class _FamConversationState extends State<FamConversationPage> {
  List<_FamMsg> _msgs = [];
  final _input = TextEditingController();
  final _list = ScrollController();
  bool _holding = false;
  final _rec = AudioRecorder();
  DateTime? _recStart;

  @override
  void initState() {
    super.initState();
    if ((widget.prefill ?? '').isNotEmpty) {
      _input.text = widget.prefill!;
    }
    _loadHistory();
  }

  @override
  void dispose() {
    _input.dispose();
    _list.dispose();
    try {
      _rec.dispose();
    } catch (_) {}
    super.dispose();
  }

  Future<void> _loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(widget.storeKey);
      if (raw == null || raw.isEmpty) return;
      final list = jsonDecode(raw) as List;
      _msgs = [
        for (final e in list)
          _FamMsg.fromJson(Map<String, dynamic>.from(e as Map))
      ];
      if (mounted) setState(() {});
    } catch (_) {}
    // 一键询问带入的业务记录：历史加载完后再追加发送，避免被覆盖
    if ((widget.autoText ?? '').isNotEmpty && mounted) {
      _push(_FamMsg(isMe: true, text: widget.autoText!));
    }
  }

  Future<void> _saveHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          widget.storeKey, jsonEncode([for (final m in _msgs) m.toJson()]));
    } catch (_) {}
  }

  void _push(_FamMsg m) {
    setState(() => _msgs.add(m));
    _saveHistory();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_list.hasClients) return;
      _list.animateTo(_list.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic);
    });
  }

  void _sendText() {
    final t = _input.text.trim();
    if (t.isEmpty) return;
    _input.clear();
    _push(_FamMsg(isMe: true, text: t));
  }

  Future<void> _voiceStart() async {
    try {
      if (!await _rec.hasPermission()) throw Exception('no mic');
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/fam_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _rec.start(const RecordConfig(), path: path);
      _recStart = DateTime.now();
      if (mounted) setState(() => _holding = true);
    } catch (_) {
      if (mounted) {
        setState(() => _holding = false);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('录音不可用，请用文字')));
      }
    }
  }

  Future<void> _voiceEnd() async {
    if (!_holding) return;
    try {
      final path = await _rec.stop();
      final secs = _recStart == null
          ? 0
          : DateTime.now().difference(_recStart!).inSeconds;
      if (path != null && secs >= 1) {
        _push(
            _FamMsg(isMe: true, kind: 'audio', text: path, dur: secs));
      }
    } catch (_) {}
    _recStart = null;
    if (mounted) setState(() => _holding = false);
  }

  /// 快捷卡片：0体检报告 1问事记录 2打卡记录。
  Future<void> _quote(int i) async {
    if (i == 0) {
      try {
        final list = await ApiService.reportList();
        if (list.isEmpty) {
          _push(const _FamMsg(
              isMe: true,
              kind: 'health',
              title: '体检报告',
              lines: ['还没有上传过体检报告']));
          return;
        }
        final m = Map<String, dynamic>.from(list.first as Map);
        final ocr = (m['ocr_text'] ?? '').toString();
        final adv = (m['advice_text'] ?? '').toString();
        _push(_FamMsg(isMe: true, kind: 'health', title: '体检报告', lines: [
          if (ocr.isNotEmpty)
            (ocr.length > 80 ? '${ocr.substring(0, 80)}…' : ocr),
          if (adv.isNotEmpty)
            (adv.length > 80 ? '${adv.substring(0, 80)}…' : adv),
        ]));
      } catch (_) {
        _push(const _FamMsg(
            isMe: true,
            kind: 'health',
            title: '体检报告',
            lines: ['报告读取失败，稍后再试']));
      }
      return;
    }
    if (i == 1) {
      final h = ChatHistory.items.where((m) => !m.thinking).toList();
      if (h.length < 2) {
        _push(const _FamMsg(
            isMe: true,
            kind: 'health',
            title: '问事记录',
            lines: ['还没有使用过问事']));
        return;
      }
      final q = h[h.length - 2].text;
      final a = h[h.length - 1].text;
      _push(_FamMsg(isMe: true, kind: 'health', title: '问事记录', lines: [
        '问：${q.length > 40 ? '${q.substring(0, 40)}…' : q}',
        '答：${a.length > 60 ? '${a.substring(0, 60)}…' : a}',
      ]));
      return;
    }
    try {
      final meds = await ApiService.medsToday();
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
      _push(_FamMsg(
          isMe: true,
          kind: 'health',
          title: '打卡记录',
          lines: ['今天已打卡 $taken / $total 次']));
    } catch (_) {
      _push(const _FamMsg(
          isMe: true, kind: 'health', title: '打卡记录', lines: ['打卡记录读取失败，稍后再试']));
    }
  }

  /// 加号菜单：上传图片 / 引用健康记录。
  void _plusMenu() {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.image_outlined,
                size: 32, color: AfuColors.primaryDeep),
            title: const Text('上传图片', style: AfuElderText.body),
            onTap: () async {
              Navigator.of(context).pop();
              final f = await ImagePicker()
                  .pickImage(source: ImageSource.gallery);
              if (f == null || !mounted) return;
              try {
                final bytes = await f.readAsBytes();
                _push(_FamMsg(
                    isMe: true,
                    kind: 'image',
                    text: f.name,
                    image: base64Encode(bytes)));
              } catch (_) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('图片读取失败，请重试')));
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.format_quote_outlined,
                size: 32, color: AfuColors.primaryDeep),
            title: const Text('引用健康记录', style: AfuElderText.body),
            onTap: () {
              Navigator.of(context).pop();
              showModalBottomSheet<void>(
                context: context,
                shape: const RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(24))),
                builder: (_) => SafeArea(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    for (var k = 0; k < 3; k++)
                      ListTile(
                        leading: Icon([
                          Icons.description_outlined,
                          Icons.chat_bubble_outline,
                          Icons.check_circle_outline
                        ][k],
                            size: 32,
                            color: AfuColors.primaryDeep),
                        title: Text(
                            ['体检报告', '问事记录', '打卡记录'][k],
                            style: AfuElderText.body),
                        onTap: () {
                          Navigator.of(context).pop();
                          _quote(k);
                        },
                      ),
                  ]),
                ),
              );
            },
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FD),
      appBar: AppBar(
        title: Text(widget.name),
        backgroundColor: const Color(0xFFF7F9FD),
        scrolledUnderElevation: 0,
        leading: IconButton(
          tooltip: '返回',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back, color: AfuColors.primaryDeep),
        ),
      ),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: _msgs.isEmpty
                ? const Padding(
                    padding: EdgeInsets.only(top: 24),
                    child: Center(
                      child: Text(
                          '还没有聊天记录\n点击下方卡片，引用一条健康记录到对话中，\n和家人一起讨论',
                          style: TextStyle(
                              fontSize: 18,
                              color: Color(0xFF555555),
                              height: 1.8),
                          textAlign: TextAlign.center),
                    ),
                  )
                : ListView.builder(
                    controller: _list,
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                    itemCount: _msgs.length,
                    itemBuilder: (c, i) => _FamBubble(msg: _msgs[i]),
                  ),
          ),
          _FamInputBar(
            controller: _input,
            holding: _holding,
            onSubmit: _sendText,
            onVoiceStart: _voiceStart,
            onVoiceEnd: _voiceEnd,
            onPlus: _plusMenu,
          ),
        ]),
      ),
    );
  }
}
class _QuickBar extends StatelessWidget {
  final ValueChanged<int> onTap;
  const _QuickBar({required this.onTap});

  static const _items = [
    (Icons.description_outlined, '体检报告'),
    (Icons.chat_bubble_outline, '问事记录'),
    (Icons.check_circle_outline, '打卡记录'),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < _items.length; i++) ...[
            Expanded(
              child: AfuPressable(
                onTap: () => onTap(i),
                borderRadius: 20,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFDCE6F7)),
                    boxShadow: [
                      BoxShadow(
                          color: AfuColors.primaryDeep.withOpacity(0.06),
                          blurRadius: 8,
                          offset: const Offset(0, 3)),
                    ],
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                          color: Color(0xFFE8EFFD), shape: BoxShape.circle),
                      child: Icon(_items[i].$1,
                          size: 26, color: AfuColors.primaryDeep),
                    ),
                    const SizedBox(height: 6),
                    Text(_items[i].$2,
                        style: const TextStyle(
                            fontSize: 17, color: Color(0xFF222222)),
                        textAlign: TextAlign.center,
                        maxLines: 2),
                  ]),
                ),
              ),
            ),
            if (i < _items.length - 1) const SizedBox(width: 10),
          ],
        ],
      ),
    );
  }
}

/// 聊天泡：长辈右蓝、家属左白；引用的记录以内嵌缩略卡展示并标注来源。
class _FamBubble extends StatelessWidget {
  final _FamMsg msg;
  const _FamBubble({required this.msg});

  @override
  Widget build(BuildContext context) {
    final baseColor =
        msg.isMe ? AfuColors.primaryDeep : Colors.white;
    final inkColor =
        msg.isMe ? Colors.white : const Color(0xFF222222);
    final border =
        msg.isMe ? null : Border.all(color: const Color(0xFFDCE6F7));
    if (msg.kind == 'image' && msg.image.isNotEmpty) {
      try {
        return Align(
          alignment:
              msg.isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: EdgeInsets.only(
                left: msg.isMe ? 48 : 0,
                right: msg.isMe ? 0 : 48,
                top: 6,
                bottom: 6),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: baseColor,
              borderRadius: BorderRadius.circular(20),
              border: border,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.memory(base64Decode(msg.image),
                  width: 200, fit: BoxFit.cover),
            ),
          ),
        );
      } catch (_) {}
    }
    if (msg.kind == 'audio') {
      return _AudioBubble(msg: msg);
    }
    if (msg.kind == 'health') {
      return Align(
        alignment: msg.isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: EdgeInsets.only(
              left: msg.isMe ? 48 : 0,
              right: msg.isMe ? 0 : 48,
              top: 6,
              bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: baseColor,
            borderRadius: BorderRadius.circular(20),
            border: border,
          ),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: msg.isMe
                        ? Colors.white.withOpacity(0.16)
                        : const Color(0xFFF5F8FD),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(Icons.health_and_safety_outlined,
                              size: 24, color: inkColor),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(msg.title,
                                style: TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.w800,
                                    color: inkColor)),
                          ),
                        ]),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 3),
                          decoration: BoxDecoration(
                            color: msg.isMe
                                ? Colors.white.withOpacity(0.25)
                                : const Color(0xFFE8EFFD),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text('来源：${msg.title}',
                              style: TextStyle(
                                  fontSize: 16,
                                  color: msg.isMe
                                      ? Colors.white
                                      : AfuColors.primaryDeep)),
                        ),
                        const SizedBox(height: 6),
                        for (final line in msg.lines)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(line,
                                style: TextStyle(
                                    fontSize: 18,
                                    height: 1.5,
                                    color: inkColor)),
                          ),
                      ]),
                ),
              ]),
        ),
      );
    }
    return Align(
      alignment: msg.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
            left: msg.isMe ? 48 : 0,
            right: msg.isMe ? 0 : 48,
            top: 6,
            bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: baseColor,
          borderRadius: BorderRadius.circular(20),
          border: border,
        ),
        child: Text(msg.text,
            style: TextStyle(fontSize: 19, height: 1.5, color: inkColor)),
      ),
    );
  }
}

/// 底部输入栏：与问事页同款（话筒 + 胶囊框 + 加号 + 发送）。
class _FamInputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool holding;
  final VoidCallback onSubmit;
  final VoidCallback onVoiceStart;
  final VoidCallback onVoiceEnd;
  final VoidCallback onPlus;
  const _FamInputBar({
    required this.controller,
    required this.holding,
    required this.onSubmit,
    required this.onVoiceStart,
    required this.onVoiceEnd,
    required this.onPlus,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 18),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
              color: AfuColors.primaryDeep.withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Row(children: [
        GestureDetector(
          onLongPressStart: (_) => onVoiceStart(),
          onLongPressEnd: (_) => onVoiceEnd(),
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: holding
                  ? const Color(0xFFE57373)
                  : const Color(0xFFE8EFFD),
            ),
            child: Icon(holding ? Icons.mic : Icons.mic_none_outlined,
                size: 28,
                color: holding ? Colors.white : AfuColors.primaryDeep),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: controller,
            minLines: 1,
            maxLines: 4,
            style: const TextStyle(fontSize: 19, color: Color(0xFF222222)),
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => onSubmit(),
            decoration: InputDecoration(
              hintText: '和家人说点什么…',
              hintStyle:
                  const TextStyle(fontSize: 18, color: Color(0xFF555555)),
              filled: true,
              fillColor: const Color(0xFFF5F8FD),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide: const BorderSide(color: Color(0xFFDCE6F7)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide: const BorderSide(color: Color(0xFFDCE6F7)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide:
                    const BorderSide(color: AfuColors.primary, width: 2),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        AfuPressable(
          onTap: onPlus,
          borderRadius: 28,
          child: Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFFE8EFFD),
            ),
            child: const Icon(Icons.add,
                size: 28, color: AfuColors.primaryDeep),
          ),
        ),
        const SizedBox(width: 8),
        AfuPressable(
          onTap: onSubmit,
          borderRadius: 28,
          child: Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AfuColors.primaryDeep,
            ),
            child: const Icon(Icons.send, size: 28, color: Colors.white),
          ),
        ),
      ]),
    );
  }
}

/// 语音泡：点播放键收听，显示秒数。
class _AudioBubble extends StatefulWidget {
  final _FamMsg msg;
  const _AudioBubble({required this.msg});

  @override
  State<_AudioBubble> createState() => _AudioBubbleState();
}

class _AudioBubbleState extends State<_AudioBubble> {
  final _player = AudioPlayer();
  bool _playing = false;

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    try {
      if (_playing) {
        await _player.stop();
        if (mounted) setState(() => _playing = false);
        return;
      }
      await _player.play(DeviceFileSource(widget.msg.text));
      if (mounted) setState(() => _playing = true);
      _player.onPlayerComplete.first.then((_) {
        if (mounted) setState(() => _playing = false);
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('录音找不到了，可能已被清理')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMe = widget.msg.isMe;
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
            left: isMe ? 48 : 0,
            right: isMe ? 0 : 48,
            top: 6,
            bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isMe ? AfuColors.primaryDeep : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border:
              isMe ? null : Border.all(color: const Color(0xFFDCE6F7)),
        ),
        child: AfuPressable(
          onTap: _toggle,
          borderRadius: 14,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isMe
                    ? Colors.white.withOpacity(0.25)
                    : const Color(0xFFE8EFFD),
              ),
              child: Icon(_playing ? Icons.stop : Icons.play_arrow,
                  size: 28,
                  color: isMe ? Colors.white : AfuColors.primaryDeep),
            ),
            const SizedBox(width: 10),
            Text('${widget.msg.dur}秒语音',
                style: TextStyle(
                    fontSize: 19,
                    color: isMe ? Colors.white : const Color(0xFF222222))),
          ]),
        ),
      ),
    );
  }
}

class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FD),
      // 全局规则：不再显示页面顶部标题栏
      body: const SafeArea(child: MeTab(role: 'elder')),
    );
  }
}

/// 长辈健康动态：读取最新用药提醒与最新体征记录，点击前往健康总览。
class _ElderDynamic extends StatefulWidget {
  const _ElderDynamic();
  @override
  State<_ElderDynamic> createState() => _ElderDynamicState();
}

class _ElderDynamicState extends State<_ElderDynamic> {
  late final Future<List<String>> _future = _load();

  static Future<List<String>> _load() async {
    String med = '暂无用药提醒';
    String vit = '暂无体征记录';
    try {
      final meds = await ApiService.medsToday();
      for (final m in meds) {
        final map =
            m is Map ? Map<String, dynamic>.from(m as Map) : <String, dynamic>{};
        final name = (map['name'] ?? '').toString();
        final slots = map['slots'] is List ? List.from(map['slots']) : [];
        for (final s in slots) {
          final sm =
              s is Map ? Map<String, dynamic>.from(s as Map) : <String, dynamic>{};
          if ((sm['status'] ?? 'pending').toString() == 'pending' &&
              name.isNotEmpty) {
            final slot = (sm['slot'] ?? '').toString();
            med = '$name ${slot.isEmpty ? '今日' : slot}待服用';
            break;
          }
        }
        if (med != '暂无用药提醒') break;
      }
    } catch (_) {}
    try {
      final vs = await ApiService.vitalsList(days: 30);
      if (vs.isNotEmpty) {
        final m = vs is List
            ? Map<String, dynamic>.from(vs.first as Map)
            : <String, dynamic>{};
        final type = (m['type'] ?? '').toString();
        if (type == 'bp') {
          vit = '血压 ${m['systolic'] ?? '-'}/${m['diastolic'] ?? '-'}';
        } else {
          vit = '$type ${m['value'] ?? ''}'.trim();
        }
      }
    } catch (_) {}
    return [med, vit];
  }

  @override
  Widget build(BuildContext context) {
    return AfuCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
                color: Color(0xFFEDF4FB), shape: BoxShape.circle),
            child: const Icon(Icons.monitor_heart_outlined,
                size: 30, color: Color(0xFF345C87)),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text('长辈健康动态',
                style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF212936))),
          ),
        ]),
        const SizedBox(height: 12),
        FutureBuilder<List<String>>(
          future: _future,
          builder: (c, s) {
            final rows = s.data ?? const ['正在加载…', '正在加载…'];
            return Column(children: [
              for (final r in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    const Icon(Icons.circle,
                        size: 10, color: const Color(0xFF345C87)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(r,
                          style: const TextStyle(
                              fontSize: 18,
                              color: Color(0xFF212936),
                              height: 1.5)),
                    ),
                  ]),
                ),
            ]);
          },
        ),
        const SizedBox(height: 4),
        AfuPressable(
          onTap: () => HubNav.go(0),
          borderRadius: 12,
          child: const Text('可前往健康总览查看完整记录',
              style: TextStyle(fontSize: 16, color: Color(0xFF6B7280))),
        ),
      ]),
    );
  }
}

/// 联系人动态头像：优先展示后端返回的用户自定义头像（http 远端或本地路径），
/// 无自定义头像时展示默认占位图标。跟随后端接口返回实时刷新。
/// 【等待后端接口开发完成】bind 接口暂未返回头像字段（avatar/avatar_url），
/// 字段就绪后 _load 中已预留读取逻辑，无需改 UI。
class _FamAvatar extends StatelessWidget {
  final String avatar;
  const _FamAvatar({required this.avatar});

  @override
  Widget build(BuildContext context) {
    Widget inner;
    if (avatar.startsWith('http')) {
      inner = ClipOval(
        child: Image.network(avatar,
            width: 72,
            height: 72,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const _FamAvatarFallback()),
      );
    } else if (avatar.isNotEmpty) {
      inner = ClipOval(
        child: Image.asset(avatar,
            width: 72,
            height: 72,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const _FamAvatarFallback()),
      );
    } else {
      inner = const _FamAvatarFallback();
    }
    return SizedBox(
      width: 72,
      height: 72,
      child: Container(
        decoration: const BoxDecoration(
            color: Color(0xFFE8EFFD), shape: BoxShape.circle),
        child: inner,
      ),
    );
  }
}

class _FamAvatarFallback extends StatelessWidget {
  const _FamAvatarFallback();
  @override
  Widget build(BuildContext context) {
    return const Icon(Icons.person, size: 40, color: const Color(0xFF345C87));
  }
}

/// 长辈视角家人互联小贴士：纯前端提示卡，无后端依赖。
class _ElderTipCard extends StatelessWidget {
  const _ElderTipCard();
  @override
  Widget build(BuildContext context) {
    return AfuCard(
      child: Row(children: [
        Container(
          width: 56,
          height: 56,
          decoration: const BoxDecoration(
              color: Color(0xFFEDF4FB), shape: BoxShape.circle),
          child: const Icon(Icons.handshake_outlined,
              size: 30, color: const Color(0xFF345C87)),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('家人互联小贴士',
                    style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF212936))),
                SizedBox(height: 6),
                Text('绑定家属后，家属可及时查看您的用药提醒和健康记录，帮助您按时用药。',
                    style: TextStyle(
                        fontSize: 18,
                        color: Color(0xFF6B7280),
                        height: 1.5)),
                SizedBox(height: 6),
                Text('有问题可随时点击去对话联系家属。',
                    style: TextStyle(
                        fontSize: 16,
                        color: Color(0xFF6B7280),
                        height: 1.5)),
              ]),
        ),
      ]),
    );
  }
}
