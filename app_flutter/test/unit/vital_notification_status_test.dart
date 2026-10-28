import 'package:flutter_test/flutter_test.dart';
import 'package:elderly_ai_assistant/services/health/vital_notification_status.dart';

void main() {
  test('recorded is not described as delivered to a phone', () {
    final message = vitalNotificationFeedback('recorded');
    expect(message, contains('服务端记录'));
    expect(message, contains('尚未确认手机送达'));
  });

  test('all backend notification states have useful feedback', () {
    for (final status in [
      'no_alert',
      'no_recipients',
      'recorded',
      'submitted',
      'pending',
      'failed',
      'partial',
      'suppressed',
    ]) {
      expect(vitalNotificationFeedback(status), isNotEmpty, reason: status);
    }
  });
}
