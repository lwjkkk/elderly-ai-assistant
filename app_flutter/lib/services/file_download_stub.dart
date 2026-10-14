/// 默认实现（兜底，理论不可达）。
Future<void> downloadBytes(List<int> bytes, String filename) {
  throw UnsupportedError('download not supported on this platform');
}

/// 默认实现（该平台不支持）。
Future<String?> saveAndOpenPdf(List<int> bytes, String filename) {
  throw UnsupportedError('pdf export not supported on this platform');
}
