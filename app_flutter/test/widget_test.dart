import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:elderly_ai_assistant/main.dart';
import 'package:elderly_ai_assistant/pages/login_page.dart';

void main() {
  testWidgets('Signed-out app opens the login page', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const ElderApp());
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(LoginPage), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
