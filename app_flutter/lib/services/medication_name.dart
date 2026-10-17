/// Keep the Chinese medicine name without the OCR English-name section.
/// Preserve meaningful identifiers such as B12 and dose numbers.
String medicationChineseName(String input) {
  var text = input
      .split(RegExp(r'英文(?:名称|名)?\s*[:：]?|English\s*(?:name)?\s*[:：]?',
          caseSensitive: false))
      .first;
  text = text.replaceAll(RegExp(r'【?(?:通用名称|通用名|药品名称)】?\s*[:：]?'), '');
  final lines = text.split(RegExp(r'[\r\n]+'));
  text = lines
      .firstWhere((s) => RegExp(r'[\u4e00-\u9fff]').hasMatch(s),
          orElse: () => '')
      .trim();
  // Discard a trailing English translation; retain short clinical identifiers.
  text = text.replaceAll(RegExp(r'[A-Za-z][A-Za-z\s-]{2,}'), '').trim();
  return text.replaceAll(RegExp(r'^[\s:：;；【】]+|[\s:：;；【】]+$'), '');
}
