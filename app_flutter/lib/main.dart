import 'package:flutter/material.dart';
import 'services/api.dart';
import 'services/location_access.dart';
import 'theme.dart';
import 'pages/login_page.dart';
import 'pages/elder_home.dart';
import 'pages/family_home.dart';
import 'pages/tabs/hub_pages.dart' show chatScale;

void main() {
  runApp(const ElderApp());
}

class ElderApp extends StatefulWidget {
  const ElderApp({super.key});

  @override
  State<ElderApp> createState() => _ElderAppState();
}

class _ElderAppState extends State<ElderApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _navigatorKey.currentContext;
      if (context != null) LocationAccess.onStartup(context);
    });
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
