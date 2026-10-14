/// 识别明确的药品查询，交给会保存记录的专用接口。
String? drugQueryName(String question) {
  if (RegExp(r'提醒|打卡|录入|记录用药|设置时间').hasMatch(question)) return null;
  const names = [
    '阿司匹林',
    '布洛芬',
    '对乙酰氨基酚',
    '二甲双胍',
    '阿莫西林',
    '氨氯地平',
    '硝苯地平',
    '缬沙坦',
    '氯沙坦',
    '奥美拉唑',
    '头孢',
    '维生素C'
  ];
  for (final name in names) {
    if (question.toLowerCase().contains(name.toLowerCase())) return name;
  }
  if (!RegExp(r'查药|药品|药名|什么药|什么作用|副作用|禁忌|说明书').hasMatch(question)) return null;
  final match =
      RegExp(r'([\u4e00-\u9fffA-Za-z0-9·-]{2,25}(?:胶囊|颗粒|口服液|注射液|滴眼液|片))')
          .firstMatch(question);
  if (match != null) {
    return match
        .group(1)!
        .replaceFirst(RegExp(r'^(?:请|帮我|我想)?(?:查一下|查询|查查|了解|介绍|查)?'), '');
  }
  final explicit =
      RegExp(r'(?:查药|查询药品|药名)[：:\s]+([^？?\n]+)').firstMatch(question);
  return explicit?.group(1)?.trim();
}
