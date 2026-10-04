import 'package:flutter/material.dart';

import 'afu_theme.dart';

/// 按压缩放 + Material 水波纹：包住任何内容即得 0.96 按压反馈。
class AfuPressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double borderRadius;
  const AfuPressable({super.key, required this.child, this.onTap, this.borderRadius = AfuRadius.card});

  @override
  State<AfuPressable> createState() => _AfuPressableState();
}

class _AfuPressableState extends State<AfuPressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.onTap == null ? null : (_) => setState(() => _down = true),
      onTapUp: widget.onTap == null ? null : (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      child: AnimatedScale(
        scale: _down ? AfuMotion.pressScale : 1.0,
        duration: const Duration(milliseconds: 120),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(widget.borderRadius),
          child: InkWell(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            onTap: widget.onTap,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// 对话气泡：淡入 + 轻微上滑 300ms，无弹跳旋转。
class AfuBubble extends StatelessWidget {
  final String text;
  final bool isMe;
  final bool elder;
  const AfuBubble({super.key, required this.text, required this.isMe, this.elder = true});

  @override
  Widget build(BuildContext context) {
    final style = (elder ? AfuElderText.body : AfuFamilyText.body).copyWith(
      color: isMe ? Colors.white : AfuColors.ink,
    );
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AfuMotion.bubbleIn,
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, 10 * (1 - v)), child: child),
      ),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isMe) ...[
              const CircleAvatar(
                radius: 16,
                backgroundColor: AfuColors.primarySoft,
                backgroundImage: AssetImage('assets/assistant_face.png'),
              ),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * (elder ? 0.8 : 0.75)),
          decoration: BoxDecoration(
            color: isMe ? AfuColors.primary : AfuColors.bubbleAi,
            borderRadius: BorderRadius.circular(AfuRadius.bubble),
            border: isMe ? null : Border.all(color: AfuColors.line),
          ),
          child: Text(text, style: style),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 思考中气泡：转圈 + 文案。
class AfuThinkingBubble extends StatelessWidget {
  final String text;
  const AfuThinkingBubble({super.key, this.text = '正在思考…'});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: AfuColors.bubbleAi,
          borderRadius: BorderRadius.circular(AfuRadius.bubble),
          border: Border.all(color: AfuColors.line),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 3, color: AfuColors.primary),
          ),
          const SizedBox(width: 12),
          Text(text, style: AfuElderText.secondary),
        ]),
      ),
    );
  }
}

/// 平缓骨架屏：慢速正弦渐变，无闪烁。
class AfuSkeleton extends StatefulWidget {
  final double width;
  final double height;
  final double radius;
  const AfuSkeleton({super.key, required this.width, required this.height, this.radius = 12});

  @override
  State<AfuSkeleton> createState() => _AfuSkeletonState();
}

class _AfuSkeletonState extends State<AfuSkeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: AfuMotion.skeletonPeriod)..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = (0.5 + 0.5 * (_c.value * 2 - 1).abs());
        final base = Color.lerp(const Color(0xFFE9EDF5), const Color(0xFFF4F6FB), t)!;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(color: base, borderRadius: BorderRadius.circular(widget.radius)),
        );
      },
    );
  }
}

/// 250ms 淡入页面切换。
Route<T> afuFadeRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: AfuMotion.pageFade,
    reverseTransitionDuration: AfuMotion.pageFade,
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
  );
}

/// 长辈端大按钮：高 60，大圆角，整行撑满。
class AfuBigButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  const AfuBigButton({super.key, required this.label, this.onPressed, this.loading = false});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        child: loading
            ? const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
              )
            : Text(label),
      ),
    );
  }
}

/// 柔和风信息卡：白底、大圆角、细边框、无阴影。
class AfuCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  const AfuCard({super.key, required this.child, this.padding = const EdgeInsets.all(18), this.onTap});

  @override
  Widget build(BuildContext context) {
    final card = Card(margin: EdgeInsets.zero, child: Padding(padding: padding, child: child));
    if (onTap == null) return card;
    return AfuPressable(onTap: onTap, child: card);
  }
}

/// 空态：大留白 + 一句说明。
class AfuEmptyView extends StatelessWidget {
  final String text;
  const AfuEmptyView({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Center(child: Text(text, style: AfuElderText.secondary, textAlign: TextAlign.center)),
    );
  }
}
