import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'services/api.dart';
import 'services/platform/location_access.dart';
import 'services/medication/medication_notification_service.dart';
import 'theme.dart';
import 'package:elderly_ai_assistant/pages/auth/login_page.dart';
import 'package:elderly_ai_assistant/pages/home/elder_home.dart';
import 'package:elderly_ai_assistant/pages/home/family_home.dart';
import 'pages/tabs/hub_pages.dart' show chatScale;

void main() {
  runApp(const ElderApp());
}

class ElderApp extends StatefulWidget {
  const ElderApp({super.key});

  @override
  State<ElderApp> createState() => _ElderAppState();
}

class _ElderAppState extends State<ElderApp> with WidgetsBindingObserver {
  final _navigatorKey = GlobalKey<NavigatorState>();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final context = _navigatorKey.currentContext;
      if (context != null) LocationAccess.onStartup(context);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 从后台恢复时重新对账，保证另一台设备的修改/删除同步到本机
    if (state == AppLifecycleState.resumed) {
      MedicationNotificationService.instance.syncWithServer();
    }
  }

  // 字号变化会重建主题；复用登录查询，避免反复移除正在使用的页面。
  late final Future<String?> _token = ApiService.getToken();
  late final Future<String?> _role = ApiService.getRole();
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      title: '老年助手',
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: buildAppTheme(),
      builder: (context, child) {
        return ValueListenableBuilder<double>(
          valueListenable: chatScale,
          builder: (c, scale, _) => MediaQuery(
            data:
                MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
        );
      },
      home: FutureBuilder<String?>(
        future: _token,
        builder: (c, s) {
          if (s.connectionState == ConnectionState.waiting) {
            return Scaffold(
                body: Center(
                    child: CircularProgressIndicator(
                        color: const Color(0xFF345C87))));
          }
          if (s.data == null) return const LoginPage();
          return FutureBuilder<String?>(
            future: _role,
            builder: (c2, r) {
              if (r.connectionState == ConnectionState.waiting) {
                return Scaffold(
                    body: Center(
                        child: CircularProgressIndicator(
                            color: const Color(0xFF345C87))));
              }
              if (r.data == 'family') return const FamilyHome();
              return const ElderHome();
            },
          );
        },
      ),
    );
  }
}
