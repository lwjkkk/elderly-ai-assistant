import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../afu/afu_theme.dart';
import '../../afu/afu_widgets.dart';
import '../../services/api.dart';
import 'consult_drug_chat_tab.dart';
import 'med_form.dart';
import 'hub_pages.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cross_file/cross_file.dart';
import '../../services/file_download.dart';
/// 全局色彩规范（本人视图与绑定长辈视图共用，身份区分靠顶部切换文字）。
const _kPrimary = Color(0xFF4080FF);
const _kText = Color(0xFF333333);
const _kSub = Color(0xFF888888);
const _kPage = Color(0xFFF7F8FA);
const _kLine = Color(0xFFE5E7EB);
const _kDanger = Color(0xFFF53F3F);

/// 主按钮样式（#4080FF 实心白字）。
ButtonStyle _primaryBtn() => ElevatedButton.styleFrom(
      backgroundColor: _kPrimary,
      foregroundColor: Colors.white,
      textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
    );

/// 暖心按钮样式（仅一键发送暖心用药提醒用）：暖橙实心白字。
ButtonStyle _warmBtn() => ElevatedButton.styleFrom(
      backgroundColor: _eMed,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      padding: const EdgeInsets.symmetric(vertical: 16),
      textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
    );

/// 本人 4 内页主题色（取自总览首页对应功能卡片色，降低透明度使用）。
// 本人 4 内页按钮/底色条/空态图标色（首页卡片色）。
const _mMed = Color(0xFF6FAE86);
const _mMedBg = Color(0xFFDDF0E5);
const _mVit = Color(0xFF7C6FB5);
const _mVitBg = Color(0xFFEDE7F6);
const _mRep = Color(0xFF5FA9A6);
const _mRepBg = Color(0xFFDDF2F0);
const _mCon = Color(0xFFC66666);
const _mConBg = Color(0xFFFBE7E7);
// 绑定长辈 6 页色板（卡片提取色）。
const _eDrug = AfuColors.primaryDeep;
const _eDrugBg = Color(0xFFE8EFFD);
const _eMed = Color(0xFF73B88F);
const _eMedBg = Color(0xFFE2F2E8);
const _eVit = Color(0xFF9078BC);
const _eVitBg = Color(0xFFEDE6F6);
const _eSelf = Color(0xFFE0B57A);
const _eSelfBg = Color(0xFFFBF1D6);
const _eRep = Color(0xFF71B3A9);
const _eRepBg = Color(0xFFE2F2F0);
const _eCon = Color(0xFFD48792);
const _eConBg = Color(0xFFF9E7E9);
const _kSub2 = Color(0xFF666666);
const _kZebra = Color(0xFFF9F9F9);
const _kRowDiv = Color(0xFFEEEEEE);
const _kTap = Color(0xFFF2F2F2);

/// 淡色主题按钮（背景主题色低透明，文字主题色实色，单行不折行）。
ButtonStyle _tintBtn(Color main, Color bg) => ElevatedButton.styleFrom(
      backgroundColor: bg,
      foregroundColor: main,
      shadowColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      padding: const EdgeInsets.symmetric(vertical: 15),
      textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
    );

/// 表格文字格（自动换行，表头加粗）。
Widget _tCell(String s, {bool head = false, Color? color, int? maxLines}) =>
    Padding(
      padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 6),
      child: Text(s,
          maxLines: maxLines,
          style: TextStyle(
              fontSize: 17,
              fontWeight: head ? FontWeight.w700 : FontWeight.w400,
              color: color ?? _kText,
              height: 1.45)),
    );

/// 统一表格：无背景底色，仅浅灰细线；表头 #333；无数据时在容器内居中展示图标+文案。
class _MineTable extends StatelessWidget {
  final List<String> headers;
  final List<int> flex;
  final List<List<Widget>> rows;
  final IconData emptyIcon;
  final Color emptyAccent;
  final String emptyText;
  const _MineTable({
    required this.headers,
    required this.flex,
    required this.rows,
    required this.emptyIcon,
    required this.emptyAccent,
    required this.emptyText,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border.all(color: _kLine),
        borderRadius: BorderRadius.circular(14),
      ),
      child: rows.isEmpty
          ? SizedBox(
              height: 220,
              child: Center(
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(emptyIcon, size: 56, color: emptyAccent),
                      const SizedBox(height: 12),
                      Text(emptyText,
                          style: const TextStyle(
                              fontSize: 18, color: _kSub, height: 1.6),
                          textAlign: TextAlign.center),
                    ]),
              ),
            )
          : Table(
              border: const TableBorder(
                  horizontalInside: BorderSide(color: _kLine)),
              columnWidths: {
                for (var i = 0; i < flex.length; i++)
                  i: FlexColumnWidth(flex[i].toDouble()),
              },
              children: [
                TableRow(
                    children: [for (final h in headers) _tCell(h, head: true)]),
                for (final r in rows) TableRow(children: r),
              ],
            ),
    );
  }
}

/// 表格列定义：标题（强制单行）/ 弹性占比 / 是否靠右。
class _ECol {
  final String label;
  final int flex;
  final bool right;
  const _ECol(this.label, this.flex, {this.right = false});
}

/// 日期简写 MM-DD（时间列固定窄宽）。
String _md(String s) => s.length >= 10 ? s.substring(5, 10) : s;

/// 表头吸顶委托：功能浅底色，15px 加粗 #333，单行。
class _EHeadDelegate extends SliverPersistentHeaderDelegate {
  final Color tint;
  final List<_ECol> cols;
  const _EHeadDelegate(this.tint, this.cols);
  @override
  double get minExtent => 52;
  @override
  double get maxExtent => 52;
  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: tint,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        for (final c in cols)
          Expanded(
            flex: c.flex,
            child: Text(c.label,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                textAlign: c.right ? TextAlign.right : TextAlign.left,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _kText)),
          ),
      ]),
    );
  }

  @override
  bool shouldRebuild(covariant _EHeadDelegate old) =>
      old.tint != tint || old.cols != cols;
}

/// 表格行：高 52，斑马纹，点击 #F2F2F2 反馈，底部 #EEEEEE 分割线，无竖线。
/// 小勾选点：28px 黑色圆圈，选中实心 + 白勾，用于行内单选。
class _SelDot extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;
  const _SelDot({required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected ? _kText : Colors.transparent,
            border: Border.all(color: _kText, width: 2),
          ),
          child: selected
              ? const Icon(Icons.check,
                  size: 13, color: Colors.white)
              : null,
        ),
      ),
    );
  }
}

/// 通用单选记录底部面板：标题 + 勾选列表 + 取消 / 发送。
/// 返回选中下标；点取消或未选中返回 null。
Future<int?> _pickOneRecord(
  BuildContext context, {
  required String title,
  required List<String> labels,
  required ButtonStyle sendStyle,
}) async {
  var sel = -1;
  return showModalBottomSheet<int>(
    context: context,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(24))),
    builder: (c) => StatefulBuilder(
      builder: (c, setP) => SafeArea(
        child: Padding(
          padding:
              const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    color: _kText)),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: labels.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: 8),
                itemBuilder: (_, i) => AfuPressable(
                  onTap: () => setP(() => sel = i),
                  borderRadius: 14,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: sel == i
                          ? const Color(0xFFEDF4FB)
                          : const Color(0xFFF7F8FA),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: sel == i
                              ? const Color(0xFF345C87)
                              : const Color(0xFFD8E6F3)),
                    ),
                    child: Row(children: [
                      _SelDot(
                          selected: sel == i,
                          onTap: () => setP(() => sel = i)),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Text(labels[i],
                              style: const TextStyle(
                                  fontSize: 18,
                                  color: _kText,
                                  height: 1.4))),
                    ]),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: SizedBox(
                  height: 54,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(c),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _kText,
                      side:
                          const BorderSide(color: _kLine),
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(18)),
                      textStyle: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700),
                    ),
                    child: const Text('取消'),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 54,
                  child: ElevatedButton.icon(
                    onPressed: sel < 0
                        ? null
                        : () => Navigator.pop(c, sel),
                    style: sendStyle,
                    icon: const Icon(Icons.send_outlined),
                    label:
                        const Text('发送', softWrap: false),
                  ),
                ),
              ),
            ]),
          ]),
        ),
      ),
    ),
  );
}

/// 列表元素兜底转 Map：后端返回结构异常时也不至于整页空白。
Map<String, dynamic> _asMap(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

/// 表格行：52 高定高 + 斑马底 + 底部线 + 按压态
class _TapRow extends StatefulWidget {
  final bool zebra;
  final VoidCallback? onTap;
  final Widget child;
  final Color div;
  const _TapRow(
      {required this.zebra,
      required this.child,
      this.onTap,
      this.div = _kRowDiv});
  @override
  State<_TapRow> createState() => _TapRowState();
}

class _TapRowState extends State<_TapRow> {
  bool _down = false;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        if (widget.onTap != null) setState(() => _down = true);
      },
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap,
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: _down ? _kTap : (widget.zebra ? _kZebra : Colors.white),
          border: Border(
              bottom: BorderSide(color: widget.div)),
        ),
        child: widget.child,
      ),
    );
  }
}

