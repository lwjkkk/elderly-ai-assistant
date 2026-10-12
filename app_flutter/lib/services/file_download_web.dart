import 'dart:html' as html;

/// Web：触发浏览器下载。
Future<void> downloadBytes(List<int> bytes, String filename) async {
  final blob = html.Blob([bytes], 'application/pdf');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..download = filename
    ..click();
  html.Url.revokeObjectUrl(url);
}


/// Web 端：直接触发浏览器下载（即系统级导出）。
Future<void> saveAndOpenPdf(List<int> bytes, String filename) async {
  await downloadBytes(bytes, filename);
}
