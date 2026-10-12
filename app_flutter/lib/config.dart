class AppConfig {
  /// Android 模拟器访问本机后端用 10.0.2.2，真机改成电脑局域网 IP，例如 http://192.168.1.5:8000
  /// 联调地址通过 --dart-define=API_BASE=... 传入，不再手改本文件。
  /// Edge 本机：--dart-define=API_BASE=http://192.168.3.22:8001
  /// 安卓模拟器默认 10.0.2.2，真机填电脑局域网 IP。
  static const String baseUrl = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'http://10.0.2.2:8000',
  );

  static const double minButtonHeight = 56;
  static const double elderFontBase = 22;
}