/// 单元格文字：14px #333 单行省略；次要列用 #666。
Widget _eCell(String s, {bool sub = false, bool right = false}) => Text(s,
    softWrap: false,
    overflow: TextOverflow.ellipsis,
    textAlign: right ? TextAlign.right : TextAlign.left,
    style: TextStyle(
        fontSize: 14, color: sub ? _kSub2 : _kText, height: 1.4));

/// 空状态（填充剩余区域）：功能插图（高亮主色）+ 居中 #888 文案。
class _ESliverEmpty extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final String text;
  const _ESliverEmpty(
      {required this.icon, required this.accent, required this.text});
  @override
  Widget build(BuildContext context) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 56, color: accent),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(text,
                style: const TextStyle(
                    fontSize: 17, color: _kSub, height: 1.8),
                textAlign: TextAlign.center),
          ),
        ]),
      ),
    );
  }
}

/// 一键询问老人：跳转到家人互动中与该长辈的聊天界面，
/// 自动把当前业务记录发送到对话里，输入框预填对应提示词（可直接发送或编辑）。
Future<void> _askElder(BuildContext context,
    {required String record, required String prompt}) async {
  try {
    final binds = await ApiService.bindList();
    String? name;
    String? key;
    var idx = 0;
    for (final b in binds) {
      final m =
          b is Map ? Map<String, dynamic>.from(b as Map) : <String, dynamic>{};
      if ((m['status'] ?? '').toString() == 'active') {
        name = (m['other_nickname'] ??
                m['nickname'] ??
                m['elder_nickname'] ??
                '长辈')
            .toString();
        key = 'family_chat_${name}_$idx';
        break;
      }
      idx++;
    }
    if (name == null || key == null) throw Exception('no bind');
    if (context.mounted) {
      await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => FamConversationPage(
              name: name!,
              storeKey: key!,
              prefill: prompt,
              autoText: record)));
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('跳转失败：${ApiService.friendly(e)}')));
    }
  }
}

/// 消息推送：后端暂无消息推送接口，先写入本地家人对话
/// （家属/长辈在“去对话”中可见），推送接口就绪后替换为服务端调用。
Future<void> _pushFamilyMsg(BuildContext context, String text) async {
  try {
    final binds = await ApiService.bindList();
    String? key;
    var idx = 0;
    for (final b in binds) {
      final m =
          b is Map ? Map<String, dynamic>.from(b as Map) : <String, dynamic>{};
      final active = (m['status'] ?? '').toString() == 'active';
      final name = (m['other_nickname'] ??
              m['nickname'] ??
              m['elder_nickname'] ??
              m['family_nickname'] ??
              '对方')
          .toString();
      if (active) {
        key = 'family_chat_${name}_$idx';
        break;
      }
      idx++;
    }
    if (key == null) throw Exception('no bind');
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    final list =
        (raw == null || raw.isEmpty) ? [] : List.from(jsonDecode(raw));
    list.add({
      'isMe': true,
      'kind': 'text',
      'text': text,
      'title': '',
      'lines': [],
      'image': '',
      'dur': 0,
    });
    await prefs.setString(key, jsonEncode(list));
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已发送，可在去对话中查看')));
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('发送失败：${ApiService.friendly(e)}')));
    }
  }
}

class HealthOverviewTab extends StatefulWidget {
  final String role;
  const HealthOverviewTab({super.key, this.role = 'elder'});
  @override
  State<HealthOverviewTab> createState() => _HealthOverviewTabState();
}


class _HealthOverviewTabState extends State<HealthOverviewTab> {
  int _elderId = 0;
  String _elderName = '';
  List _binds = [];
  // 当前展示的健康模块：0总览卡片 1体征 2报告 3用药。
  // 顶部横排标签已移除，改由下方功能卡片点击切换。
  int mod = 0;
  // 家属端身份切换：true=看绑定长辈（自动同步），false=看本人（手动上传）。
  bool showElder = true;

  @override
  void initState() {
    super.initState();
    _loadBinds();
  }

/// 家属端：读取已绑定长辈列表，默认选中首个（与接口 elder_id 规则一致）。
  Future<void> _loadBinds() async {
    if (widget.role != 'family') return;
    try {
      final binds = await ApiService.bindList();
      final list = <Map<String, dynamic>>[];
      for (final b in binds) {
        final m = b is Map
            ? Map<String, dynamic>.from(b as Map)
            : <String, dynamic>{};
        if ((m['status'] ?? '').toString() != 'active') continue;
        final eid = (m['elder_id'] as num?)?.toInt() ?? 0;
        if (eid == 0) continue;
        list.add({
          'elder_id': eid,
          'name': (m['other_nickname'] ??
                  m['nickname'] ??
                  m['elder_nickname'] ??
                  '长辈')
              .toString(),
        });
      }
      if (!mounted) return;
      setState(() {
        _binds = list;
        if (list.isNotEmpty) {
          _elderId = list.first['elder_id'] as int;
          _elderName = list.first['name'].toString();
        }
      });
    } catch (_) {}
  }

  /// 长辈选择卡片点击：底部面板单选已绑定长辈，切换后整页数据刷新。
  Future<void> _pickElder() async {
    if (widget.role != 'family') return;
    int tmp = _elderId;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(24))),
      builder: (c) => StatefulBuilder(
        builder: (c, setP) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text('选择长辈',
                  style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      color: _kText)),
            ),
            if (_binds.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 12, 20, 28),
                child: Text('暂无绑定长辈，请先去绑定',
                    style: TextStyle(
                        fontSize: 19, color: _kSub)),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding:
                      const EdgeInsets.fromLTRB(12, 4, 12, 20),
                  children: [
                    for (final b in _binds)
                      _ElderPickTile(
                        name: (b['name'] ?? '').toString(),
                        selected:
                            tmp == (b['elder_id'] as int),
                        onTap: () =>
                            setP(() => tmp = b['elder_id'] as int),
                      ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: tmp == 0
                      ? null
                      : () => Navigator.pop(c, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF345C87),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(18)),
                  ),
                  child: const Text('确定',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
    if (ok == true && tmp != 0 && tmp != _elderId) {
      await ApiService.setElderId(tmp);
      if (!mounted) return;
      setState(() {
        _elderId = tmp;
        _elderName = _binds
            .firstWhere((b) =>
                (b as Map)['elder_id'] == tmp)['name']
            .toString();
        mod = 0;
      });
    }
  }

  @override
  void dispose() {
    // 离开总览页时恢复 Tab 默认色
    if (HubNav.accent.value != null) HubNav.accent.value = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 数据来源：长辈端 mine=true（自己的记录，含后端从 AI 对话自动总结的数据）；
    // 家属端看长辈 mine=false（ApiService 自动带 elder_id 拉取）；
    // 家属端看本人 mine=true（手动上传模式）。
    // 注意：家属本人模式后端暂无独立存储，列表接口可能返回空或报错，属后端能力限制。
    final mine = widget.role != 'family' || !showElder;
    // 本人视图：仅家属端切到本人时进入；绑定长辈视图与长辈端逻辑原样不变
    final mineView = widget.role == 'family' && !showElder;
    // Tab 高亮：本人内页用本人同系色，长辈栈内页用长辈同系色（post-frame 避免 build 内 setState）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Color? c;
      if (mineView && mod != 0) {
        c = _mineAccent();
      } else if (widget.role == 'family' && !mineView && mod != 0) {
        c = mod == 1
            ? _eVit
            : (mod == 2
                ? _eRep
                : (mod == 3
                    ? _eMed
                    : (mod == 4
                        ? _eSelf
                        : (mod == 5 ? _eCon : _eDrug))));
      }
      if (HubNav.accent.value != c) HubNav.accent.value = c;
    });
    return Expanded(
      child: Column(children: [
        // 本人 4 内页：移除身份切换，左上单行文字返回
        if (mineView && mod != 0)
          _mineBackBar()
        // 绑定长辈内页：移除身份切换，左上返回箭头 + 页面标题
        else if (widget.role == 'family' && !mineView && mod != 0)
          _elderBackBar(_elderTitle(mod))
        else ...[
          // 家属端身份切换：本人 / 绑定长辈
          if (widget.role == 'family') _roleSwitch(),
          // 子页面返回栏：点卡片进入子模块后，可一键返回健康总览主页
          if (mod != 0) _backBar(),
        ],
        Expanded(
          child: IndexedStack(
            index: mod,
            key: ValueKey('hub-$mine-$mod-$mineView'),
            children: mineView
                // 本人视图：仅用药/体征/报告/咨询 4 卡（无查药/自查入口）
                ? [
                    _ElderDigest(
                        onModule: (i) => setState(() => mod = i),
                        mine: mine,
                        compact: true),
                    _MineMedsPage(key: ValueKey('mm-$mine')),
                    _MineVitalsPage(key: ValueKey('mv-$mine')),
                    _MineReportsPage(key: ValueKey('mr-$mine')),
                    _MineConsultsPage(key: ValueKey('mc-$mine')),
                  ]
                // 绑定长辈视图：6 个只读页（仅查看 + 消息交互，无录入上传按钮）
                : [
                    _ElderDigest(
                        onModule: (i) => setState(() => mod = i),
                        mine: mine,
                        elderName: _elderName,
                        onPickElder: _pickElder),
                    _ElderVitalsPage(key: ValueKey('ev-$mine-$_elderId')),
                    _ElderReportsPage(key: ValueKey('er-$mine-$_elderId')),
                    _ElderMedsPage(key: ValueKey('em-$mine-$_elderId')),
                    _ElderSelfcheckPage(key: ValueKey('es-$mine-$_elderId')),
                    _ElderConsultsPage(key: ValueKey('ec-$mine-$_elderId')),
                    _ElderDrugPage(key: ValueKey('ed-$mine-$_elderId')),
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
                  ? const Color(0xFFEDF4FB)
                  : const Color(0xFFFFFFFF),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: active
                        ? const Color(0xFF345C87)
                        : const Color(0xFF212936),
                  )),
              // 选中标签底部指示线（胶囊内，文字下方）
              if (active) ...[
                const SizedBox(height: 4),
                Container(
                  width: 28,
                  height: 3,
                  decoration: BoxDecoration(
                    color: const Color(0xFF345C87),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ]),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Row(children: [
        seg('本人', !showElder,
            () => setState(() { showElder = false; mod = 0; })),
        const SizedBox(width: 12),
        seg('长辈', showElder,
            () => setState(() { showElder = true; mod = 0; })),
      ]),
    );
  }

  /// 绑定长辈内页顶栏：左上返回箭头 + 页面标题（仅长辈 3 个栈内页使用；
  /// 自查/咨询/查药走 AfuSubPage 自带 AppBar 返回箭头 + 标题）。
  /// 长辈内页标题：1 体征 2 报告 3 用药 4 自查 5 咨询 6 查药。
  String _elderTitle(int m) {
    if (m == 1) return '体征';
    if (m == 2) return '报告';
    if (m == 3) return '用药';
    if (m == 4) return '自查';
    if (m == 5) return '咨询';
    return '查药';
  }

  Color _elderTint(int m) {
    if (m == 1) return _eVitBg;
    if (m == 2) return _eRepBg;
    if (m == 3) return _eMedBg;
    if (m == 4) return _eSelfBg;
    if (m == 5) return _eConBg;
    return _eDrugBg;
  }

  /// 绑定长辈内页退出区域：整块功能底色方块，完整包含返回按钮与退出文字，
  /// 距顶部留足安全距离，大触控区；点整块返回健康总览。
  Widget _elderBackBar(String title) {
    final tint = _elderTint(mod);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: AfuPressable(
          onTap: () => setState(() => mod = 0),
          borderRadius: 16,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
                color: tint, borderRadius: BorderRadius.circular(16)),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.arrow_back, size: 26, color: _kText),
              SizedBox(width: 10),
              Text('退出',
                  softWrap: false,
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: _kText)),
            ]),
          ),
        ),
      ),
    );
  }

  /// 本人内页返回键 + 低饱和主题底色条（仅本人 4 内页使用）。
  /// mod 1 用药 2 体征 3 报告 4 咨询。
  Widget _mineBackBar() {
    final strip =
        mod == 1 ? _mMedBg : (mod == 2 ? _mVitBg : (mod == 3 ? _mRepBg : _mConBg));
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: AfuPressable(
          onTap: () => setState(() => mod = 0),
          borderRadius: 16,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
                color: strip, borderRadius: BorderRadius.circular(16)),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.arrow_back, size: 26, color: _kText),
              SizedBox(width: 10),
              Text('返回',
                  softWrap: false,
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: _kText)),
            ]),
          ),
        ),
      ),
    );
  }



  /// 本人内页 Tab 高亮色：健康总览 Tab 切为功能同系色。
  Color _mineAccent() {
    if (mod == 1) return _mMed;
    if (mod == 2) return _mVit;
    if (mod == 3) return _mRep;
    return _mCon;
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
            Icon(Icons.arrow_back, size: 26, color: _kText),
            SizedBox(width: 8),
            Text('返回健康总览',
                style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: _kText)),
          ]),
        ),
      ),
    );
  }
}

