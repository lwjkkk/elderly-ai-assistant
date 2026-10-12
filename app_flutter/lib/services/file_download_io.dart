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
Future<void> saveAndOpenPdf(List<int> bytes, String filename) async {
  final dir = await getTemporaryDirectory();
  final f = File('${dir.path}/$filename');
  await f.writeAsBytes(bytes, flush: true);
  await OpenFilex.open(f.path, type: 'application/pdf');
}
