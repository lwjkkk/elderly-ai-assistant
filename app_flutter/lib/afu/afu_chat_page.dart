import 'package:flutter/material.dart';

import 'afu_theme.dart';
import 'afu_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import '../services/api.dart';

/// 图片资源说明：
/// - 欢迎卡助手形象：assets/assistant.png（透明底全身像，pubspec.yaml 已注册）
/// - AI 消息头像：assets/assistant_face.png（脸部特写，pubspec.yaml 已注册）

const _kDeep = Color(0xFF345C87);
const _kBright = Color(0xFF345C87);
const _kInk = Color(0xFF212936);
const _kSub = Color(0xFF6B7280);
const _kBubbleAi = Color(0xFFEDF4FB);

/// 消息模型：纯展示用。
class AfuMessage {
  final String text;
  final bool isMe;
  final bool thinking;
  const AfuMessage({required this.text, required this.isMe, this.thinking = false});
}

/// 一级 Tab【问事】AI 问答主页（纯 UI，不调接口）。
class AfuElderChatPage extends StatefulWidget {
  final List<AfuMessage> messages;
  final bool busy;
  final double textScale;
  final ValueChanged<String> onSend;
  final VoidCallback onVoiceStart;
  final VoidCallback onVoiceEnd;
  final VoidCallback onToggleTextScale;
  final Widget? header;
  final TextEditingController? inputController;
  final ValueChanged<int>? onQuickEntry;
  final VoidCallback? onTipMore;

  const AfuElderChatPage({
    super.key,
    required this.messages,
    required this.onSend,
    required this.onVoiceStart,
    required this.onVoiceEnd,
    required this.onToggleTextScale,
    this.inputController,
    this.onQuickEntry,
    this.onTipMore,
    this.busy = false,
    this.textScale = 1.0,
    this.header,
  });

  @override
  State<AfuElderChatPage> createState() => _AfuElderChatPageState();
}

class _AfuElderChatPageState extends State<AfuElderChatPage> {
  final _innerInput = TextEditingController();
  TextEditingController get _input => widget.inputController ?? _innerInput;
  final _list = ScrollController();

  @override
  void initState() {
    super.initState();
    _maybePrivacy();
  }

  Future<void> _maybePrivacy() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('privacy_ok_v1') == true) return;
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const _PrivacyDialog(),
      );
      prefs.setBool('privacy_ok_v1', true);
    });
  }

  @override
  void didUpdateWidget(AfuElderChatPage old) {
    super.didUpdateWidget(old);
    if (widget.messages.length != old.messages.length) _scrollToBottom();
  }

  @override
  void dispose() {
    _innerInput.dispose();
    _list.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_list.hasClients) return;
      _list.animateTo(_list.position.maxScrollExtent, duration: AfuMotion.bubbleIn, curve: Curves.easeOutCubic);
    });
  }

  void _submit() {
    final t = _input.text.trim();
    if (t.isEmpty || widget.busy) return;
    _input.clear();
    widget.onSend(t);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: Colors.transparent,
        // 全局规则：不再保留页面顶部黑色标题（字号调节已移到「个人中心」）
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFF7FAFD), Color(0xFFF7FAFD)],
            ),
          ),
          child: Column(
            children: [
              if (widget.header != null) widget.header!,
              Expanded(
                child: widget.messages.isEmpty
                    ? SingleChildScrollView(
                        child: Column(children: [
                          _TipCard(onMore: widget.onTipMore),
                          const _WelcomeCard(),
                          _FuncCards(onTap: (i) => widget.onQuickEntry?.call(i)),
                          const SizedBox(height: 8),
                        ]),
                      )
                    : ListView.builder(
                        controller: _list,
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                        itemCount: widget.messages.length,
                        itemBuilder: (c, i) {
                          final m = widget.messages[i];
                          if (m.thinking) return const _ThinkingRow();
                          return m.isMe ? _UserRow(text: m.text) : _AiRow(text: m.text);
                        },
                      ),
              ),
              _InputBar(
                controller: _input,
                busy: widget.busy,
                onSubmit: _submit,
                onVoiceStart: widget.onVoiceStart,
                onVoiceEnd: widget.onVoiceEnd,
              ),
            ],
          ),
        ),
    );
  }
}