/// 总览页主体：6 张正方形功能卡 + 今日小贴士。家属端原样复用此页。
/// 长辈单选项：黑色勾选点 + 姓名，选中浅蓝底。
class _ElderPickTile extends StatelessWidget {
  final String name;
  final bool selected;
  final VoidCallback onTap;
  const _ElderPickTile(
      {required this.name, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AfuPressable(
        onTap: onTap,
        borderRadius: 16,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFFEDF4FB)
                : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: selected
                    ? const Color(0xFF345C87)
                    : const Color(0xFFD8E6F3)),
          ),
          child: Row(children: [
            _SelDot(selected: selected, onTap: onTap),
            const SizedBox(width: 12),
            Expanded(
              child: Text(name,
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: _kText)),
            ),
          ]),
        ),
      ),
    );
  }
}

/// 健康总览摘要
class _ElderDigest extends StatelessWidget {
  final void Function(int) onModule;
  final bool mine;
  final bool compact;
  final String elderName;
  final VoidCallback? onPickElder;
  const _ElderDigest(
      {super.key,
      required this.onModule,
      this.mine = true,
      this.compact = false,
      this.elderName = '',
      this.onPickElder});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      children: [
        // 顶部提示卡：与现有卡片风格统一
        (mine || onPickElder == null)
          ? AfuCard(
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
          
            ]))
          : AfuCard(
              onTap: onPickElder,
              child: Row(children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: const BoxDecoration(
                      color: Color(0xFFEDF4FB),
                      shape: BoxShape.circle),
                  child: const Icon(Icons.person_outline,
                      size: 30, color: Color(0xFF345C87)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        const Text('选择长辈',
                            style: TextStyle(
                                fontSize: 16,
                                color: Color(0xFF6B7280))),
                        const SizedBox(height: 4),
                        Text(
                            elderName.isEmpty
                                ? '暂无绑定长辈'
                                : elderName,
                            style: const TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF212936))),
                      ]),
                ),
                const Icon(Icons.chevron_right,
                    size: 28, color: Color(0xFF6B7280)),
              ])),
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
            // 本人视图：仅保留用药/体征/报告/咨询 4 卡（无查药/自查入口）
            if (compact) ...[
              _mod(context, Icons.alarm_outlined, '用药', '用药提醒管理', 1,
                  const Color(0xFFDDF0E5), const Color(0xFF6FAE86), 'med'),
              _mod(context, Icons.show_chart_outlined, '体征', '体征数据记录', 2,
                  const Color(0xFFEDE7F6), const Color(0xFF7C6FB5), 'vitals'),
              _mod(context, Icons.description_outlined, '报告', '体检报告解读', 3,
                  const Color(0xFFDDF2F0), const Color(0xFF5FA9A6), 'report'),
              _mod(context, Icons.chat_bubble_outline, '咨询', '问诊录音回放', 4,
                  const Color(0xFFFBE7E7), const Color(0xFFC66666), 'chat'),
            ] else ...[
              _mod(context, Icons.medication_outlined, '\u67e5\u836f', '\u836f\u54c1\u4fe1\u606f\u67e5\u8be2', -3,
                  const Color(0xFFE8EFFD), AfuColors.primaryDeep, 'drug'),
              _mod(context, Icons.alarm_outlined, '\u7528\u836f', '\u7528\u836f\u63d0\u9192\u7ba1\u7406', 3,
                  const Color(0xFFDDF0E5), const Color(0xFF6FAE86), 'med'),
              _mod(context, Icons.show_chart_outlined, '\u4f53\u5f81', '\u4f53\u5f81\u6570\u636e\u8bb0\u5f55', 1,
                  const Color(0xFFEDE7F6), const Color(0xFF7C6FB5), 'vitals'),
              _mod(context, Icons.speed_outlined, '\u81ea\u67e5', '\u5065\u5eb7\u81ea\u6d4b\u8bc4\u4f30', -1,
                  const Color(0xFFFFF3E2), const Color(0xFFB07A2A), 'selfcheck'),
              _mod(context, Icons.description_outlined, '\u62a5\u544a', '\u4f53\u68c0\u62a5\u544a\u89e3\u8bfb', 2,
                  const Color(0xFFDDF2F0), const Color(0xFF5FA9A6), 'report'),
              _mod(context, Icons.chat_bubble_outline, '\u54a8\u8be2', '\u95ee\u8bca\u5f55\u97f3\u56de\u653e', -2,
                  const Color(0xFFFBE7E7), const Color(0xFFC66666), 'chat'),
            ],
          ],
        ),
        // 天气提醒模块：仅本人 digest 保留，绑定长辈入口页移除
        if (compact) ...[
          const SizedBox(height: 16),
          // 健康小贴士：优先用药提醒，否则展示天气 + 穿衣建议
          const _HealthTip(),
        ],
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
        // 绑定长辈视图（!mine）：进只读页；其余进原有可操作页
        if (mine) {
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
          return;
        }
        // 长辈视图：自查/咨询/查药进栈内页（mod 4/5/6），底部 Tab 常驻
        onModule(seg == -1 ? 4 : (seg == -2 ? 5 : 6));
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

  @override
  void initState() {
    super.initState();
    _load();
  }

    Future<void> _load() async {
    // 1) 优先：今日是否有用药提醒
    try {
      final meds = await ApiService.medsToday(mine: true);
      final tip = _medsTip(meds);
      if (tip != null) {
        if (mounted) {
          setState(() {
            _line = tip;
            _icon = Icons.medication_outlined;
          });
        }
        return;
      }
    } catch (_) {}
    // 2) 无用药提醒 -> 调用天气，展示温度 + 穿衣建议
    try {
      final tips = [
        '多喝温水，少喝冷饮',
        '每天散步三十分钟',
        '按时作息不熬夜',
        '饮食清淡少油盐',
        '定期测量血压血糖',
        '保持心情愉快',
      ];
      if (mounted) {
        final now = DateTime.now();
        final idx =
            now.difference(DateTime(now.year, 1, 1)).inDays %
                tips.length;
        setState(() {
          _line = '养生小常识：${tips[idx]}';
          _icon = Icons.lightbulb_outline;
        });
      }
    } catch (_) {}
  }

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
          decoration: const BoxDecoration(
              color: Color(0xFFFBF1E2), shape: BoxShape.circle),
          // 用药提醒沿用线性药瓶图标；天气态用多云太阳定制图标
          child: _icon == Icons.medication_outlined
              ? Icon(_icon,
                  size: 30, color: const Color(0xFFE0B57A))
              : const CustomPaint(
                  size: Size(36, 36), painter: _SunCloudPainter()),
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

