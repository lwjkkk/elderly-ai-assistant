/// 将服务端持久化异常事件转换为现有家人健康卡片，不生成送达状态。
Map<String, dynamic> normalizeFamilyAlertContent(Map<String, dynamic> content) {
  if (content['kind'] != 'health' || content['type'] != 'vital_alert') {
    return content;
  }
  const names = {'bp': '血压', 'bs': '血糖', 'hr': '心率', 'weight': '体重'};
  final name = names[content['vital_type']] ?? '体征';
  return {
    ...content,
    'title': '$name异常提醒',
    'lines': [
      if (content['alert_id'] != null) '事件编号：${content['alert_id']}',
      if (content['level'] != null) '提醒等级：${content['level']}',
      if ((content['message'] ?? '').toString().isNotEmpty)
        '${content['message']}',
      if ((content['source'] ?? '').toString().isNotEmpty)
        '阈值依据：${content['source']}',
      '服务端已记录，手机推送送达状态未提供。',
    ],
  };
}