/// 隐私说明弹窗：首次进入问事页弹出一次，确认后不再打扰。
class _PrivacyDialog extends StatelessWidget {
  const _PrivacyDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFFEDF4FB),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: Color(0xFFD8E6F3)),
      ),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 72,
          height: 72,
          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          child: const Icon(Icons.shield_outlined, size: 40, color: Color(0xFF345C87)),
        ),
        const SizedBox(height: 16),
        const Text('隐私保护说明',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: _kInk)),
        const SizedBox(height: 10),
        const Text('对话已开启隐私保护，您的提问仅用于本次解答',
            style: TextStyle(fontSize: 19, color: _kSub, height: 1.5),
            textAlign: TextAlign.center),
      ]),
      actions: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF345C87),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
        ),
      ],
    );
  }
}

/// 今日健康小贴士卡：有未服用的药就显示用药提醒，否则显示天气与穿衣建议。
/// 小贴士当前是否在显示天气（是则问事页隐藏天气卡，避免重复）。
final tipIsWeather = ValueNotifier<bool>(false);

class _TipCard extends StatefulWidget {
  final VoidCallback? onMore;
  const _TipCard({this.onMore});
  @override
  State<_TipCard> createState() => _TipCardState();
}

class _TipCardState extends State<_TipCard> {
  late final Future<String?> _future = _load();

  static Future<String?> _load() async {
    try {
      tipIsWeather.value = false;
      final meds = await ApiService.medsToday();
      for (final m in meds) {
        final map = m is Map ? Map<String, dynamic>.from(m as Map) : <String, dynamic>{};
        final name = (map['name'] ?? '').toString();
        final slots = map['slots'] is List ? List.from(map['slots']) : [];
        for (final s in slots) {
          final sm = s is Map ? Map<String, dynamic>.from(s as Map) : <String, dynamic>{};
          if ((sm['status'] ?? 'pending').toString() == 'pending' && name.isNotEmpty) {
            final slot = (sm['slot'] ?? '').toString();
            return '今日用药提醒：$name，${slot.isEmpty ? '按时' : slot}服用，请不要随意停药。';
          }
        }
      }
    } catch (_) {}
    try {
      Map<String, dynamic>? d;
      try {
        var perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied) {
          perm = await Geolocator.requestPermission();
        }
        if (perm == LocationPermission.whileInUse || perm == LocationPermission.always) {
          final pos = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.low,
            timeLimit: const Duration(seconds: 8),
          );
          d = await ApiService.weatherRemind(lat: pos.latitude, lon: pos.longitude);
        }
      } catch (_) {}
      d ??= await ApiService.weatherRemind(city: '武汉');
      final raw = '${d['text'] ?? ''} ${d['tip'] ?? ''}';
      if (raw.contains('未配置') || raw.contains('API_KEY')) return null;
      tipIsWeather.value = true;
      final text = (d['text'] ?? '').toString();
      final tip = (d['tip'] ?? '').toString();
      final body = (text + '，' + tip).trim().replaceAll(RegExp('^，|，\$'), '');
      if (body.isNotEmpty) return '今日天气：$body';
    } catch (_) {}
    return '今日小贴士：降压药建议固定时间服用，不要随意停药。';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _future,
      builder: (c, s) {
        if (s.connectionState == ConnectionState.waiting) {
          return _TipBody(text: '正在加载今日小贴士…', onMore: widget.onMore);
        }
        if (s.data == null) return const SizedBox.shrink();
        return _TipBody(text: s.data!, onMore: widget.onMore);
      },
    );
  }

}