/// ============ 本人视图 4 页：仅家属端【本人】身份使用 ============
/// 数据走现有后端接口（mine=true 手动上传模式）；绑定长辈视图不受影响。
/// 注意：家属本人模式后端暂无独立存储，部分列表接口可能返回空或报错，
/// 页面按空状态展示，不新增后端接口。

/// 本人-用药：顶部双按钮（录入安排 / 说明书拍照上传）+ 待办列表 + 详情。
class _MineMedsPage extends StatefulWidget {
  final bool forElder;
  const _MineMedsPage({super.key, this.forElder = false});
  @override
  State<_MineMedsPage> createState() => _MineMedsPageState();
}

class _MineMedsPageState extends State<_MineMedsPage> {
  List _todos = [];
  bool _loading = true;


  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final list = <Map<String, dynamic>>[];
    try {
      final meds = await ApiService.medsToday(mine: !widget.forElder);
      for (final m in meds) {
        final map =
            m is Map ? Map<String, dynamic>.from(m as Map) : <String, dynamic>{};
        final medId = (map['medication_id'] ?? map['id'] ?? 0) as num? ?? 0;
        final slots = map['slots'] is List ? List.from(map['slots']) : [];
        for (final s in slots) {
          final sm =
              s is Map ? Map<String, dynamic>.from(s as Map) : <String, dynamic>{};
          list.add({
            'medId': medId.toInt(),
            'name': (map['name'] ?? '').toString(),
            'dosage': (map['dosage'] ?? '').toString(),
            'frequency': (map['frequency'] ?? '').toString(),
            'slot': (sm['slot'] ?? '').toString(),
            'status': (sm['status'] ?? 'pending').toString(),
          });
        }
      }
    } catch (_) {}
    if (mounted) setState(() { _todos = list; _loading = false; });
  }

  /// 录入用药安排：支持选择用药开始日期。
  /// 【等待后端接口开发完成】medications 暂无开始日期字段，日期仅用于本地展示，
  /// 后端仍以服务端时间为准。
  Future<void> _openAdd({String? presetName}) async {
    final data = await showMedFormDialog(context,
        presetName: presetName);
    if (data == null) return;
    try {
      await ApiService.addMed(
        name: data['name'] as String,
        dosage: data['dosage'] as String,
        frequency: data['frequency'] as String,
        times: List<String>.from(data['times'] as List),
        mine: !widget.forElder,
      );
      await _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('保存失败：${ApiService.friendly(e)}')));
      }
    }
  }

Future<void> _pickInstruction() async {
    try {
      final f = await ImagePicker()
          .pickImage(source: ImageSource.camera, maxWidth: 1600);
      if (f == null) return;
      final bytes = await f.readAsBytes();
      final r = await ApiService.queryDrugByImage(bytes.toList());
      final ocr = (r['ocr_text'] ?? '').toString().split('\n').first.trim();
      if (!mounted) return;
      await _openAdd(presetName: ocr.isEmpty ? null : ocr);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('识别失败：${ApiService.friendly(e)}')));
      }
    }
  }

  Future<void> _detail(Map<String, dynamic> td) async {
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(td['name']?.toString().isEmpty == true ? '用药详情' : td['name'].toString(),
            style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: Color(0xFF333333))),
        content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('日期：${DateTime.now().toString().substring(0, 10)}',
                  style: const TextStyle(fontSize: 19, color: Color(0xFF333333))),
              Text('药品：${td['name'] ?? ''}',
                  style: const TextStyle(fontSize: 19, color: Color(0xFF333333))),
              Text('时间段：${td['slot'] ?? ''}',
                  style: const TextStyle(fontSize: 19, color: Color(0xFF333333))),
              Text('剂量：${td['dosage'] ?? ''}',
                  style: const TextStyle(fontSize: 19, color: Color(0xFF333333))),
              Text('频次：${td['frequency'] ?? ''}',
                  style: const TextStyle(fontSize: 19, color: Color(0xFF333333))),
            ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('关闭', style: TextStyle(fontSize: 19, color: _kText))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _kPage,
      child: RefreshIndicator(
      onRefresh: _refresh,
      color: const Color(0xFF345C87),
      child: _loading
          ? const Center(
              child: CircularProgressIndicator(color: const Color(0xFF345C87)))
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              children: [
                Row(children: [
                  Expanded(
                    child: ElevatedButton.icon(
                        onPressed: () => _openAdd(),
                        style: _tintBtn(_kText, _mMedBg),
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('手动录入', softWrap: false)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                        onPressed: _pickInstruction,
                        style: _tintBtn(_kText, _mMedBg),
                        icon: const Icon(Icons.camera_alt_outlined),
                        label: const Text('说明书拍照', softWrap: false)),
                  ),
                ]),
                const SizedBox(height: 16),
                _MineTable(
                  headers: const ['日期', '药品名称', '服用时段', '剂量', '是否用药'],
                  flex: const [2, 3, 2, 2, 2],
                  rows: [
                    for (final td in _todos)
                      [
                        _tCell(DateTime.now()
                            .toString()
                            .substring(0, 10)),
                        AfuPressable(
                          onTap: () => _detail(
                              Map<String, dynamic>.from(td as Map)),
                          borderRadius: 8,
                          child: Row(children: [
                            Expanded(
                                child: Text((td['name'] ?? '').toString(),
                                    style: const TextStyle(
                                        fontSize: 17,
                                        color: _kText,
                                        height: 1.45))),
                            const Icon(Icons.chevron_right,
                                size: 18, color: _kSub),
                          ]),
                        ),
                        _tCell((td['slot'] ?? '').toString()),
                        _tCell((td['dosage'] ?? '').toString()),
                        _tCell(statusText((td['status'] ?? '').toString())),
                      ],
                  ],
                  emptyIcon: Icons.medication_outlined,
                  emptyAccent: _mMed,
                  emptyText: widget.forElder ? '点右上角录药\n帮长辈上传用药安排' : '点右上角录药\n把每天要吃的药品记下来吧',
                ),
                if (widget.forElder && _todos.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _startAsk,
                      style: _tintBtn(_kText, _mMedBg),
                      icon: const Icon(Icons.alarm_outlined),
                      label: const Text('一键提醒用药',
                          softWrap: false),
                    ),
                  ),
                ],
              ],
            ),
    ),
    );
  }

  String statusText(String s) {
    if (s == 'taken') return '已服';
    if (s == 'missed') return '漏服';
    return '待服';
  }

  /// 一键提醒用药：底部面板单选一条用药记录，确认后跳聊天并预填提醒语。
  Future<void> _startAsk() async {
    final labels = [
      for (final td in _todos)
        '${(td as Map)['name'] ?? ''} ${td['dosage'] ?? ''} ${td['slot'] ?? ''}（${statusText((td['status'] ?? '').toString())}）',
    ];
    final idx = await _pickOneRecord(context,
        title: '提醒长辈用药',
        labels: labels,
        sendStyle: _tintBtn(_kText, _mMedBg));
    if (idx == null || idx < 0 || idx >= _todos.length) return;
    final td = Map<String, dynamic>.from(_todos[idx] as Map);
    final times = (td['slot'] ?? '').toString();
    final rec =
        '用药提醒：${td['name'] ?? ''}，${td['dosage'] ?? ''}，${times.isEmpty ? '' : '$times 服用'}';
    await _askElder(context,
        record: rec, prompt: '记得按时吃药，吃药后有不舒服要跟我说。');
  }
}

/// 本人-体征：录入（手动/拍照）+ 历史表格（编辑/删除）+ 导出 PDF。
class _MineVitalsPage extends StatefulWidget {
  final bool forElder;
  const _MineVitalsPage({super.key, this.forElder = false});
  @override
  State<_MineVitalsPage> createState() => _MineVitalsPageState();
}

class _MineVitalsPageState extends State<_MineVitalsPage> {
  List _rows = [];
  bool _loading = true;

  bool _exporting = false;

