import 'package:flutter/material.dart';

import 'afu_theme.dart';
import 'afu_widgets.dart';

/// 简约柔和的助手插画：纯 CustomPainter 矢量绘制，无图片资源。
/// 构图：浅蓝光晕底 + 圆润机器人助手（圆头、微笑弧线、身体、两侧小星），克制不幼稚。
class AfuAssistantMoon extends StatelessWidget {
  final double size;
  const AfuAssistantMoon({super.key, this.size = 168});

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: Image.asset(
          'assets/assistant.png',
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => SizedBox(
            width: size,
            height: size,
            child: CustomPaint(painter: _AssistantPainter()),
          ),
        ),
      ),
    );
  }
}

class _AssistantPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    final halo = Paint()..color = const Color(0xFFE3ECFD);
    canvas.drawCircle(Offset(cx, cy), size.width * 0.48, halo);
    final halo2 = Paint()..color = const Color(0xFFF0F5FE);
    canvas.drawCircle(Offset(cx, cy), size.width * 0.36, halo2);

    final body = Paint()..color = const Color(0xFF5B8DEF);
    final face = Paint()..color = Colors.white;
    final dark = Paint()
      ..color = const Color(0xFF3E6FD8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.018
      ..strokeCap = StrokeCap.round;

    // 身体
    canvas.drawRRect(
      RRect.fromLTRBR(
        cx - size.width * 0.2,
        cy - size.height * 0.02,
        cx + size.width * 0.2,
        cy + size.height * 0.34,
        Radius.circular(size.width * 0.12),
      ),
      body,
    );
    // 头
    canvas.drawCircle(Offset(cx, cy - size.height * 0.16), size.width * 0.21, face);
    canvas.drawCircle(Offset(cx, cy - size.height * 0.16), size.width * 0.21, Paint()
      ..color = const Color(0xFFD7E3FA)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.014);
    // 眼睛
    final eye = Paint()..color = const Color(0xFF3E6FD8);
    canvas.drawCircle(Offset(cx - size.width * 0.075, cy - size.height * 0.18), size.width * 0.022, eye);
    canvas.drawCircle(Offset(cx + size.width * 0.075, cy - size.height * 0.18), size.width * 0.022, eye);
    // 微笑
    canvas.drawArc(
      Rect.fromCenter(center: Offset(cx, cy - size.height * 0.12), width: size.width * 0.12, height: size.width * 0.09),
      0.25,
      3.14 - 0.5,
      false,
      dark,
    );
    // 天线
    canvas.drawLine(
      Offset(cx, cy - size.height * 0.37),
      Offset(cx, cy - size.height * 0.29),
      dark,
    );
    canvas.drawCircle(Offset(cx, cy - size.height * 0.38), size.width * 0.025, eye);
    // 身体装饰
    canvas.drawCircle(Offset(cx, cy + size.height * 0.16), size.width * 0.045, face);
    // 两侧小星
    _star(canvas, Offset(cx - size.width * 0.38, cy - size.height * 0.3), size.width * 0.035);
    _star(canvas, Offset(cx + size.width * 0.38, cy + size.height * 0.05), size.width * 0.028);
  }

  void _star(Canvas canvas, Offset c, double r) {
    final p = Paint()..color = const Color(0xFF9DBCF3);
    final path = Path();
    for (var i = 0; i < 8; i++) {
      final a = i * 3.14159 / 4;
      final rr = i.isEven ? r : r * 0.45;
      final x = c.dx + rr * _cos(a);
      final y = c.dy + rr * _sin(a);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, p);
  }

  double _cos(double a) => a < 1.58 ? 1 - a * a / 2 : (a < 4.71 ? -1 + (a - 3.14) * (a - 3.14) / 2 : 1);
  double _sin(double a) => _cos(a - 1.5708);

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 问事空态：插画 + 引导文案，不留大面积空白。
class AfuChatEmptyView extends StatelessWidget {
  final VoidCallback? onSampleTap;
  const AfuChatEmptyView({super.key, this.onSampleTap});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AfuAssistantMoon(size: 160),
            const SizedBox(height: 20),
            const Text('有什么可以帮您？', style: AfuElderText.appTitle, textAlign: TextAlign.center),
            const SizedBox(height: 10),
            const Text(
              '查药、看报告、问症状\n在下方输入问题，或长按话筒说话',
              style: AfuElderText.secondary,
              textAlign: TextAlign.center,
            ),
            if (onSampleTap != null) ...[
              const SizedBox(height: 18),
              AfuPressable(
                onTap: onSampleTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  decoration: BoxDecoration(
                    color: AfuColors.primarySoft,
                    borderRadius: BorderRadius.circular(AfuRadius.button),
                  ),
                  child: const Text('试试：感冒了能吃阿莫西林吗', style: TextStyle(fontSize: 18, color: AfuColors.primaryDeep)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 顶部提示信息卡：大圆角、柔和浅阴影、内边距充足。
class AfuTipCard extends StatelessWidget {
  final String text;
  final IconData icon;
  final VoidCallback? onTap;
  const AfuTipCard({super.key, required this.text, this.icon = Icons.shield_outlined, this.onTap});

  @override
  Widget build(BuildContext context) {
    final card = Container(
      margin: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: AfuColors.card,
        borderRadius: BorderRadius.circular(AfuRadius.card),
        border: Border.all(color: AfuColors.line),
        boxShadow: [
          BoxShadow(color: AfuColors.primary.withOpacity(0.08), blurRadius: 16, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(color: AfuColors.primarySoft, shape: BoxShape.circle),
            child: Icon(icon, size: 26, color: AfuColors.primaryDeep),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: AfuElderText.secondary)),
          if (onTap != null) const Icon(Icons.chevron_right, color: AfuColors.secondary),
        ],
      ),
    );
    if (onTap == null) return card;
    return AfuPressable(onTap: onTap, child: card);
  }
}
