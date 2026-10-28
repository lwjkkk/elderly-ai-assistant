import 'dart:io';

import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

/// 非 Web：写入临时目录。
Future<void> downloadBytes(List<int> bytes, String filename) async {
  final dir = await getTemporaryDirectory();
  final f = File('${dir.path}/$filename');
  await f.writeAsBytes(bytes, flush: true);
}

/// 保存到临时目录并用系统应用打开（真实导出）。
Future<String?> saveAndOpenPdf(List<int> bytes, String filename) async {
  if (bytes.length < 5 || String.fromCharCodes(bytes.take(5)) != '%PDF-') {
    throw StateError('服务器返回的不是有效 PDF，文件未保存');
  }
  final dir = await getApplicationDocumentsDirectory();
  final f = File('${dir.path}/$filename');
  await f.writeAsBytes(bytes, flush: true);
  final result = await OpenFilex.open(f.path, type: 'application/pdf');
  if (result.type == ResultType.done) return null;
  if (result.type == ResultType.noAppToOpen) {
    return 'PDF 已保存，手机没有可打开 PDF 的应用：${f.path}';
  }
  return 'PDF 已保存，但未能自动打开：${result.message}。文件位置：${f.path}';
}
