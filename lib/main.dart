import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'data/app_state.dart';
import 'data/store.dart';
import 'data/widget_position.dart';
import 'platform/android_background.dart';
import 'platform/android_widget.dart';
import 'platform/desktop_window.dart';
import 'platform/notifications.dart';
import 'platform/single_instance.dart';
import 'platform/tray.dart';
import 'ui/app.dart';
import 'ui/widget_app.dart';

/// 一个可执行文件，两种运行模式：
///   desktile.exe            -> 主窗口（编辑课表、导入导出、设置）
///   desktile.exe --widget   -> 桌面挂件 + 托盘，常驻，负责排提醒
///
/// Flutter stable 目前不支持多窗口，所以两者是两个进程；数据靠同一个 JSON
/// 文件同步，挂件监听文件变化。
Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = DataStore();
  if (Platform.isAndroid) {
    await _runAndroidMain(store);
    return;
  }
  if (isWidgetMode(args)) {
    await _runWidget(store);
  } else {
    await _runMainWindow(store);
  }
}

/// Android 只有一个 Flutter 主界面；桌面端的单实例、托盘和无边框挂件
/// 都不应在这里初始化。课表变化时同步一份纯文本快照给 Glance 小组件。
Future<void> _runAndroidMain(DataStore store) async {
  final state = AppState(store: store);
  await state.load();

  late final ReminderService reminders;
  reminders = ReminderService(
    onTaskSnooze: (taskId) => state.snoozeTask(taskId),
  );
  runApp(MainApp(state: state, reminders: reminders));

  var syncing = false;
  var syncAgain = false;
  var reminderSyncPending = false;
  var debouncedReminderSync = false;
  Timer? debounce;
  var lastTimetable = state.activeTimetable;
  var lastTasks = state.tasks;
  var lastSettings = state.settings;

  Future<void> sync({bool remindersToo = false}) async {
    reminderSyncPending = reminderSyncPending || remindersToo;
    if (syncing) {
      syncAgain = true;
      return;
    }
    syncing = true;
    do {
      syncAgain = false;
      final shouldSyncReminders = reminderSyncPending;
      reminderSyncPending = false;
      await AndroidWidgetService.update(
        timetable: state.activeTimetable,
        exams: state.exams,
      );
      if (shouldSyncReminders) {
        await reminders.reschedule(
          timetable: state.activeTimetable,
          timetables: state.timetables,
          tasks: state.tasks,
          settings: state.settings,
        );
      }
    } while (syncAgain || reminderSyncPending);
    syncing = false;
  }

  void scheduleSync() {
    final timetableChanged = !identical(lastTimetable, state.activeTimetable);
    final tasksChanged = !identical(lastTasks, state.tasks);
    final settingsChanged = !identical(lastSettings, state.settings);
    lastTimetable = state.activeTimetable;
    lastTasks = state.tasks;
    lastSettings = state.settings;
    debouncedReminderSync =
        debouncedReminderSync ||
        timetableChanged ||
        tasksChanged ||
        settingsChanged;
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 300), () {
      final shouldSyncReminders = debouncedReminderSync;
      debouncedReminderSync = false;
      unawaited(sync(remindersToo: shouldSyncReminders));
    });
  }

  state.addListener(scheduleSync);
  await reminders.init();
  await sync(remindersToo: true);
  await initializeAndroidBackgroundWork();

  // 前台打开时让倒计时保持新鲜；后台由 WorkManager 接手。
  Timer.periodic(const Duration(minutes: 1), (_) => unawaited(sync()));
}

Future<void> _runMainWindow(DataStore store) async {
  final instance = await SingleInstance.acquire(
    SingleInstance.mainPort,
    onActivate: () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );
  // 已经有一个主窗口在跑，刚才已经把它叫到前面了。
  if (instance == null) exit(0);

  final state = AppState(store: store);
  await state.load();
  await setupMainWindow();

  late final ReminderService reminders;
  reminders = ReminderService(
    onTaskSnooze: (taskId) => state.snoozeTask(taskId),
  );
  await reminders.init();
  final scheduled = await reminders.reschedule(
    timetable: state.activeTimetable,
    timetables: state.timetables,
    tasks: state.tasks,
    settings: state.settings,
  );
  debugPrint(
    '[DeskTile] 主窗口启动，提醒已排定 $scheduled 条'
    '${reminders.lastError == null ? '' : '，最近一次错误：${reminders.lastError}'}',
  );

  Timer? reminderDebounce;
  state.addListener(() {
    reminderDebounce?.cancel();
    reminderDebounce = Timer(const Duration(milliseconds: 300), () {
      unawaited(
        reminders.reschedule(
          timetable: state.activeTimetable,
          timetables: state.timetables,
          tasks: state.tasks,
          settings: state.settings,
        ),
      );
    });
  });

  runApp(MainApp(state: state, reminders: reminders));
}

Future<void> _runWidget(DataStore store) async {
  final instance = await SingleInstance.acquire(
    SingleInstance.widgetPort,
    onActivate: windowManager.show,
  );
  if (instance == null) exit(0);

  final state = AppState(store: store, readOnly: true);
  await state.load();

  final positionStore = WidgetPositionStore(store);
  await setupWidgetWindow(state.settings, await positionStore.load());
  state.startWatching();

  late final ReminderService reminders;
  reminders = ReminderService(
    onTaskSnooze: (taskId) => state.snoozeTaskSafely(taskId),
  );
  await reminders.init();

  Future<void> reschedule() async {
    final n = await reminders.reschedule(
      timetable: state.activeTimetable,
      timetables: state.timetables,
      tasks: state.tasks,
      settings: state.settings,
    );
    final pending = await reminders.pendingCount();
    debugPrint(
      '[DeskTile] 挂件重排提醒 $n 条，系统里待触发 $pending 条'
      '${reminders.lastError == null ? '' : '，最近一次错误：${reminders.lastError}'}',
    );
  }

  await reschedule();

  // 数据或设置变了就重排提醒，同时让窗口外观跟上设置。
  var lastSettings = state.settings;
  state.addListener(() {
    final s = state.settings;
    if (s.widgetForm != lastSettings.widgetForm ||
        s.widgetOpacity != lastSettings.widgetOpacity ||
        s.widgetAlwaysOnBottom != lastSettings.widgetAlwaysOnBottom) {
      applyWidgetAppearance(s);
    }
    lastSettings = s;
    reschedule();
  });

  _armDailyRefresh(reschedule);

  final tray = WidgetTray(
    readSettings: () => state.settings,
    onSettingsChanged: (next) => state.mutateSettingsSafely((_) => next),
    onQuit: () async {
      await instance.release();
      await windowManager.destroy();
      exit(0);
    },
  );
  await tray.init();

  runApp(WidgetApp(state: state, positionStore: positionStore));
}

/// 每天 00:05 重排一次，滚动覆盖未来 7 天。
void _armDailyRefresh(Future<void> Function() reschedule) {
  void schedule() {
    final now = DateTime.now();
    var next = DateTime(now.year, now.month, now.day, 0, 5);
    if (!next.isAfter(now)) next = next.add(const Duration(days: 1));
    Timer(next.difference(now), () async {
      await reschedule();
      schedule();
    });
  }

  schedule();
}
