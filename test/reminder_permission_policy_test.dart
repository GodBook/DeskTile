import 'package:desktile/ui/pages/settings_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Android 提醒权限请求策略', () {
    test('从关闭切到开启时请求', () {
      expect(
        shouldRequestAndroidReminderPermissions(
          isAndroid: true,
          wasEnabled: false,
          willBeEnabled: true,
        ),
        isTrue,
      );
    });

    test('提醒已开启时修改普通设置不重复请求', () {
      expect(
        shouldRequestAndroidReminderPermissions(
          isAndroid: true,
          wasEnabled: true,
          willBeEnabled: true,
        ),
        isFalse,
      );
    });

    test('作业待办提醒从关闭切到开启时请求', () {
      expect(
        shouldRequestAndroidReminderPermissions(
          isAndroid: true,
          wasEnabled: false,
          willBeEnabled: false,
          wasTaskEnabled: false,
          willTaskBeEnabled: true,
        ),
        isTrue,
      );
    });

    test('作业待办提醒已开启时不重复请求', () {
      expect(
        shouldRequestAndroidReminderPermissions(
          isAndroid: true,
          wasEnabled: false,
          willBeEnabled: false,
          wasTaskEnabled: true,
          willTaskBeEnabled: true,
        ),
        isFalse,
      );
    });

    test('关闭提醒或保持关闭时不请求', () {
      expect(
        shouldRequestAndroidReminderPermissions(
          isAndroid: true,
          wasEnabled: true,
          willBeEnabled: false,
        ),
        isFalse,
      );
      expect(
        shouldRequestAndroidReminderPermissions(
          isAndroid: true,
          wasEnabled: false,
          willBeEnabled: false,
        ),
        isFalse,
      );
    });

    test('用户明确重新排定时请求', () {
      expect(
        shouldRequestAndroidReminderPermissions(
          isAndroid: true,
          wasEnabled: true,
          willBeEnabled: true,
          explicitlyRequested: true,
        ),
        isTrue,
      );
      expect(
        shouldRequestAndroidReminderPermissions(
          isAndroid: true,
          wasEnabled: false,
          willBeEnabled: false,
          explicitlyRequested: true,
        ),
        isTrue,
      );
    });

    test('非 Android 平台不请求 Android 权限', () {
      expect(
        shouldRequestAndroidReminderPermissions(
          isAndroid: false,
          wasEnabled: false,
          willBeEnabled: true,
          explicitlyRequested: true,
        ),
        isFalse,
      );
    });
  });
}