  static const _typeNames = {
    'bp': '血压',
    'bs': '血糖',
    'hr': '心率',
    'weight': '体重',
  };

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      _rows = await ApiService.vitalsList(mine: !widget.forElder, days: 90);
    } catch (_) {
      _rows = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  /// 按日期聚合：每天一行，血压/血糖/心率/体重各一列。
  List<Map<String, String>> _pivot() {
    final map = <String, Map<String, String>>{};
    for (final r in _rows) {
      final m = Map<String, dynamic>.from(r as Map);
      final d = (m['measured_at'] ?? m['created_at'] ?? '').toString();
      final day = d.length >= 10 ? d.substring(0, 10) : d;
      if (day.isEmpty) continue;
      final row = map.putIfAbsent(day,
          () => {'date': day, 'bp': '-', 'bs': '-', 'hr': '-', 'weight': '-'});
      final type = (m['type'] ?? '').toString();
      if (type == 'bp') {
        row['bp'] = '${m['systolic'] ?? '-'}/${m['diastolic'] ?? '-'}';
      } else if (row[type] != null) {
        row[type] = (m['value'] ?? '-').toString();
      }
    }
    final list = map.values.toList();
    list.sort((a, b) => b['date']!.compareTo(a['date']!));
    return list;
  }





  /// 手动录入体征（含记录日期选择）。
  /// 【等待后端接口开发完成】VitalsCreate 暂无日期字段，日期仅本地展示，
  /// 后端以服务端时间为准；单条编辑/删除暂无 PUT/DELETE 接口。
    Future<void> _openAdd() async {
    var type = 'bp';
    final v1C = TextEditingController();
    final v2C = TextEditingController();
    var date = DateTime(2026, 10, 5);
    String fmtD(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    InputDecoration boxDec(String hint) => InputDecoration(
          hintText: hint,
          hintStyle:
              const TextStyle(fontSize: 20, color: Color(0xFF6B7280)),
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide:
                  const BorderSide(color: Color(0xFFE4EAF2))),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide:
                  const BorderSide(color: Color(0xFFE4EAF2))),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(
                  color: Color(0xFF7C6FB5), width: 2)),
        );

    Widget formRow(String label, Widget field) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 108,
            child: Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: _kText)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: field),
        ]),
      );
    }

    Widget numField(TextEditingController c, bool decimal) {
      return TextField(
        controller: c,
        keyboardType: decimal
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.number,
        cursorColor: const Color(0xFF7C6FB5),
        style: const TextStyle(fontSize: 20, color: _kText),
        decoration: boxDec('请输入'),
      );
    }

    Future<void> pickDate(StateSetter setD) async {
      var y = date.year, m = date.month, d = date.day;
      int maxD() => DateTime(y, m + 1, 0).day;
      if (d > maxD()) d = maxD();
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(24))),
        builder: (c) => StatefulBuilder(
          builder: (c, setP) => SafeArea(
            child:
                Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding:
                    const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Row(children: [
                  TextButton(
                    onPressed: () => Navigator.pop(c),
                    child: const Text('取消',
                        style: TextStyle(
                            fontSize: 19, color: _kSub)),
                  ),
                  const Expanded(
                    child: Text('选择日期',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                            color: _kText)),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(c);
                      setD(() => date = DateTime(y, m, d));
                    },
                    child: const Text('确定',
                        style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF7C6FB5))),
                  ),
                ]),
              ),
              SizedBox(
                height: 220,
                child: Row(children: [
                  Expanded(
                    child: CupertinoPicker(
                      itemExtent: 46,
                      scrollController:
                          FixedExtentScrollController(
                              initialItem: y - 2020),
                      onSelectedItemChanged: (v) => setP(() {
                        y = 2020 + v;
                        if (d > maxD()) d = maxD();
                      }),
                      children: [
                        for (var yy = 2020; yy <= 2035; yy++)
                          Center(
                              child: Text('$yy年',
                                  style: const TextStyle(
                                      fontSize: 21))),
                      ],
                    ),
                  ),
                  Expanded(
                    child: CupertinoPicker(
                      itemExtent: 46,
                      scrollController:
                          FixedExtentScrollController(
                              initialItem: m - 1),
                      onSelectedItemChanged: (v) => setP(() {
                        m = v + 1;
                        if (d > maxD()) d = maxD();
                      }),
                      children: [
                        for (var mm = 1; mm <= 12; mm++)
                          Center(
                              child: Text('$mm月',
                                  style: const TextStyle(
                                      fontSize: 21))),
                      ],
                    ),
                  ),
                  Expanded(
                    child: CupertinoPicker(
                      key: ValueKey(maxD()),
                      itemExtent: 46,
                      scrollController:
                          FixedExtentScrollController(
                              initialItem: d - 1),
                      onSelectedItemChanged: (v) =>
                          setP(() => d = v + 1),
                      children: [
                        for (var dd = 1;
                            dd <= maxD();
                            dd++)
                          Center(
                              child: Text('$dd日',
                                  style: const TextStyle(
                                      fontSize: 21))),
                      ],
                    ),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      );
    }

    final ok = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black45,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => Dialog(
          backgroundColor: const Color(0xFFF4F5F7),
          insetPadding:
              const EdgeInsets.fromLTRB(20, 90, 20, 20),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28)),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
            child:
                Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('录入体征',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: _kText)),
              const SizedBox(height: 20),
              formRow(
                  '体征类型',
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                          color: const Color(0xFFE4EAF2)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: type,
                        isExpanded: true,
                        style: const TextStyle(
                            fontSize: 20, color: _kText),
                        items: [
                          for (final e in _typeNames.entries)
                            DropdownMenuItem(
                                value: e.key,
                                child: Text(e.value)),
                        ],
                        onChanged: (v) =>
                            setD(() => type = v ?? 'bp'),
                      ),
                    ),
                  )),
              if (type == 'bp') ...[
                formRow('收缩压', numField(v1C, false)),
                formRow('舒张压', numField(v2C, false)),
              ] else if (type == 'bs')
                formRow('血糖', numField(v1C, true))
              else if (type == 'hr')
                formRow('心率', numField(v1C, false))
              else
                formRow('体重', numField(v1C, true)),
              formRow(
                  '记录日期',
                  GestureDetector(
                    onTap: () => pickDate(setD),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius:
                            BorderRadius.circular(18),
                        border: Border.all(
                            color: const Color(0xFFE4EAF2)),
                      ),
                      child: Row(children: [
                        Expanded(
                          child: Text(fmtD(date),
                              style: const TextStyle(
                                  fontSize: 20,
                                  color: _kText)),
                        ),
                        const Icon(Icons.arrow_drop_down,
                            size: 28,
                            color: Color(0xFF7C6FB5)),
                      ]),
                    ),
                  )),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            vertical: 16)),
                    child: const Text('取消',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF555555))),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 56,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(c, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _mVit,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(18)),
                      ),
                      child: const Text('保存',
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
    if (ok == true) {
      final v1ok = v1C.text.trim().isNotEmpty &&
          (type == 'bs' || type == 'weight'
              ? double.tryParse(v1C.text.trim()) != null
              : int.tryParse(v1C.text.trim()) != null);
      final v2ok = type != 'bp' ||
          (v2C.text.trim().isNotEmpty &&
              int.tryParse(v2C.text.trim()) != null);
      if (!v1ok || !v2ok) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('请填写完整数值后再保存')));
        }
        return;
      }
      try {
        if (type == 'bp') {
          await ApiService.addVital(
              type: type,
              systolic: int.tryParse(v1C.text.trim()),
              diastolic: int.tryParse(v2C.text.trim()),
              mine: !widget.forElder);
        } else {
          await ApiService.addVital(
              type: type,
              value: double.tryParse(v1C.text.trim()),
              mine: !widget.forElder);
        }
        await _refresh();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('保存失败：${ApiService.friendly(e)}')));
        }
      }
    }
  }

Future<void> _pickPhoto() async {
    try {
      final f = await ImagePicker()
          .pickImage(source: ImageSource.camera, maxWidth: 1600);
      if (f == null) return;
      // 【等待后端接口开发完成】后端暂无体征拍照识别接口，照片暂不上传。
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('体征拍照识别即将上线，请先手动录入')));
      }
    } catch (_) {}
  }

  Future<void> _export() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final bytes = await ApiService.vitalsExportPdf(mine: !widget.forElder, days: 90);
      if (bytes.isEmpty) throw Exception('空文件');
      final now = DateTime.now();
      final name =
          '体征记录_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}.pdf';
      await saveAndOpenPdf(bytes, name);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('PDF 已导出：$name')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('导出失败：${ApiService.friendly(e)}')));
      }
    }
    if (mounted) setState(() => _exporting = false);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _kPage,
      child: RefreshIndicator(
      onRefresh: _refresh,
      color: const Color(0xFF345C87),
      child: _loading
          ? const Center(
              child: CircularProgressIndicator(color: const Color(0xFF345C87)))
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              children: [
                Row(children: [
                  Expanded(
                    child: ElevatedButton.icon(
                        onPressed: _openAdd,
                        style: _tintBtn(_kText, _mVitBg),
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('手动录入', softWrap: false)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                        onPressed: _pickPhoto,
                        style: _tintBtn(_kText, _mVitBg),
                        icon: const Icon(Icons.camera_alt_outlined),
                        label: const Text('拍照上传', softWrap: false)),
                  ),

                ]),
                const SizedBox(height: 16),
                _MineTable(
                  headers: const ['日期', '血压', '血糖', '心率', '体重'],
                  flex: const [2, 2, 2, 2, 2],
                  rows: [
                    for (final r in _pivot())
                      [
                        _tCell(r['date']!),
                        _tCell(r['bp']!),
                        _tCell(r['bs']!),
                        _tCell(r['hr']!),
                        _tCell(r['weight']!),
                      ],
                  ],
                  emptyIcon: Icons.show_chart_outlined,
                  emptyAccent: _mVit,
                  emptyText: '暂无体征数据，今天记录一条吧',
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                      onPressed: _exporting ? null : _export,
                      style: _tintBtn(_kText, _mVitBg),
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: Text(_exporting ? '导入中…' : '导出pdf',
                          softWrap: false)),
                ),
                if (widget.forElder && _rows.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _startAsk,
                      style: _tintBtn(_kText, _mVitBg),
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: const Text('一键询问长辈',
                          softWrap: false),
                    ),
                  ),
                ],
              ],
            ),
    ),
    );
  }

  /// 一键询问长辈：底部面板单选一条体征记录，确认后跳聊天并预填询问语。
  Future<void> _startAsk() async {
    final pv = _pivot();
    final labels = [
      for (final r in pv)
        '${r['date']}　血压${r['bp']}　血糖${r['bs']}　心率${r['hr']}　体重${r['weight']}',
    ];
    final idx = await _pickOneRecord(context,
        title: '选择体征记录',
        labels: labels,
        sendStyle: _tintBtn(_kText, _mVitBg));
    if (idx == null || idx < 0 || idx >= pv.length) return;
    final r = pv[idx];
    final rec = '体征记录：血压 ${r['bp']}mmHg，记录日期 ${r['date']}';
    await _askElder(context,
        record: rec, prompt: '请问你今天血压测量的时候有没有头晕不舒服？');
  }
}

