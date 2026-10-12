import 'dart:io';

import 'package:flutter/material.dart';

/// 柔和风设计 token：低饱和蓝 + 柔和浅底 + 大圆角。
/// 长辈端/家属端共用这一套，只调字号与密度，不另起配色。
class AfuColors {
  static const bg = Color(0xFFF4F6FB);
  static const card = Colors.white;
  static const primary = Color(0xFF8AA9DE);
  static const primaryDeep = Color(0xFF5C7FBC);
  static const primarySoft = Color(0xFFE8EFFD);
  static const ink = Color(0xFF1A2333);
  static const secondary = Color(0xFF6B7690);
  static const line = Color(0xFFE6EAF3);
  static const bubbleAi = Colors.white;
  static const success = Color(0xFF4CAF7D);
  static const warning = Color(0xFFE8A33D);
  static const danger = Color(0xFFE57373);
}

const kAvatarAssets = <String>[
  'assets/avatars/avatar1.png',
  'assets/avatars/avatar2.png',
  'assets/avatars/avatar3.png',
  'assets/avatars/avatar4.png',
];

/// 头像解析：预设走 Asset，注册页自定义上传的本地照片走 File。
ImageProvider avatarImage(String path) {
  if (kAvatarAssets.contains(path)) return AssetImage(path);
  try {
    if (File(path).existsSync()) return FileImage(File(path));
  } catch (_) {}
  return const AssetImage('assets/avatars/avatar1.png');
}
class AfuRadius {

  static const card = 20.0;
  static const bubble = 20.0;
  static const field = 24.0;
  static const button = 28.0;
}

class AfuSpace {
  static const page = 20.0;
  static const gap = 12.0;
  static const section = 24.0;
}

class AfuMotion {
  static const bubbleIn = Duration(milliseconds: 300);
  static const pageFade = Duration(milliseconds: 250);
  static const pressScale = 0.96;
  static const skeletonPeriod = Duration(milliseconds: 1600);
}

/// 长辈端字阶：最小 18sp，全部白底黑字高对比。
class AfuElderText {
  static const appTitle = TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AfuColors.ink, height: 1.3);
  static const body = TextStyle(fontSize: 19, color: AfuColors.ink, height: 1.5);
  static const secondary = TextStyle(fontSize: 18, color: AfuColors.secondary, height: 1.4);
  static const button = TextStyle(fontSize: 20, fontWeight: FontWeight.w700);
}

/// 家属端字阶：同风格，字号缩小、密度更高。
class AfuFamilyText {
  static const appTitle = TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AfuColors.ink, height: 1.3);
  static const body = TextStyle(fontSize: 16, color: AfuColors.ink, height: 1.45);
  static const secondary = TextStyle(fontSize: 14, color: AfuColors.secondary, height: 1.4);
  static const button = TextStyle(fontSize: 17, fontWeight: FontWeight.w600);
}

ThemeData buildAfuTheme({required bool elder}) {
  final title = elder ? AfuElderText.appTitle : AfuFamilyText.appTitle;
  final body = elder ? AfuElderText.body : AfuFamilyText.body;
  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: AfuColors.bg,
    colorScheme: ColorScheme.fromSeed(seedColor: AfuColors.primary).copyWith(
      primary: AfuColors.primary,
      surface: AfuColors.card,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: AfuColors.bg,
      foregroundColor: AfuColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: title,
    ),
    textTheme: TextTheme(bodyLarge: body, bodyMedium: body, titleLarge: title),
    cardTheme: CardThemeData(
      color: AfuColors.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AfuRadius.card),
        side: const BorderSide(color: AfuColors.line),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AfuColors.card,
      hintStyle: TextStyle(color: AfuColors.secondary, fontSize: elder ? 19 : 16),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AfuRadius.field),
        borderSide: const BorderSide(color: AfuColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AfuRadius.field),
        borderSide: const BorderSide(color: AfuColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AfuRadius.field),
        borderSide: const BorderSide(color: AfuColors.primary, width: 2),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AfuColors.primary,
        foregroundColor: Colors.white,
        minimumSize: Size(64, elder ? 60 : 52),
        textStyle: elder ? AfuElderText.button : AfuFamilyText.button,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AfuRadius.button)),
      ),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AfuColors.card,
      selectedItemColor: AfuColors.primaryDeep,
      unselectedItemColor: AfuColors.secondary,
    ),
  );
}