class _TipBody extends StatelessWidget {
  final String text;
  final VoidCallback? onMore;
  const _TipBody({required this.text, this.onMore});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 10, 20, 6),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD8E6F3)),
        boxShadow: [BoxShadow(color: _kDeep.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Column(children: [
        Row(children: [
          Container(
            width: 46,
            height: 46,
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            child: const Icon(Icons.lightbulb_outline, size: 28, color: Color(0xFF345C87)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 19, color: _kInk, height: 1.45)),
          ),
        ]),
        Align(
          alignment: Alignment.bottomRight,
          child: TextButton(
            onPressed: onMore,
            child: const Text('查看更多', style: TextStyle(fontSize: 18, color: _kDeep)),
          ),
        ),
      ]),
    );
  }
}
/// 快捷功能区：仅保留【体征】【报告】两张卡片。
/// 卡片样式：左上角圆形图标 + 右侧两字标题 + 标题下方灰色小字说明，无底部装饰图。
/// 查药 / 自查 / 咨询不再做独立卡片入口，统一由 AI 对话完成。
class _FuncCards extends StatelessWidget {
  final ValueChanged<int> onTap; // 0=体征 1=报告
  const _FuncCards({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
      child: Column(children: [
        _funcCard(
          icon: Icons.show_chart_outlined,
          title: '体征',
          desc: '记录血压、血糖、心率、体重',
          tint: const Color(0xFFEDF4FB),
          main: const Color(0xFF345C87),
          onTap: () => onTap(0),
        ),
        const SizedBox(height: 16),
        _funcCard(
          icon: Icons.description_outlined,
          title: '报告',
          desc: '上传体检单，智能读懂结果',
          tint: const Color(0xFFEDF4FB),
          main: const Color(0xFF345C87),
          onTap: () => onTap(1),
        ),
      ]),
    );
  }

  Widget _funcCard({
    required IconData icon,
    required String title,
    required String desc,
    required Color tint,
    required Color main,
    required VoidCallback onTap,
  }) {
    return AfuPressable(
      onTap: onTap,
      borderRadius: 24,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFD8E6F3)),
          boxShadow: [
            BoxShadow(
                color: _kDeep.withOpacity(0.06),
                blurRadius: 12,
                offset: const Offset(0, 4)),
          ],
        ),
        child: Row(children: [
          // 左上角圆形图标
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
            child: Icon(icon, size: 32, color: main),
          ),
          const SizedBox(width: 16),
          // 右侧两字标题 + 标题下方灰色小字说明
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: _kInk)),
                  const SizedBox(height: 6),
                  Text(desc,
                      style:
                          const TextStyle(fontSize: 17, color: _kSub, height: 1.4)),
                ]),
          ),
        ]),
      ),
    );
  }
}
/// 空态欢迎卡：AI 助手形象 + 引导文字（推荐问题小卡片已移除）。
class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 26),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFEDF4FB), Color(0xFFFFFFFF)],
          ),
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
                color: _kDeep.withOpacity(0.10),
                blurRadius: 16,
                offset: const Offset(0, 6)),
          ],
        ),
        child: Column(children: [
          // AI 助手形象
          Container(
            width: 128,
            height: 128,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.95),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 4)),
              ],
            ),
            padding: const EdgeInsets.all(6),
            child: ClipOval(
                child: Image.asset('assets/assistant.png', fit: BoxFit.cover)),
          ),
          const SizedBox(height: 18),
          const Text('有什么可以帮您？',
              style: TextStyle(
                  fontSize: 26, fontWeight: FontWeight.w800, color: _kInk)),
          const SizedBox(height: 8),
          // 引导文字
          const Text('查药、看报告、问症状，我来陪您一起弄清楚。',
              style: TextStyle(fontSize: 19, color: _kSub, height: 1.5),
              textAlign: TextAlign.center),
        ]),
      ),
    );
  }
}
class _AiRow extends StatefulWidget {
  final String text;
  const _AiRow({required this.text});
  @override
  State<_AiRow> createState() => _AiRowState();
}