/// 本人-报告：双上传入口 + AI 摘要 + 历史列表。
class _MineReportsPage extends StatefulWidget {
  final bool forElder;
  const _MineReportsPage({super.key, this.forElder = false});
  @override
  State<_MineReportsPage> createState() => _MineReportsPageState();
}

class _MineReportsPageState extends State<_MineReportsPage> {
  List _items = [];
  bool _loading = true;
  bool _uploading = false;


  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      _items = await ApiService.reportList(mine: !widget.forElder);
    } catch (_) {
      _items = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _upload(ImageSource source) async {
    if (_uploading) return;
    try {
      final f = await ImagePicker()
          .pickImage(source: source, maxWidth: 1600);
      if (f == null) return;
      setState(() => _uploading = true);
      final bytes = await f.readAsBytes();
      final r = await ApiService.uploadReport(bytes.toList(), f.name,
          mine: !widget.forElder);
      await _refresh();
      if (mounted) {
        final advice = (r['advice_text'] ?? '').toString();
        await showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('识别结果',
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF333333))),
            content: SingleChildScrollView(
                child: Text(
                    advice.isEmpty ? '已上传，解读生成中' : advice,
                    style: const TextStyle(
                        fontSize: 19,
                        color: Color(0xFF333333),
                        height: 1.5))),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(c),
                  child: const Text('知道了', style: TextStyle(fontSize: 19, color: _kText))),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('上传失败：${ApiService.friendly(e)}')));
      }
    }
    if (mounted) setState(() => _uploading = false);
  }

  Future<void> _detail(Map<String, dynamic> m) async {
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(
            (m['created_at'] ?? '').toString().substring(0, 10),
            style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: Color(0xFF333333))),
        content: SingleChildScrollView(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('指标摘要',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF333333))),
                Text((m['ocr_text'] ?? '').toString(),
                    style: const TextStyle(
                        fontSize: 18,
                        color: Color(0xFF333333),
                        height: 1.5)),
                const SizedBox(height: 12),
                const Text('健康建议',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF333333))),
                Text((m['advice_text'] ?? '').toString(),
                    style: const TextStyle(
                        fontSize: 18,
                        color: Color(0xFF333333),
                        height: 1.5)),
              ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('关闭', style: TextStyle(fontSize: 19, color: _kText))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _kPage,
      child: RefreshIndicator(
      onRefresh: _refresh,
      color: const Color(0xFF345C87),
      child: _loading
          ? const Center(
              child: CircularProgressIndicator(color: const Color(0xFF345C87)))
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              children: [
                Row(children: [
                  Expanded(
                    child: ElevatedButton.icon(
                        onPressed:
                            _uploading ? null : () => _upload(ImageSource.camera),
                        style: _tintBtn(_kText, _mRepBg),
                        icon: const Icon(Icons.camera_alt_outlined),
                        label: const Text('拍照上传', softWrap: false)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                        onPressed:
                            _uploading ? null : () => _upload(ImageSource.gallery),
                        style: _tintBtn(_kText, _mRepBg),
                        icon: const Icon(Icons.photo_outlined),
                        label: const Text('相册上传', softWrap: false)),
                  ),
                ]),
                const SizedBox(height: 16),
                _MineTable(
                  headers: const ['日期', '指标摘要', '提示', '健康建议'],
                  flex: const [2, 3, 2, 3],
                  rows: [
                    for (final e in _items)
                      [
                        AfuPressable(
                          onTap: () => _detail(
                              Map<String, dynamic>.from(e as Map)),
                          borderRadius: 8,
                          child: Row(children: [
                            Expanded(
                                child: Text(
                                    ((Map<String, dynamic>.from(e as Map)['created_at'] ?? '').toString().length >= 10)
                                        ? (Map<String, dynamic>.from(e as Map)['created_at']).toString().substring(0, 10)
                                        : '',
                                    style: const TextStyle(
                                        fontSize: 17,
                                        color: _kText,
                                        height: 1.45))),
                            const Icon(Icons.chevron_right,
                                size: 18, color: _kSub),
                          ]),
                        ),
                        _tCell(
                            _short((Map<String, dynamic>.from(e as Map)['ocr_text'] ?? '').toString(), 40)),
                        _tCell(
                            _abnormalShort((Map<String, dynamic>.from(e as Map)['ocr_text'] ?? '').toString(),
                                (Map<String, dynamic>.from(e as Map)['advice_text'] ?? '').toString()),
                            color: _kDanger),
                        _tCell(
                            _short((Map<String, dynamic>.from(e as Map)['advice_text'] ?? '').toString(), 40)),
                      ],
                  ],
                  emptyIcon: Icons.description_outlined,
                  emptyAccent: _mRep,
                  emptyText: widget.forElder ? '暂无报告信息' : '暂无历史体检报告，今天记录一条吧',
                ),
                if (widget.forElder && _items.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _startAsk,
                      style: _tintBtn(_kText, _mRepBg),
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: const Text('一键询问长辈',
                          softWrap: false),
                    ),
                  ),
                ],
              ],
            ),
    ),
    );
  }

  /// 一键询问长辈：底部面板单选一份体检报告，确认后跳聊天并预填询问语。
  Future<void> _startAsk() async {
    final labels = [
      for (final e in _items)
        '${((Map<String, dynamic>.from(e as Map)['created_at'] ?? '').toString().length >= 10) ? (Map<String, dynamic>.from(e as Map)['created_at']).toString().substring(0, 10) : ''}　${_short((Map<String, dynamic>.from(e as Map)['advice_text'] ?? '').toString(), 30)}',
    ];
    final idx = await _pickOneRecord(context,
        title: '选择体检报告',
        labels: labels,
        sendStyle: _tintBtn(_kText, _mRepBg));
    if (idx == null || idx < 0 || idx >= _items.length) return;
    final m = Map<String, dynamic>.from(_items[idx] as Map);
    final d = (m['created_at'] ?? '').toString();
    final date = d.length >= 10 ? d.substring(0, 10) : d;
    final rec =
        '体检报告（$date）：${_short((m['ocr_text'] ?? '').toString(), 40)}';
    await _askElder(context,
        record: rec, prompt: '这份体检报告有些指标需要关注，咱们要不要去医院复查一下？');
  }
}

String _short(String s, int n) =>
    s.length > n ? '${s.substring(0, n)}…' : s;

/// 异常提示提取（与长辈报告页同规则）：命中关键词标红，否则空。
String _abnormalShort(String ocr, String adv) {
  for (final line in '$ocr\n$adv'.split('\n')) {
    final s = line.trim();
    if (s.isEmpty) continue;
    for (final k in ['异常', '偏高', '偏低', '升高', '降低', '阳性', '超标', '注意']) {
      if (s.contains(k)) return _short(s, 30);
    }
  }
  return '—';
}

// 自查日期简写 + 就医提示（risk 语义映射）。
String _cdate(Map<String, dynamic> m) {
  final d = (m['created_at'] ?? '').toString();
  return d.length >= 10 ? d.substring(0, 10) : d;
}

String _riskHint(String risk) {
  if (risk == 'red') return '建议尽快就医';
  if (risk == 'yellow') return '建议咨询医生';
  return '注意观察';
}

// 长辈咨询标题 + 行内回放键（播放图标主色）。
String _ctitle(Map<String, dynamic> m) {
  final hosp = (m['hospital'] ?? '').toString();
  final doc = (m['doctor'] ?? '').toString();
  final d = (m['created_at'] ?? '').toString();
  if (hosp.isNotEmpty) return hosp;
  if (doc.isNotEmpty) return doc;
  return '问诊录音${d.length >= 10 ? d.substring(0, 10) : ''}';
}

/// 本人-咨询：录音上传（医院/标题备注）+ 历史回放。
/// 【等待后端接口开发完成】ConsultRecord 暂无标题/转写摘要字段：
/// 标题存本地（未填则默认“问诊录音+日期”），AI 摘要主题待后端转写能力。
class _MineConsultsPage extends StatefulWidget {
  const _MineConsultsPage({super.key});
  @override
  State<_MineConsultsPage> createState() => _MineConsultsPageState();
}

