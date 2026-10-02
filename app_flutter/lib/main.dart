import 'package:flutter/material.dart';
import 'config.dart';
import 'services/api.dart';
import 'theme.dart';
import 'pages/login_page.dart';
import 'pages/elder_home.dart';
import 'pages/family_home.dart';

void main() { runApp(const ElderApp()); }

class ElderApp extends StatelessWidget {
  const ElderApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '云栖码梦',
      theme: buildAppTheme(),
      home: FutureBuilder<String?>(
        future: ApiService.getToken(),
        builder: (c, s) {
          if (s.connectionState == ConnectionState.waiting) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          if (s.data == null) return const LoginPage();
          return FutureBuilder<String?>(
            future: ApiService.getRole(),
            builder: (c2, r) {
              if (r.connectionState == ConnectionState.waiting) {
                return const Scaffold(body: Center(child: CircularProgressIndicator()));
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