import 'dart:html' as html;
import 'dart:typed_data';
import 'dart:async';

/// Web：触发浏览器下载。
Future<void> downloadBytes(List<int> bytes, String filename) async {
  final blob = html.Blob([Uint8List.fromList(bytes)], 'application/pdf');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)..download = filename;
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  Timer(const Duration(minutes: 1), () => html.Url.revokeObjectUrl(url));
}

/// Web 端：直接触发浏览器下载（即系统级导出）。
Future<String?> saveAndOpenPdf(List<int> bytes, String filename) async {
  if (bytes.length < 5 || String.fromCharCodes(bytes.take(5)) != '%PDF-') {
    throw StateError('服务器返回的不是有效 PDF，文件未保存');
  }
  await downloadBytes(bytes, filename);
  return null;
}