class _MineConsultsPageState extends State<_MineConsultsPage> {
  List _items = [];
  bool _loading = true;
  bool _busy = false;
  bool _recording = false;
  final _rec = AudioRecorder();
  final _player = AudioPlayer();
  String? _playing;
  Map<int, String> _titles = {};

  @override
  void initState() {
    super.initState();
    _refresh();
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = null);
    });
  }

  @override
  void dispose() {
    _rec.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      _items = await ApiService.consultList(mine: true);
      try {
        final prefs = await SharedPreferences.getInstance();
        final map = <int, String>{};
        for (final e in _items) {
          final m = Map<String, dynamic>.from(e as Map);
          final id = (m['id'] as num?)?.toInt();
          if (id != null) {
            final t = prefs.getString('consult_title_$id');
            if (t != null && t.isNotEmpty) map[id] = t;
          }
        }
        _titles = map;
      } catch (_) {}
    } catch (_) {
      _items = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  String _titleOf(Map<String, dynamic> m) {
    final id = (m['id'] as num?)?.toInt();
    if (id != null && (_titles[id] ?? '').isNotEmpty) return _titles[id]!;
    final d = (m['created_at'] ?? '').toString();
    return '问诊录音${d.length >= 10 ? d.substring(0, 10) : ''}';
  }

  Future<void> _toggleRecord() async {
    if (_busy) return;
    if (_recording) {
      setState(() => _busy = true);
      try {
        final path = await _rec.stop();
        if (path != null && mounted) await _afterRecord(path);
      } catch (_) {}
      if (mounted) setState(() { _recording = false; _busy = false; });
      return;
    }
    try {
      if (!await _rec.hasPermission()) throw Exception('no mic');
      await _rec.start(const RecordConfig(),
          path: 'consult_${DateTime.now().millisecondsSinceEpoch}.m4a');
      if (mounted) setState(() => _recording = true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('录音启动失败，请检查麦克风权限')));
      }
    }
  }

  Future<void> _afterRecord(String path) async {
    final bytes = await XFile(path).readAsBytes();
    final hospC = TextEditingController();
    final titleC = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('保存录音',
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: Color(0xFF333333))),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: hospC,
                style: const TextStyle(fontSize: 20, color: Color(0xFF333333)),
                decoration:
                    const InputDecoration(labelText: '医院地址（选填）')),
            TextField(
                controller: titleC,
                style: const TextStyle(fontSize: 20, color: Color(0xFF333333)),
                decoration: const InputDecoration(
                    labelText: '标题备注（选填，不填自动生成）')),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消', style: TextStyle(fontSize: 19, color: _kText))),
          ElevatedButton(
              onPressed: () => Navigator.pop(c, true),
              style: _primaryBtn().copyWith(foregroundColor: const WidgetStatePropertyAll<Color>(_kText)),
              child: const Text('上传', style: TextStyle(fontSize: 19, color: _kText))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final r = await ApiService.uploadConsult(
        bytes.toList(),
        'consult_${DateTime.now().millisecondsSinceEpoch}.m4a',
        hospital: hospC.text.trim().isEmpty ? null : hospC.text.trim(),
        mine: true,
      );
      final id = (r['id'] as num?)?.toInt();
      if (id != null && titleC.text.trim().isNotEmpty) {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('consult_title_$id', titleC.text.trim());
        } catch (_) {}
      }
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('录音已保存')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('上传失败：${ApiService.friendly(e)}')));
      }
    }
  }

  Future<void> _togglePlay(String url) async {
    try {
      if (_playing == url) {
        await _player.stop();
        if (mounted) setState(() => _playing = null);
        return;
      }
      await _player.stop();
      await _player.play(UrlSource(url));
      if (mounted) setState(() => _playing = url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('播放失败：${ApiService.friendly(e)}')));
      }
    }
  }

  String _dateOf(Map<String, dynamic> m) {
    final d = (m['created_at'] ?? '').toString();
    return d.length >= 10 ? d.substring(0, 10) : d;
  }

  Widget _playBtn(Map<String, dynamic> m) {
    final audio = (m['audio_url'] ?? '').toString();
    if (audio.isEmpty) return const SizedBox.shrink();
    final full = ApiService.consultAudioUrl(audio);
    final playing = _playing != null && _playing == full;
    return IconButton(
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        icon: Icon(playing ? Icons.stop_circle : Icons.play_arrow,
            size: 26, color: _mCon),
        onPressed: () => _togglePlay(full));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _kPage,
      child: RefreshIndicator(
      onRefresh: _refresh,
      color: const Color(0xFF345C87),
      child: _loading
          ? const Center(
              child: CircularProgressIndicator(color: const Color(0xFF345C87)))
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              children: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                      onPressed: _toggleRecord,
                      style: _tintBtn(_kText, _mConBg),
                      icon: Icon(_recording
                          ? Icons.stop_circle
                          : Icons.mic_none_outlined),
                      label: Text(
                          _recording ? '停止并保存' : '开始录音',
                          softWrap: false,
                          style: const TextStyle(fontSize: 20))),
                ),
                const SizedBox(height: 16),
                _MineTable(
                  headers: const ['标题', '录制时间', 'AI摘要', '就诊地址'],
                  flex: const [3, 2, 2, 2],
                  rows: [
                    for (final e in _items)
                      [
                        Row(children: [
                          Expanded(
                              child: Text(
                                  _titleOf(Map<String, dynamic>.from(
                                      e as Map)),
                                  style: const TextStyle(
                                      fontSize: 17,
                                      color: _kText,
                                      height: 1.45))),
                          _playBtn(Map<String, dynamic>.from(e as Map)),
                        ]),
                        _tCell(_dateOf(
                            Map<String, dynamic>.from(e as Map))),
                        // 后端暂无录音转写摘要字段，待 AI 识别能力上线
                        _tCell('—', color: _kSub),
                        _tCell((Map<String, dynamic>.from(e as Map)['hospital'] ??
                                '')
                            .toString()),
                      ],
                  ],
                  emptyIcon: Icons.mic_none_outlined,
                  emptyAccent: _mCon,
                  emptyText: '暂无录音记录，点击记录就诊历史',
                ),
              ],
            ),
    ),
    );
  }
}

/// ============ 绑定长辈视图 6 只读页：仅查看 + 消息交互 ============
/// 无上传/录入/拍照/新增类按钮；空状态统一图片+文案；底部一键询问老人。

/// 绑定长辈-查药：仅展示记录列表（后端暂无查药记录接口，常显空状态）。
/// 【等待后端接口开发完成】查药结果后端不落库（DrugResult 只返回不存表），
/// 记录列表/药品信息/症状/禁忌/总结时间待 drug_queries 接口。
class _ElderDrugPage extends StatefulWidget {
  const _ElderDrugPage({super.key});
  @override
  State<_ElderDrugPage> createState() => _ElderDrugPageState();
}

class _ElderDrugPageState extends State<_ElderDrugPage> {
  // 【等待后端接口开发完成】查药结果后端不落库，暂无记录可展示；
  // drug_queries 接口就绪后在此读取并展示（药品/症状/禁忌/总结时间）。
  final List _items = const [];

  @override
  Widget build(BuildContext context) {
    const cols = [
      _ECol('药品名称', 3),
      _ECol('查询时间', 2),
      _ECol('操作', 2, right: true),
    ];
    return Container(
      color: _kPage,
      child: CustomScrollView(slivers: [
        if (_items.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => _askElder(context,
                      record: '查药记录：暂无',
                      prompt: '看到本次查药记录，想跟您确认，该药品服用后有没有不舒服的反应？'),
                  style: _tintBtn(_eDrug, _eDrugBg),
                  child:
                      const Text('一键询问老人', softWrap: false),
                ),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 12)),
          SliverPersistentHeader(
              pinned: true,
              delegate: const _EHeadDelegate(_eDrugBg, cols)),
          SliverList(
              delegate: SliverChildBuilderDelegate(
                  (c, i) => const SizedBox.shrink(),
                  childCount: 0)),
        ] else
          const _ESliverEmpty(
            icon: Icons.medical_services_outlined,
            accent: _eDrug,
            text: '暂时没有查药信息',
          ),
      ]),
    );
  }
}

class _ElderMedsPage extends StatelessWidget {
  const _ElderMedsPage({super.key});
  @override
  Widget build(BuildContext context) =>
      const _MineMedsPage(forElder: true);
}

class _ElderVitalsPage extends StatelessWidget {
  const _ElderVitalsPage({super.key});
  @override
  Widget build(BuildContext context) =>
      const _MineVitalsPage(forElder: true);
}

class _ElderSelfcheckPage extends StatefulWidget {
  const _ElderSelfcheckPage({super.key});
  @override
  State<_ElderSelfcheckPage> createState() => _ElderSelfcheckPageState();
}

