import 'package:flutter/material.dart';
import '../services/api.dart';

/// 年龄和共享分层均来自服务端；出生年月可由本人核对后补齐。
class AgeProfileCard extends StatefulWidget {
  final bool family;
  final VoidCallback? onUpdated;
  const AgeProfileCard({super.key, this.family = false, this.onUpdated});

  @override
  State<AgeProfileCard> createState() => _AgeProfileCardState();
}

class _AgeProfileCardState extends State<AgeProfileCard> {
  Map<String, dynamic> _profile = {};
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = await ApiService.getProfile();
      if (mounted) setState(() => _profile = profile);
    } catch (e) {
      if (mounted) setState(() => _error = ApiService.friendly(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editBirth() async {
    if (_loading || _saving) return;
    final now = DateTime.now();
    final existing = DateTime.tryParse('${_profile['birth_ym'] ?? ''}-01');
    final picked = await showDatePicker(
      context: context,
      locale: const Locale('zh', 'CN'),
      helpText: '请选择出生年月，日期仅用于选择月份',
      initialDate:
          existing != null && !existing.isAfter(now) && existing.year >= 1900
              ? existing
              : DateTime(now.year - 60, now.month),
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked == null || !mounted) return;
    final birth = '${picked.year}-${picked.month.toString().padLeft(2, '0')}';
    final birthLabel = '${picked.year}年${picked.month}月';
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('确认出生年月'),
              content: Text('出生年月：$birthLabel。此资料会影响服务端年龄分层及共享规则，请核对后保存。'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('返回修改')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('确认保存')),
              ],
            ));
    if (confirmed != true || !mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final profile = await ApiService.updateProfile(birthYm: birth);
      if (!mounted) return;
      setState(() => _profile = profile);
      widget.onUpdated?.call();
    } catch (e) {
      if (mounted) setState(() => _error = ApiService.friendly(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tier = _profile['age_tier'];
    final age = _profile['age'];
    return Card(
        child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('年龄分层与共享说明',
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (_loading || _saving) const LinearProgressIndicator(),
        if (_error != null) ...[
          Text('资料未能读取或保存：$_error',
              style: const TextStyle(fontSize: 17, color: Color(0xFFB3261E))),
          TextButton(
              onPressed: _loading || _saving ? null : _load,
              child: const Text('重新读取')),
        ],
        if (!_loading && _profile.isNotEmpty) ...[
          Text(
              '出生年月：${_birthLabel(_profile['birth_ym'])}${age == null ? '' : ' · $age 周岁'}',
              style: const TextStyle(fontSize: 19)),
          Text(
              tier == 'senior'
                  ? '服务端分层：满60周岁及以上'
                  : tier == 'younger'
                      ? '服务端分层：未满60周岁'
                      : '请补齐有效出生年月，以确定分层和家属可见范围',
              style: const TextStyle(fontSize: 18, height: 1.5)),
          if (widget.family)
            const Text('这是您的本人资料；查看长辈资料仍须有效绑定，并遵循长辈的年龄分层和共享设置。',
                style: TextStyle(fontSize: 17, height: 1.5))
          else if (_profile['forced_share'] == true)
            const Text('当前服务端启用强制共享：健康资料向有效绑定家属开放，无法在此关闭。',
                style: TextStyle(fontSize: 17, height: 1.5))
          else
            const Text('家属可见范围由共享设置和有效绑定共同决定；缺少出生年月时，服务端会限制家属访问健康资料。',
                style: TextStyle(fontSize: 17, height: 1.5)),
        ],
        TextButton.icon(
            onPressed: _loading || _saving ? null : _editBirth,
            icon: const Icon(Icons.edit_calendar_outlined),
            label: const Text('补充／修改出生年月')),
      ]),
    ));
  }

  String _birthLabel(dynamic value) {
    final match =
        RegExp(r'^(\d{4})-(\d{2})$').firstMatch((value ?? '').toString());
    if (match == null) return '未设置';
    return '${match.group(1)}年${int.parse(match.group(2)!)}月';
  }
}
