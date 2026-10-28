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

/// 普通问答落库的 kind=chat 记录没有 category 字段，列表端用同一组
/// 意图词过滤旧数据，避免“高血压怎么办”被误显示成查药记录。
bool isDrugSummaryQuestion(String question) {
  final text = question.trim();
  if (text.isEmpty) return false;
  final healthCondition =
      RegExp(r'高血压|血压高|血压低|血糖高|血糖低|糖尿病|心率|心慌|胸闷|头晕|头痛|发热|咳嗽|不舒服|难受')
          .hasMatch(text);
  final explicitDrugQuery =
      RegExp(r'查药|药盒|说明书|药品|药名|什么药|药的作用|副作用|禁忌|能一起吃|药怎么吃').hasMatch(text);
  if (healthCondition && !explicitDrugQuery && drugQueryName(text) == null) {
    return false;
  }
  return drugQueryName(text) != null ||
      RegExp(r'查药|药盒|说明书|药品|药名|什么药|药的作用|副作用|禁忌|能一起吃|药怎么吃').hasMatch(text);
}

bool isHealthSelfcheckQuestion(String question) {
  final text = question.trim();
  if (text.isEmpty || drugQueryName(text) != null) return false;
  final hasHealthTopic =
      RegExp(r'高血压|血压高|血压低|血糖高|血糖低|糖尿病|心率|心慌|胸闷|头晕|头痛|发热|咳嗽|不舒服|难受|症状|自查|血脂|尿酸')
          .hasMatch(text);
  final asksAboutDrug =
      RegExp(r'查药|药盒|说明书|药品|药名|什么药|药的作用|副作用|禁忌|能一起吃|药怎么吃').hasMatch(text);
  return hasHealthTopic && !asksAboutDrug;
}
