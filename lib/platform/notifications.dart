import 'dart:async';
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../core/models/settings.dart';
import '../core/models/task_item.dart';
import '../core/models/timetable.dart';
import '../core/reminder_plan.dart';
import '../core/task_reminder_plan.dart';
import 'windows_registry.dart';

/// 早八提醒的调度。
///
/// 提醒计划由 [buildReminders] 纯函数算出，这里只负责把它变成系统通知：
/// 每次重排都先 cancelAll 再全量写入，靠 [PlannedReminder.id] 的决定性避免重复。
class ReminderService {
  ReminderService({this.onTaskSnooze});

  final Future<void> Function(String taskId)? onTaskSnooze;

  static const appName = 'DeskTile 课表岛';
  static const aumid = 'DeskTile.KeBiaoDao.Desktop';
  static const androidNotificationIconResource = 'ic_notification';
  static const _guid = '4d1b2f80-3c7a-4e21-9f6d-8c5a1e7b9042';

  /// 一次排多少天。配合每天 00:05 的重排，足够覆盖。
  static const scheduleDays = 7;
  static const taskSnoozeAction = 'task_snooze_10';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _ready = false;
  bool _timezoneReady = false;
  tz.Location _scheduleLocation = tz.UTC;
  String? _lastError;

  bool get ready => _ready;
  String? get lastError => _lastError;

  /// 初始化 timezone 数据库。Windows 端沿用 UTC（插件按绝对时间戳调度），
  /// Android 端则必须使用设备的 IANA 时区，否则夏令时或非 UTC 时区会错时。
  Future<void> _initTimezone() async {
    if (_timezoneReady) return;
    tz_data.initializeTimeZones();
    _scheduleLocation = tz.UTC;
    if (Platform.isAndroid) {
      try {
        final info = await FlutterTimezone.getLocalTimezone();
        _scheduleLocation = tz.getLocation(info.identifier);
      } catch (e) {
        // 设备返回未知时区时仍让通知可用；UTC 是明确且可诊断的兜底。
        _lastError ??= '读取设备时区失败：$e';
      }
    }
    tz.setLocalLocation(_scheduleLocation);
    _timezoneReady = true;
  }

  static String get iconPath {
    final dir = File(Platform.resolvedExecutable).parent.path;
    return '$dir${Platform.pathSeparator}data${Platform.pathSeparator}'
        'flutter_assets${Platform.pathSeparator}assets'
        '${Platform.pathSeparator}tray_icon.ico';
  }

  Future<bool> init() async {
    if (_ready) return true;
    try {
      await _initTimezone();
      if (Platform.isWindows) await _registerToastSender();
      final ok = await _plugin.initialize(
        settings: InitializationSettings(
          android: const AndroidInitializationSettings(
            androidNotificationIconResource,
          ),
          windows: WindowsInitializationSettings(
            appName: appName,
            appUserModelId: aumid,
            guid: _guid,
            iconPath: File(iconPath).existsSync() ? iconPath : null,
          ),
        ),
        onDidReceiveNotificationResponse: _handleNotificationResponse,
      );
      _ready = ok ?? false;
      if (!_ready) _lastError = '通知插件初始化返回失败';
    } catch (e) {
      _ready = false;
      _lastError = '$e';
    }
    return _ready;
  }

  void _handleNotificationResponse(NotificationResponse response) {
    String? taskId;
    final action = response.actionId ?? '';
    if (action == taskSnoozeAction &&
        response.payload?.startsWith('task:') == true) {
      taskId = response.payload!.substring('task:'.length);
    } else if (action.startsWith('$taskSnoozeAction:')) {
      taskId = action.substring(taskSnoozeAction.length + 1);
    }
    final handler = onTaskSnooze;
    if (taskId != null && taskId.isNotEmpty && handler != null) {
      unawaited(handler(taskId));
    }
  }

  /// 由设置页的明确用户操作触发。精准闹钟授权可能打开系统设置页，因此
  /// 不能在 `runApp` 前或 WorkManager 后台任务里静默调用。
  Future<bool> requestAndroidPermissions() async {
    if (!Platform.isAndroid) return true;
    if (!_ready && !await init()) return false;
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final notification =
          await android?.requestNotificationsPermission() ?? false;
      final exact = await android?.requestExactAlarmsPermission() ?? false;
      return notification && exact;
    } catch (e) {
      _lastError = '$e';
      return false;
    }
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
    Iterable<Timetable> timetables = const [],
    Iterable<TaskItem> tasks = const [],
    required AppSettings settings,
    DateTime? now,
  }) async {
    if (!_ready && !await init()) return 0;
    try {
      await _plugin.cancelAll();
    } catch (e) {
      _lastError = '$e';
    }
    final instant = now ?? DateTime.now();
    final reminders = timetable == null
        ? const <PlannedReminder>[]
        : buildReminders(
            timetable: timetable,
            settings: settings,
            from: instant,
            daysAhead: scheduleDays,
          );
    final taskReminders = buildTaskReminders(
      tasks: tasks,
      timetables: timetables,
      settings: settings,
      from: instant,
    );

    var count = 0;
    for (final r in reminders) {
      try {
        await _plugin.zonedSchedule(
          id: r.id,
          title: r.title,
          body: r.body,
          scheduledDate: tz.TZDateTime.from(r.fireAt, _scheduleLocation),
          notificationDetails: _details,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        );
        count++;
      } catch (e) {
        _lastError = '$e';
      }
    }
    for (final r in taskReminders) {
      try {
        await _plugin.zonedSchedule(
          id: r.id,
          title: r.title,
          body: r.body,
          scheduledDate: tz.TZDateTime.from(r.fireAt, _scheduleLocation),
          notificationDetails: _taskDetails(r.taskId),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          payload: 'task:${r.taskId}',
        );
        count++;
      } catch (e) {
        _lastError = '$e';
      }
    }
    return count;
  }

  /// 设置页里的「测试提醒」：10 秒后弹一条，用来确认通知链路是通的。
  Future<bool> scheduleTest({
    Duration delay = const Duration(seconds: 10),
  }) async {
    if (!_ready && !await init()) return false;
    if (Platform.isAndroid && !await requestAndroidPermissions()) return false;
    try {
      await _plugin.zonedSchedule(
        id: 999000,
        title: '早八提醒：测试课程',
        body: '08:00 上课 · 第1-2节 · 教三-305',
        scheduledDate: tz.TZDateTime.from(
          DateTime.now().add(delay),
          _scheduleLocation,
        ),
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

  static NotificationDetails _taskDetails(String taskId) => NotificationDetails(
    windows: WindowsNotificationDetails(
      actions: [
        WindowsAction(
          content: '10 分钟后提醒',
          arguments: '$taskSnoozeAction:$taskId',
        ),
      ],
    ),
    android: const AndroidNotificationDetails(
      'desktile_task_reminder',
      '作业与待办提醒',
      channelDescription: '作业和待办事项的截止提醒',
      importance: Importance.max,
      priority: Priority.high,
      actions: [
        AndroidNotificationAction(
          taskSnoozeAction,
          '10 分钟后提醒',
          showsUserInterface: true,
        ),
      ],
    ),
  );
}
