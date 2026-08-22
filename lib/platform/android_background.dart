import 'dart:developer' as developer;
import 'dart:io';

import 'package:workmanager/workmanager.dart';

import '../data/store.dart';
import 'android_widget.dart';
import 'notifications.dart';

const _widgetTask = 'desktile_widget_refresh';
const _reminderTask = 'desktile_reminder_refresh';
const _reminderWorkV2 = 'desktile_reminder_refresh_v2';

/// WorkManager 会在独立 Flutter isolate 里调用这个入口。
@pragma('vm:entry-point')
void androidBackgroundDispatcher() {
  Workmanager().executeTask((task, _) async {
    if (!Platform.isAndroid) return true;
    if (task != _widgetTask && task != _reminderTask) {
      // 旧版本或第三方调试触发的未知任务不应无限重试。
      return true;
    }

    try {
      final data = await DataStore().load();
      switch (task) {
        case _widgetTask:
          return await AndroidWidgetService.update(
            timetable: data.activeTimetable,
            exams: data.exams,
          );
        case _reminderTask:
          final reminders = ReminderService();
          if (!await reminders.init()) return false;
          await reminders.reschedule(
            timetable: data.activeTimetable,
            settings: data.settings,
          );
          return true;
        default:
          throw StateError('无法识别 Android 后台任务：$task');
      }
    } catch (error, stackTrace) {
      developer.log(
        'Android 后台任务执行失败：$task',
        name: 'desktile.background',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  });
}

/// 小组件每 30 分钟重新计算下一节课；提醒每天 00:05 左右滚动重排。
/// WorkManager 的执行时间由 Android 调度，不保证精确到分钟。
Future<void> initializeAndroidBackgroundWork() async {
  if (!Platform.isAndroid) return;
  final work = Workmanager();
  await work.initialize(androidBackgroundDispatcher);
  await work.registerPeriodicTask(
    _widgetTask,
    _widgetTask,
    frequency: const Duration(minutes: 30),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
  );

  final now = DateTime.now();

  // v1 显式设置了 30 分钟 flex。WorkManager 会把首次执行推迟到
  // initialDelay + (24h - flex)，先取消它再用新名称迁移到正确配置。
  await work.cancelByUniqueName(_reminderTask);
  await work.registerPeriodicTask(
    _reminderWorkV2,
    _reminderTask,
    frequency: const Duration(days: 1),
    initialDelay: androidReminderRefreshDelay(now),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
  );
}

/// 从 [now] 起到下一个本地时间 00:05 的时长。
///
/// 用日历日期构造“明天”，避免夏令时切换日直接加 24 小时造成墙上时间漂移。
Duration androidReminderRefreshDelay(DateTime now) {
  var next = DateTime(now.year, now.month, now.day, 0, 5);
  if (!next.isAfter(now)) {
    next = DateTime(now.year, now.month, now.day + 1, 0, 5);
  }
  return next.difference(now);
}