class _AiRowState extends State<_AiRow> {
  static const _limit = 300;
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AfuMotion.bubbleIn,
      curve: Curves.easeOutCubic,
      builder: (context, v, child) =>
          Opacity(opacity: v, child: Transform.translate(offset: Offset(0, 10 * (1 - v)), child: child)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const CircleAvatar(
            radius: 20,
            backgroundColor: Colors.white,
            backgroundImage: AssetImage('assets/assistant_face.png'),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Container(
              margin: const EdgeInsets.only(right: 48),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: _kBubbleAi,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFD8E6F3)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  !_open && widget.text.length > _limit
                      ? '${widget.text.substring(0, _limit)}……'
                      : widget.text,
                  style: const TextStyle(fontSize: 19, color: _kInk, height: 1.5),
                ),
                if (widget.text.length > _limit)
                  GestureDetector(
                    onTap: () => setState(() => _open = !_open),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_open ? '收起 ▲' : '展开全文 ▼',
                          style: const TextStyle(fontSize: 18, color: _kDeep)),
                    ),
                  ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

/// 用户行：右侧蓝色气泡。
class _UserRow extends StatelessWidget {
  final String text;
  const _UserRow({required this.text});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AfuMotion.bubbleIn,
      curve: Curves.easeOutCubic,
      builder: (context, v, child) =>
          Opacity(opacity: v, child: Transform.translate(offset: Offset(0, 10 * (1 - v)), child: child)),
      child: Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(left: 48, top: 6, bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: _kDeep,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: _kDeep.withOpacity(0.12), blurRadius: 8, offset: const Offset(0, 3))],
          ),
          child: Text(text, style: const TextStyle(fontSize: 19, color: Colors.white, height: 1.5)),
        ),
      ),
    );
  }
}

class _ThinkingRow extends StatelessWidget {
  const _ThinkingRow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        const CircleAvatar(
          radius: 20,
          backgroundColor: Colors.white,
          backgroundImage: AssetImage('assets/assistant_face.png'),
        ),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: _kBubbleAi,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFD8E6F3)),
          ),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
                width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 3, color: _kDeep)),
            SizedBox(width: 12),
            Text('正在思考…', style: TextStyle(fontSize: 18, color: _kSub)),
          ]),
        ),
      ]),
    );
  }
}

/// 底部悬浮输入栏：胶囊输入框 + 话筒 + 圆形发送。
class _InputBar extends StatefulWidget {
  final TextEditingController controller;
  final bool busy;
  final VoidCallback onSubmit;
  final VoidCallback onVoiceStart;
  final VoidCallback onVoiceEnd;
  const _InputBar({
    required this.controller,
    required this.busy,
    required this.onSubmit,
    required this.onVoiceStart,
    required this.onVoiceEnd,
  });

  @override
  State<_InputBar> createState() => _InputBarState();
}

class _InputBarState extends State<_InputBar> {
  bool _holding = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 18),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [BoxShadow(color: _kDeep.withOpacity(0.08), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Row(children: [
        GestureDetector(
          onLongPressStart: (_) {
            setState(() => _holding = true);
            widget.onVoiceStart();
          },
          onLongPressEnd: (_) {
            setState(() => _holding = false);
            widget.onVoiceEnd();
          },
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _holding ? const Color(0xFFE57373) : const Color(0xFFEDF4FB),
            ),
            child: Icon(_holding ? Icons.mic : Icons.mic_none, size: 30, color: _holding ? Colors.white : const Color(0xFF345C87)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Focus(
            onFocusChange: (f) => setState(() => _focused = f),
            child: TextField(
              controller: widget.controller,
              minLines: 1,
              maxLines: 4,
              style: const TextStyle(fontSize: 19, color: _kInk),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => widget.onSubmit(),
              decoration: InputDecoration(
                hintText: '请输入问题，长按话筒可说话',
                hintStyle: const TextStyle(fontSize: 18, color: _kSub),
                filled: true,
                fillColor: const Color(0xFFFFFFFF),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                  borderSide: const BorderSide(color: Color(0xFFD8E6F3)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                  borderSide: const BorderSide(color: Color(0xFFD8E6F3)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                  borderSide: const BorderSide(color: _kBright, width: 2.5),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        AfuPressable(
          onTap: widget.busy ? null : widget.onSubmit,
          borderRadius: 28,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.busy ? const Color(0xFF6B7280) : _kDeep,
              boxShadow: widget.busy
                  ? null
                  : [BoxShadow(color: _kDeep.withOpacity(0.14), blurRadius: 8, offset: const Offset(0, 3))],
            ),
            child: widget.busy
                ? const Padding(
                    padding: EdgeInsets.all(17),
                    child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
                  )
                : const Icon(Icons.send, size: 28, color: Colors.white),
          ),
        ),
      ]),
    );
  }
}
