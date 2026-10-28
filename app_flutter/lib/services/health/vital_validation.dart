/// 与后端录入接口一致的输入限制，不代表医学上的正常范围。
String? validateVitalValues(String type,
    {int? systolic, int? diastolic, double? value}) {
  if (type == 'bp') {
    if (systolic == null || diastolic == null) return '请填写高压和低压整数';
    if (systolic < 30 || systolic > 300) return '高压请输入 30～300 mmHg';
    if (diastolic < 20 || diastolic > 250) return '低压请输入 20～250 mmHg';
    if (systolic <= diastolic) return '高压必须大于低压';
    return null;
  }
  if (!['bs', 'hr', 'weight'].contains(type)) return '请选择有效的体征类型';
  if (value == null || !value.isFinite) return '请输入有效数值';
  if (type == 'bs' && (value < 1 || value > 50)) return '血糖请输入 1～50 mmol/L';
  if (type == 'hr' && (value < 30 || value > 250)) return '心率请输入 30～250 次/分';
  if (type == 'weight' && (value < 20 || value > 300)) return '体重请输入 20～300 kg';
  return null;
}
