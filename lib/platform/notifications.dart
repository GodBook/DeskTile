import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../core/models/settings.dart';
import '../core/models/timetable.dart';
import '../core/reminder_plan.dart';
import 'windows_registry.dart';

/// 早八提醒的调度。
///
/// 提醒计划由 [buildReminders] 纯函数算出，这里只负责把它变成系统通知：
/// 每次重排都先 cancelAll 再全量写入，靠 [PlannedReminder.id] 的决定性避免重复。
class ReminderService {
  static const appName = 'DeskTile 课表岛';
  static const aumid = 'DeskTile.KeBiaoDao.Desktop';
  static const _guid = '4d1b2f80-3c7a-4e21-9f6d-8c5a1e7b9042';

  /// 一次排多少天。配合每天 00:05 的重排，足够覆盖。
  static const scheduleDays = 7;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _ready = false;
  String? _lastError;

  bool get ready => _ready;
  String? get lastError => _lastError;

  static String get iconPath {
    final dir = File(Platform.resolvedExecutable).parent.path;
    return '$dir${Platform.pathSeparator}data${Platform.pathSeparator}'
        'flutter_assets${Platform.pathSeparator}assets'
        '${Platform.pathSeparator}tray_icon.ico';
  }

  Future<bool> init() async {
    if (_ready) return true;
    try {
      if (Platform.isWindows) await _registerToastSender();
      final ok = await _plugin.initialize(
        settings: InitializationSettings(
          windows: WindowsInitializationSettings(
            appName: appName,
            appUserModelId: aumid,
            guid: _guid,
            iconPath: File(iconPath).existsSync() ? iconPath : null,
          ),
        ),
      );
      _ready = ok ?? false;
      if (!_ready) _lastError = '通知插件初始化返回失败';
    } catch (e) {
      _ready = false;
      _lastError = '$e';
    }
    return _ready;
  }

  /// 未打包的 Win32 程序要让 Toast 显示正确的应用名和图标，需要在
  /// HKCU\Software\Classes\AppUserModelId 下登记自己。纯用户级，不需要管理员。
  Future<void> _registerToastSender() async {
    const key = r'HKCU\Software\Classes\AppUserModelId\' + aumid;
    await WindowsRegistry.write(key, 'DisplayName', appName);
    final icon = iconPath;
    if (File(icon).existsSync()) {
      await WindowsRegistry.write(key, 'IconUri', icon);
    }
  }

  /// 重排未来几天的提醒。返回实际排上的条数。
  Future<int> reschedule({
    required Timetable? timetable,
    required AppSettings settings,
    DateTime? now,
  }) async {
    if (!_ready && !await init()) return 0;
    try {
      await _plugin.cancelAll();
    } catch (e) {
      _lastError = '$e';
    }
    if (timetable == null || !settings.reminderEnabled) return 0;

    final reminders = buildReminders(
      timetable: timetable,
      settings: settings,
      from: now ?? DateTime.now(),
      daysAhead: scheduleDays,
    );

    var count = 0;
    for (final r in reminders) {
      try {
        await _plugin.zonedSchedule(
          id: r.id,
          title: r.title,
          body: r.body,
          // Windows 端只用到绝对时刻（millisecondsSinceEpoch），
          // 所以用 UTC 表示同一瞬间即可，不必去查系统的 IANA 时区名。
          // Phase 2 接 Android 时要换成真正的本地时区。
          scheduledDate: tz.TZDateTime.from(r.fireAt, tz.UTC),
          notificationDetails: _details,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        );
        count++;
      } catch (e) {
        _lastError = '$e';
      }
    }
    return count;
  }

  /// 设置页里的「测试提醒」：10 秒后弹一条，用来确认通知链路是通的。
  Future<bool> scheduleTest({Duration delay = const Duration(seconds: 10)}) async {
    if (!_ready && !await init()) return false;
    try {
      await _plugin.zonedSchedule(
        id: 999000,
        title: '早八提醒：测试课程',
        body: '08:00 上课 · 第1-2节 · 教三-305',
        scheduledDate: tz.TZDateTime.from(DateTime.now().add(delay), tz.UTC),
        notificationDetails: _details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
      return true;
    } catch (e) {
      _lastError = '$e';
      return false;
    }
  }

  Future<int> pendingCount() async {
    try {
      final pending = await _plugin.pendingNotificationRequests();
      return pending.length;
    } catch (_) {
      return 0;
    }
  }

  Future<void> cancelAll() async {
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }

  static const NotificationDetails _details = NotificationDetails(
    windows: WindowsNotificationDetails(),
    android: AndroidNotificationDetails(
      'desktile_class_reminder',
      '上课提醒',
      channelDescription: '早八和上课前提醒',
      importance: Importance.max,
      priority: Priority.high,
    ),
  );
}
