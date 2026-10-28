class AppConfig {
  /// 发布/真机 APK 必须在构建时传入已部署后端的 HTTPS 地址：
  /// --dart-define=API_BASE=https://api.example.com
  /// 未传入时仅适用于 Android 模拟器访问本机后端。
  static const String baseUrl = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'http://10.0.2.2:8000',
  );

  static const double minButtonHeight = 56;
  static const double elderFontBase = 22;
}
