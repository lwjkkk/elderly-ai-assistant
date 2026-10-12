import 'package:flutter/material.dart';
import 'config.dart';
import 'services/api.dart';
import 'theme.dart';
import 'pages/login_page.dart';
import 'pages/elder_home.dart';
import 'pages/family_home.dart';
import 'pages/tabs/hub_pages.dart' show chatScale;

void main() { runApp(const ElderApp()); }

class ElderApp extends StatelessWidget {
  const ElderApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '老年助手',
      theme: buildAppTheme(),
      builder: (context, child) {
        return ValueListenableBuilder<double>(
          valueListenable: chatScale,
          builder: (c, scale, _) => MediaQuery(
            data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
        );
      },
      home: FutureBuilder<String?>(
        future: ApiService.getToken(),
        builder: (c, s) {
          if (s.connectionState == ConnectionState.waiting) {
            return Scaffold(body: Center(child: CircularProgressIndicator(color: const Color(0xFF345C87))));
          }
          if (s.data == null) return const LoginPage();
          return FutureBuilder<String?>(
            future: ApiService.getRole(),
            builder: (c2, r) {
              if (r.connectionState == ConnectionState.waiting) {
                return Scaffold(body: Center(child: CircularProgressIndicator(color: const Color(0xFF345C87))));
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