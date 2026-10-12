import 'package:flutter/material.dart';

/// 全局设计 token（苹果风：浅灰底、白卡片、系统蓝）
/// 所有页面只许用这里的值，不许硬编码颜色/字号/圆角。
class AppColors {
  static const bg = Color(0xFFF2F2F7);
  static const card = Colors.white;
  static const primary = Color(0xFF007AFF);
  static const ink = Color(0xFF1C1C1E);
  static const secondary = Color(0xFF8E8E93);
  static const line = Color(0xFFE5E5EA);
  static const success = Color(0xFF34C759);
  static const warning = Color(0xFFFF9500);
  static const danger = Color(0xFFFF3B30);
}

class AppSpace {
  static const page = 16.0;
  static const gap = 12.0;
  static const radiusCard = 18.0;
  static const radiusField = 14.0;
}

class AppText {
  static const title = TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.ink, height: 1.3);
  static const body = TextStyle(fontSize: 17, color: AppColors.ink, height: 1.4);
  static const secondary = TextStyle(fontSize: 15, color: AppColors.secondary, height: 1.4);
  static const bigButton = TextStyle(fontSize: 20, fontWeight: FontWeight.bold);
}

ThemeData buildAppTheme() {
  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary).copyWith(primary: AppColors.primary),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg,
      foregroundColor: AppColors.ink,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: AppText.title,
    ),
    textTheme: const TextTheme(
      bodyLarge: AppText.body,
      bodyMedium: AppText.body,
      titleLarge: AppText.title,
    ),
    cardTheme: CardThemeData(
      color: AppColors.card,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpace.radiusCard),
        side: const BorderSide(color: AppColors.line),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.card,
      hintStyle: AppText.secondary,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpace.radiusField),
        borderSide: const BorderSide(color: AppColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpace.radiusField),
        borderSide: const BorderSide(color: AppColors.line),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(64, 52),
        textStyle: AppText.bigButton,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpace.radiusField)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 52),
        textStyle: AppText.bigButton,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpace.radiusField)),
      ),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppColors.card,
      selectedItemColor: AppColors.primary,
      unselectedItemColor: AppColors.secondary,
    ),
  );
}

/// 通用状态件：错误带重试、空态带说明
class AppErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const AppErrorCard({super.key, required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off, size: 40, color: AppColors.secondary),
          const SizedBox(height: 8),
          Text(message, style: AppText.secondary, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('重试')),
        ]),
      ),
    );
  }
}

class AppEmptyView extends StatelessWidget {
  final String text;
  const AppEmptyView({super.key, required this.text});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Center(child: Text(text, style: AppText.secondary, textAlign: TextAlign.center)),
    );
  }
}