class _ElderSelfcheckPageState extends State<_ElderSelfcheckPage> {
  List _items = [];
  bool _loading = true;


  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      _items = await ApiService.symptomHistory();
    } catch (_) {
      _items = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  /// 一键询问长辈：底部面板单选一条自查记录，确认后跳聊天并预填询问语。
  Future<void> _startAsk() async {
    final labels = [
      for (final m in _items)
        '${_cdate(Map<String, dynamic>.from(m as Map))}　${(Map<String, dynamic>.from(m as Map)['input_text'] ?? '').toString()}',
    ];
    final idx = await _pickOneRecord(context,
        title: '选择自查记录',
        labels: labels,
        sendStyle: _tintBtn(_kText, _eSelfBg));
    if (idx == null || idx < 0 || idx >= _items.length) return;
    final m = Map<String, dynamic>.from(_items[idx] as Map);
    final date = _cdate(m);
    final rec =
        '自查记录（$date）：${(m['input_text'] ?? '').toString()}';
    await _askElder(context,
        record: rec, prompt: '看到你有一条自查记录，现在感觉好些了吗？');
  }

  Future<void> _sDetail(Map<String, dynamic> m) async {
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('自查详情（${_cdate(m)}）',
            style: const TextStyle(
                fontSize: 22, fontWeight: FontWeight.w700, color: _kText)),
        content: SingleChildScrollView(
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('自查症状\n${m['input_text'] ?? ''}',
                    style: const TextStyle(
                        fontSize: 19, color: _kText, height: 1.6)),
                const SizedBox(height: 8),
                Text('AI健康结论\n${m['advice_text'] ?? ''}',
                    style: const TextStyle(
                        fontSize: 19, color: _kText, height: 1.6)),
                const SizedBox(height: 8),
                Text('就医提示\n${_riskHint((m['risk'] ?? '').toString())}',
                    style: const TextStyle(
                        fontSize: 19, color: _kText, height: 1.6)),
              ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('关闭',
                  style: TextStyle(fontSize: 19, color: _kPrimary))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Container(
        color: _kPage,
        child: const Center(
            child: CircularProgressIndicator(color: const Color(0xFF345C87))),
      );
    }
    final list = [for (final it in _items) _asMap(it)];
    return Container(
      color: _kPage,
      child: RefreshIndicator(
        onRefresh: _refresh,
        color: const Color(0xFF345C87),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          children: [
            _MineTable(
              headers: const ['自测时间', '题目内容', '建议', '状态'],
              flex: const [2, 3, 3, 2],
              rows: [
                for (final m in list)
                  [
                    AfuPressable(
                      onTap: () => _sDetail(m),
                      borderRadius: 8,
                      child: Row(children: [
                        Expanded(
                            child: Text(_cdate(m),
                                softWrap: false,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 17,
                                    color: _kText,
                                    height: 1.45))),
                        const Icon(Icons.chevron_right,
                            size: 18, color: _kSub),
                      ]),
                    ),
                    _tCell((m['input_text'] ?? '').toString(),
                        maxLines: 3),
                    _tCell((m['advice_text'] ?? '').toString(),
                        maxLines: 3),
                    _tCell(_riskHint((m['risk'] ?? '').toString())),
                  ],
              ],
              emptyIcon: Icons.speed_outlined,
              emptyAccent: _eSelf,
              emptyText: '暂无自查记录',
            ),
            if (list.isNotEmpty) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _startAsk,
                  style: _tintBtn(_kText, _eSelfBg),
                  icon: const Icon(Icons.chat_bubble_outline),
                  label: const Text('一键询问长辈',
                      softWrap: false),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 绑定长辈-报告：报告记录 + 异常提示（关键词启发式，#F53F3F）。
class _ElderReportsPage extends StatelessWidget {
  const _ElderReportsPage({super.key});
  @override
  Widget build(BuildContext context) =>
      const _MineReportsPage(forElder: true);
}



class _ElderConsultsPage extends StatefulWidget {
  const _ElderConsultsPage({super.key});
  @override
  State<_ElderConsultsPage> createState() => _ElderConsultsPageState();
}

class _ElderConsultsPageState extends State<_ElderConsultsPage> {
  List _items = [];
  bool _loading = true;

  final _player = AudioPlayer();
  String? _playing;

  @override
  void initState() {
    super.initState();
    _refresh();
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = null);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      _items = await ApiService.consultList();
    } catch (_) {
      _items = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  /// 一键询问长辈：底部面板单选一条问诊记录，确认后跳聊天并预填询问语。
  Future<void> _startAsk() async {
    final labels = [
      for (final m in _items) _ctitle(Map<String, dynamic>.from(m as Map)),
    ];
    final idx = await _pickOneRecord(context,
        title: '选择问诊记录',
        labels: labels,
        sendStyle: _tintBtn(_kText, _eConBg));
    if (idx == null || idx < 0 || idx >= _items.length) return;
    final m = Map<String, dynamic>.from(_items[idx] as Map);
    final d = (m['created_at'] ?? '').toString();
    final date = d.length >= 10 ? d.substring(0, 10) : d;
    final rec = '问诊记录（$date）：${_ctitle(m)}';
    await _askElder(context,
        record: rec, prompt: '关于这次问诊，医生交代的事项都记清楚了吗？');
  }

  Future<void> _togglePlay(String url) async {
    try {
      if (_playing == url) {
        await _player.stop();
        if (mounted) setState(() => _playing = null);
        return;
      }
      await _player.stop();
      await _player.play(UrlSource(url));
      if (mounted) setState(() => _playing = url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('播放失败：${ApiService.friendly(e)}')));
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Container(
        color: _kPage,
        child: const Center(
            child: CircularProgressIndicator(color: const Color(0xFF345C87))),
      );
    }
    final list = [for (final it in _items) _asMap(it)];
    return Container(
      color: _kPage,
      child: RefreshIndicator(
        onRefresh: _refresh,
        color: const Color(0xFF345C87),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          children: [
            _MineTable(
              headers: const ['咨询时间', '问诊摘要', '回复状态', '语音'],
              flex: const [2, 3, 2, 2],
              rows: [
                for (final m in list)
                  [
                    _tCell(_md((m['created_at'] ?? '').toString()),
                        color: _kSub2),
                    _tCell(_ctitle(m), maxLines: 3),
                    _tCell(
                        ((m['audio_url'] ?? '').toString())
                                .isEmpty
                            ? '无'
                            : '可回放',
                        color: ((m['audio_url'] ?? '')
                                .toString())
                                .isEmpty
                            ? _kSub2
                            : _kText),
                    _playCell(m),
                  ],
              ],
              emptyIcon: Icons.mic_none_outlined,
              emptyAccent: _eCon,
              emptyText: '暂时没有咨询信息',
            ),
            if (list.isNotEmpty) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _startAsk,
                  style: _tintBtn(_kText, _eConBg),
                  icon: const Icon(Icons.chat_bubble_outline),
                  label: const Text('一键询问长辈',
                      softWrap: false),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 表格末列：有录音则显示播放/停止按钮，否则显示"无"。
  Widget _playCell(Map<String, dynamic> m) {
    final audio = (m['audio_url'] ?? '').toString();
    final full =
        audio.isEmpty ? '' : ApiService.consultAudioUrl(audio);
    if (full.isEmpty) return _tCell('无', color: _kSub2);
    final playing = _playing != null && _playing == full;
    return Align(
      alignment: Alignment.centerRight,
      child: AfuPressable(
        onTap: () => _togglePlay(full),
        borderRadius: 8,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
              playing ? Icons.stop_circle : Icons.play_arrow,
              size: 26,
              color: _eCon),
        ),
      ),
    );
  }
}

/// 天气插件多云太阳图标：太阳线条 + 光芒用低饱和暖橙，
/// 云朵浅灰白填充 + 暖橙投影，线性圆润风格，与功能卡片图标一致。
class _SunCloudPainter extends CustomPainter {
  const _SunCloudPainter();
  @override
  void paint(Canvas canvas, Size s) {
    final warm = const Color(0xFFE0B57A);
    final cloudFill = const Color(0xFFF4F4F4);
    final w = s.width;
    final sunC = Offset(w * 0.34, w * 0.34);
    final sunR = w * 0.15;
    // 太阳本体 + 8 束光芒
    canvas.drawCircle(
        sunC,
        sunR,
        Paint()
          ..color = warm
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round);
    for (var i = 0; i < 8; i++) {
      final a = i * 0.7854;
      final dx = math.cos(a);
      final dy = math.sin(a);
      canvas.drawLine(
          Offset(sunC.dx + dx * (sunR + 2.5), sunC.dy + dy * (sunR + 2.5)),
          Offset(sunC.dx + dx * (sunR + 6), sunC.dy + dy * (sunR + 6)),
          Paint()
            ..color = warm
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.4
            ..strokeCap = StrokeCap.round);
    }
    // 云朵：三圆 + 底座圆角矩形
    final cloud = Path()
      ..addOval(Rect.fromCircle(center: Offset(w * 0.52, w * 0.66), radius: w * 0.13))
      ..addOval(Rect.fromCircle(center: Offset(w * 0.65, w * 0.60), radius: w * 0.17))
      ..addOval(Rect.fromCircle(center: Offset(w * 0.78, w * 0.67), radius: w * 0.12))
      ..addRRect(RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.40, w * 0.64, w * 0.50, w * 0.16),
          Radius.circular(w * 0.08)));
    // 暖橙投影
    canvas.save();
    canvas.translate(1.5, 2.0);
    canvas.drawPath(
        cloud,
        Paint()
          ..color = warm.withOpacity(0.45)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0));
    canvas.restore();
    canvas.drawPath(cloud, Paint()..color = cloudFill);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
