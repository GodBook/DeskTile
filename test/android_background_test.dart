import 'package:flutter_test/flutter_test.dart';

import 'package:desktile/platform/android_background.dart';

void main() {
  group('Android 每日后台刷新延迟', () {
    test('00:05 前安排在当天 00:05', () {
      final now = DateTime(2026, 8, 22, 0, 4, 30);

      expect(androidReminderRefreshDelay(now), const Duration(seconds: 30));
    });

    test('到达 00:05 后安排在次日 00:05', () {
      final now = DateTime(2026, 8, 22, 0, 5);

      expect(androidReminderRefreshDelay(now), const Duration(days: 1));
    });

    test('午夜前计算出的延迟不会跨过目标时刻', () {
      final now = DateTime(2026, 8, 22, 23, 55);

      expect(androidReminderRefreshDelay(now), const Duration(minutes: 10));
    });
  });
}
