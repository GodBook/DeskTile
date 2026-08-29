import 'dart:convert';
import 'dart:io';

import 'package:desktile/core/import/course_info_dto.dart';
import 'package:desktile/core/import/csv_importer.dart';
import 'package:desktile/core/import/json_importer.dart';
import 'package:desktile/core/models/course.dart';
import 'package:desktile/core/models/exam.dart';
import 'package:desktile/core/models/schedule_change.dart';
import 'package:desktile/core/models/settings.dart';
import 'package:desktile/core/models/task_item.dart';
import 'package:desktile/core/models/timetable.dart';
import 'package:desktile/core/week_math.dart';
import 'package:desktile/data/app_state.dart';
import 'package:desktile/data/store.dart';
import 'package:desktile/data/widget_position.dart';
import 'package:desktile/platform/notifications.dart';
import 'package:desktile/ui/app.dart';
import 'package:desktile/ui/pages/exams_page.dart';
import 'package:desktile/ui/pages/import_export_page.dart';
import 'package:desktile/ui/pages/tasks_page.dart';
import 'package:desktile/ui/pages/timetable_page.dart';
import 'package:desktile/ui/widget_app.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// 用真实的 DataStore（临时目录）装配 AppState。
///
/// testWidgets 跑在 fake async 区里，真实的文件 IO 必须放到 [WidgetTester.runAsync]
/// 里才会完成，否则 await 永远挂住。
Future<AppState> _makeState(
  WidgetTester tester, {
  List<Exam> exams = const [],
  List<TaskItem> tasks = const [],
  AppSettings settings = const AppSettings(),
}) async {
  late AppState state;
  await tester.runAsync(() async {
    final dir = Directory.systemTemp.createTempSync('desktile_ui');
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });
    final store = DataStore(overrideDirectory: dir);
    // 学期第一周设成本周，「本周」就稳定落在第 1 周（单周）；
    // 再补一节「今天」的课，让挂件的今日列表不依赖测试当天是星期几。
    final base = buildTestTimetable(termStart: mondayOf(DateTime.now()));
    final withToday = base.copyWith(
      courses: [
        ...base.courses,
        const Course(id: 'c_today', name: '今天的课'),
      ],
      sessions: [
        ...base.sessions,
        CourseSession(
          id: 's_today',
          courseId: 'c_today',
          day: DateTime.now().weekday,
          startSection: 11,
          endSection: 12,
          weeks: allWeeks(base.totalWeeks),
          room: '今日教室',
        ),
      ],
    );
    await store.save(
      AppData(
        timetables: [withToday],
        activeTimetableId: 't1',
        exams: exams,
        tasks: tasks,
        settings: settings,
      ),
    );
    state = AppState(store: store);
    await state.load();
  });
  return state;
}

Widget _host(AppState state, Widget child) => AppScope(
  state: state,
  child: MaterialApp(home: Scaffold(body: child)),
);

Future<void> _pressAsyncButton(WidgetTester tester, Finder buttonFinder) async {
  final callback = tester.widget<ButtonStyleButton>(buttonFinder).onPressed!;
  await tester.runAsync(() async {
    final result = (callback as dynamic)();
    if (result is Future) await result;
  });
  await tester.pumpAndSettle();
}

Future<void> _changeCheckbox(
  WidgetTester tester,
  Finder checkboxFinder,
  bool value,
) async {
  final callback = tester.widget<Checkbox>(checkboxFinder).onChanged!;
  await tester.runAsync(() async {
    final result = (callback as dynamic)(value);
    if (result is Future) await result;
  });
  await tester.pumpAndSettle();
}

void main() {
  test('Android 通知小图标资源配置完整', () {
    const iconName = ReminderService.androidNotificationIconResource;
    expect(iconName, 'ic_notification');
    expect(iconName, isNot(contains('@')));
    expect(iconName, isNot(contains('/')));

    expect(
      File('android/app/src/main/res/drawable/$iconName.xml').existsSync(),
      isTrue,
    );
    final keepRules = File('android/app/src/main/res/raw/keep.xml')
        .readAsStringSync();
    expect(keepRules, contains('@drawable/$iconName'));
  });

  testWidgets('主窗口：手机布局避开状态栏并使用底部导航', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    tester.view.padding = const FakeViewPadding(top: 24);
    addTearDown(tester.view.reset);

    final state = await _makeState(tester);
    await tester.pumpWidget(
      MainApp(state: state, reminders: ReminderService()),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(tester.getTopLeft(find.text('测试课表')).dy, greaterThan(24));
    await tester.tap(find.text('待办'));
    await tester.pumpAndSettle();
    expect(find.text('作业与待办'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('主窗口：宽屏继续使用侧边导航', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 600);
    addTearDown(tester.view.reset);

    final state = await _makeState(tester);
    await tester.pumpWidget(
      MainApp(state: state, reminders: ReminderService()),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('课程编辑器：窄屏字段能够重排且没有布局溢出', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 700);
    tester.view.padding = const FakeViewPadding(top: 24);
    addTearDown(tester.view.reset);

    final state = await _makeState(tester);
    await tester.pumpWidget(
      MainApp(state: state, reminders: ReminderService()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加课程'));
    await tester.pumpAndSettle();

    expect(find.text('课程名称 *'), findsOneWidget);
    expect(find.text('教师'), findsOneWidget);
    expect(find.text('教室'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<int>), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('周视图：默认落在本周，画出课程块、星期和节次时间', (tester) async {
    final state = await _makeState(tester);
    await tester.pumpWidget(_host(state, const TimetablePage()));
    await tester.pumpAndSettle();

    expect(find.text('测试课表'), findsOneWidget);
    expect(find.text('第 1 周 · 单周'), findsOneWidget);
    expect(find.text('周一'), findsOneWidget);
    expect(find.text('周日'), findsOneWidget);
    expect(find.text('08:00'), findsOneWidget);
    expect(find.text('添加课程'), findsOneWidget);
    expect(find.text('高等数学'), findsOneWidget);
    expect(find.text('教三-305'), findsOneWidget);
  });

  testWidgets('Android 周视图支持双指缩放网格', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 800);
      tester.view.padding = const FakeViewPadding(top: 24);
      addTearDown(tester.view.reset);

      final state = await _makeState(tester);
      await tester.pumpWidget(_host(state, const TimetablePage()));
      await tester.pumpAndSettle();

      final zoomView = find.byKey(const ValueKey('timetable-zoom-view'));
      expect(zoomView, findsOneWidget);
      final viewer = tester.widget<InteractiveViewer>(zoomView);
      expect(viewer.minScale, lessThan(1));
      expect(viewer.maxScale, greaterThan(1));

      final firstFinger = await tester.startGesture(const Offset(130, 350));
      final secondFinger = await tester.startGesture(const Offset(230, 350));
      await tester.pump();
      await firstFinger.moveBy(const Offset(-24, 0));
      await secondFinger.moveBy(const Offset(24, 0));
      await tester.pump();
      await firstFinger.up();
      await secondFinger.up();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Windows 周视图支持 Ctrl 加滚轮缩放，普通滚轮仍可滚动', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 600);
    addTearDown(tester.view.reset);

    TestPointer? mouse;
    var controlPressed = false;
    try {
      final state = await _makeState(tester);
      await tester.pumpWidget(_host(state, const TimetablePage()));
      await tester.pumpAndSettle();

      const zoomKey = ValueKey('timetable-windows-body-zoom');
      final verticalScroll = find.byKey(
        const ValueKey('timetable-vertical-scroll'),
      );
      final scrollable = find.descendant(
        of: verticalScroll,
        matching: find.byType(Scrollable),
      );
      double currentScale() =>
          tester.widget<Transform>(find.byKey(zoomKey)).transform.storage[0];

      expect(currentScale(), 1);
      final scrollableState = tester.state<ScrollableState>(scrollable);
      expect(scrollableState.position.pixels, 0);

      mouse = TestPointer(1, PointerDeviceKind.mouse);
      final pointerLocation = tester.getCenter(verticalScroll);
      await tester.sendEventToBinding(
        mouse.addPointer(location: pointerLocation),
      );
      await tester.sendEventToBinding(mouse.hover(pointerLocation));
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      controlPressed = true;
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, -120)));
      await tester.pump();

      expect(currentScale(), closeTo(1.1, 0.001));
      expect(scrollableState.position.pixels, 0);

      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      controlPressed = false;
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, 120)));
      await tester.pumpAndSettle();

      expect(currentScale(), closeTo(1.1, 0.001));
      expect(scrollableState.position.pixels, greaterThan(0));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      controlPressed = true;
      for (var i = 0; i < 30; i++) {
        await tester.sendEventToBinding(mouse.scroll(const Offset(0, -120)));
      }
      await tester.pump();
      expect(currentScale(), closeTo(2.5, 0.001));

      for (var i = 0; i < 30; i++) {
        await tester.sendEventToBinding(mouse.scroll(const Offset(0, 120)));
      }
      await tester.pump();
      expect(currentScale(), closeTo(0.65, 0.001));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      controlPressed = false;

      expect(tester.takeException(), isNull);
    } finally {
      if (controlPressed) {
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      }
      if (mouse != null) {
        await tester.sendEventToBinding(mouse.removePointer());
      }
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('周视图：单周课在第 1 周出现、第 2 周消失', (tester) async {
    final state = await _makeState(tester);
    await tester.pumpWidget(_host(state, const TimetablePage()));
    await tester.pumpAndSettle();

    expect(find.text('第 1 周 · 单周'), findsOneWidget);
    expect(find.text('线性代数'), findsOneWidget);

    await tester.tap(find.byTooltip('下一周'));
    await tester.pumpAndSettle();

    expect(find.text('第 2 周 · 双周'), findsOneWidget);
    expect(find.text('线性代数'), findsNothing);
    expect(find.text('高等数学'), findsOneWidget, reason: '每周的课不受单双周影响');
  });

  testWidgets('临时停课：从常规课程创建后在周视图标记并写入磁盘', (tester) async {
    final state = await _makeState(tester);
    await tester.pumpWidget(_host(state, const TimetablePage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('高等数学'));
    await tester.pumpAndSettle();
    final temporaryChange = find.textContaining('临时调整');
    await tester.ensureVisible(temporaryChange);
    await tester.tap(temporaryChange);
    await tester.pumpAndSettle();

    expect(find.text('调整本次课程'), findsOneWidget);
    await tester.tap(find.text('停课'));
    await tester.pump();
    await _pressAsyncButton(tester, find.widgetWithText(FilledButton, '保存'));

    expect(find.text('停课'), findsOneWidget);
    final change = state.activeTimetable!.scheduleChanges.single;
    expect(change.type, ScheduleChangeType.cancellation);
    expect(change.originalSessionId, 's1');

    late List<ScheduleChange> persistedChanges;
    await tester.runAsync(() async {
      persistedChanges =
          (await state.store.load()).activeTimetable!.scheduleChanges;
    });
    expect(persistedChanges.single.type, ScheduleChangeType.cancellation);
    expect(persistedChanges.single.originalSessionId, 's1');
  });

  testWidgets('临时补课：从工具栏添加、显示标记并可删除', (tester) async {
    final state = await _makeState(tester);
    await tester.pumpWidget(_host(state, const TimetablePage()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('添加补课'));
    await tester.pumpAndSettle();
    expect(find.text('添加补课'), findsOneWidget);

    await _pressAsyncButton(tester, find.widgetWithText(FilledButton, '保存'));

    expect(find.text('补课'), findsOneWidget);
    final change = state.activeTimetable!.scheduleChanges.single;
    expect(change.type, ScheduleChangeType.extraClass);
    expect(change.courseId, 'c1');

    await tester.tap(find.text('补课'));
    await tester.pumpAndSettle();
    expect(find.text('删除补课'), findsOneWidget);
    await _pressAsyncButton(tester, find.widgetWithText(TextButton, '删除补课'));

    expect(find.text('补课'), findsNothing);
    expect(state.activeTimetable!.scheduleChanges, isEmpty);
  });

  testWidgets('作业待办页：320px 下工具栏、筛选和编辑器无溢出', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 700);
    addTearDown(tester.view.reset);

    final state = await _makeState(tester);
    await tester.pumpWidget(_host(state, const TasksPage()));
    await tester.pumpAndSettle();

    expect(find.text('作业与待办'), findsOneWidget);
    expect(find.text('待完成'), findsOneWidget);
    expect(find.text('已完成'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '添加事项'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('添加事项'),
      ),
      findsOneWidget,
    );
    expect(find.text('作业'), findsOneWidget);
    expect(find.text('待办'), findsOneWidget);
    expect(find.byKey(const ValueKey('task-title')), findsOneWidget);
    expect(find.byKey(const ValueKey('task-due-date')), findsOneWidget);
    expect(find.byKey(const ValueKey('task-due-time')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('作业待办页：新增课程作业、持久化、编辑并删除', (tester) async {
    final state = await _makeState(tester);
    await tester.pumpWidget(_host(state, const TasksPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '添加事项'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('task-title')), '完成高数习题');
    await tester.tap(find.byKey(const ValueKey('task-course')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('高等数学').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('标为重要'));
    await tester.pump();
    await _pressAsyncButton(tester, find.widgetWithText(FilledButton, '保存'));

    expect(state.tasks, hasLength(1));
    final taskId = state.tasks.single.id;
    expect(state.tasks.single.title, '完成高数习题');
    expect(state.tasks.single.kind, TaskKind.homework);
    expect(state.tasks.single.courseId, 'c1');
    expect(state.tasks.single.priority, TaskPriority.important);
    expect(state.tasks.single.dueAt, isNotNull);
    expect(find.text('1 项待完成'), findsOneWidget);
    expect(find.text('完成高数习题'), findsOneWidget);
    expect(find.text('高等数学'), findsOneWidget);

    late List<TaskItem> persistedTasks;
    await tester.runAsync(() async {
      persistedTasks = (await state.store.load()).tasks;
    });
    expect(persistedTasks.single.title, '完成高数习题');

    await tester.tap(find.byKey(ValueKey('task-row-$taskId')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('task-title')),
      '完成高数第二章习题',
    );
    await _pressAsyncButton(tester, find.widgetWithText(FilledButton, '保存'));
    expect(find.text('完成高数第二章习题'), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('task-row-$taskId')));
    await tester.pumpAndSettle();
    await _pressAsyncButton(tester, find.widgetWithText(TextButton, '删除'));
    expect(state.tasks, isEmpty);
    expect(find.text('完成高数第二章习题'), findsNothing);
  });

  testWidgets('作业待办页：完成和恢复会在筛选视图间移动', (tester) async {
    final now = DateTime.now();
    final state = await _makeState(
      tester,
      tasks: [
        TaskItem(
          id: 'task1',
          title: '整理实验报告',
          kind: TaskKind.todo,
          createdAt: now,
          dueAt: DateTime(now.year, now.month, now.day + 1, 18),
        ),
      ],
    );
    await tester.pumpWidget(_host(state, const TasksPage()));
    await tester.pumpAndSettle();

    expect(find.text('整理实验报告'), findsOneWidget);
    await _changeCheckbox(
      tester,
      find.byKey(const ValueKey('task-checkbox-task1')),
      true,
    );
    expect(state.tasks.single.isCompleted, isTrue);
    expect(find.text('整理实验报告'), findsNothing);
    expect(find.text('暂无待完成事项'), findsOneWidget);

    await tester.tap(find.text('已完成'));
    await tester.pumpAndSettle();
    expect(find.text('整理实验报告'), findsOneWidget);
    await _changeCheckbox(
      tester,
      find.byKey(const ValueKey('task-checkbox-task1')),
      false,
    );
    expect(state.tasks.single.isCompleted, isFalse);
    expect(find.text('整理实验报告'), findsNothing);
  });

  testWidgets('考试页：列出倒计时、考场和座位，考完的折叠起来', (tester) async {
    final state = await _makeState(
      tester,
      exams: [
        Exam(
          id: 'e1',
          name: '高等数学 期末',
          startAt: DateTime.now().add(
            const Duration(days: 12, hours: 3, minutes: 1),
          ),
          room: '教三-305',
          seat: '18',
        ),
        Exam(
          id: 'e2',
          name: '已经考完的',
          startAt: DateTime.now().subtract(const Duration(days: 3)),
        ),
      ],
    );
    await tester.pumpWidget(_host(state, const ExamsPage()));
    await tester.pumpAndSettle();

    expect(find.text('高等数学 期末'), findsOneWidget);
    expect(find.textContaining('教三-305'), findsOneWidget);
    expect(find.textContaining('座位 18'), findsOneWidget);
    expect(find.text('12 天 3 小时'), findsOneWidget);
    expect(find.text('已结束（1）'), findsOneWidget);
    expect(find.text('已经考完的'), findsNothing);
  });

  testWidgets('挂件：显示周次、下一节（含教室）和最近考试倒计时', (tester) async {
    final state = await _makeState(
      tester,
      exams: [
        Exam(
          id: 'e1',
          name: '线性代数 期末',
          startAt: DateTime.now().add(const Duration(days: 5)),
        ),
      ],
    );
    await tester.pumpWidget(
      WidgetApp(state: state, positionStore: WidgetPositionStore(state.store)),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('第 1 周 · '), findsOneWidget);
    expect(find.text('今日课程'), findsOneWidget);
    expect(find.textContaining('线性代数 期末'), findsOneWidget);
    expect(find.byTooltip('打开主窗口'), findsOneWidget);
  });

  testWidgets('挂件：迷你形态不画今日列表', (tester) async {
    final state = await _makeState(
      tester,
      settings: const AppSettings(widgetForm: WidgetForm.mini),
    );
    await tester.pumpWidget(
      WidgetApp(state: state, positionStore: WidgetPositionStore(state.store)),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('第 1 周 · '), findsOneWidget);
    expect(find.text('今日课程'), findsNothing);
  });

  testWidgets('导入预览：确认后整表覆盖，课程数与警告都对', (tester) async {
    final existingTask = TaskItem(
      id: 'existing-task',
      title: '保留的待办',
      kind: TaskKind.todo,
      createdAt: DateTime(2026, 8, 28),
    );
    final state = await _makeState(tester, tasks: [existingTask]);
    late ImportedSchedule imported;
    await tester.runAsync(() async {
      final csv = utf8.decode(File('docs/示例课表.csv').readAsBytesSync());
      imported = importCsv(csv, totalWeeks: 16);
    });

    await tester.pumpWidget(
      _host(
        state,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showImportPreview(
              context,
              fileName: '示例课表.csv',
              imported: imported,
              base: state.activeTimetable!,
            ),
            child: const Text('打开导入预览'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开导入预览'));
    await tester.pumpAndSettle();

    expect(find.text('导入预览'), findsOneWidget);
    expect(find.textContaining('解析到 8 门课、9 个上课时段'), findsOneWidget);
    expect(find.textContaining('会覆盖当前课表'), findsOneWidget);

    await tester.tap(find.text('导入并覆盖'));
    // putTimetable 要写盘，交给 runAsync 真正跑完
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();

    final t = state.activeTimetable!;
    expect(t.courses.length, 8);
    expect(t.sessions.length, 9);
    expect(t.courses.map((c) => c.name), contains('高等数学A'));
    expect(state.tasks.single.id, 'existing-task');
    expect(state.tasks.single.title, '保留的待办');
  });

  testWidgets('导入预览：完整备份替换任务并重绑到当前课表', (tester) async {
    final state = await _makeState(
      tester,
      tasks: [
        TaskItem(
          id: 'old-task',
          title: '应被替换的待办',
          kind: TaskKind.todo,
          createdAt: DateTime(2026, 8, 28),
        ),
      ],
    );
    final original = buildTestTimetable(termStart: mondayOf(DateTime.now()));
    final backupTimetable = Timetable(
      id: 'backup-table',
      name: '备份课表',
      termStart: original.termStart,
      totalWeeks: original.totalWeeks,
      timeSlots: original.timeSlots,
      showWeekend: original.showWeekend,
      courses: original.courses,
      sessions: original.sessions,
      scheduleChanges: original.scheduleChanges,
    );
    final backupTask = TaskItem(
      id: 'backup-task',
      title: '备份里的高数作业',
      kind: TaskKind.homework,
      createdAt: DateTime(2026, 8, 29, 9),
      dueAt: DateTime(2026, 8, 30, 20),
      timetableId: backupTimetable.id,
      courseId: 'c1',
      priority: TaskPriority.important,
    );
    final imported = importCourseInfosJson(
      jsonEncode({
        'schemaVersion': 3,
        'activeTimetableId': backupTimetable.id,
        'timetables': [backupTimetable.toJson()],
        'exams': const [],
        'tasks': [backupTask.toJson()],
        'settings': const {},
      }),
    );

    await tester.pumpWidget(
      _host(
        state,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showImportPreview(
              context,
              fileName: 'DeskTile-backup.json',
              imported: imported,
              base: state.activeTimetable!,
            ),
            child: const Text('打开备份预览'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开备份预览'));
    await tester.pumpAndSettle();

    expect(find.text('备份包含 1 项作业与待办'), findsOneWidget);
    expect(find.textContaining('并替换作业与待办列表'), findsOneWidget);

    await _pressAsyncButton(tester, find.widgetWithText(FilledButton, '导入并覆盖'));

    expect(state.tasks, hasLength(1));
    expect(state.tasks.single.id, 'backup-task');
    expect(state.tasks.single.title, '备份里的高数作业');
    expect(state.tasks.single.timetableId, state.activeTimetable!.id);
    expect(state.tasks.single.timetableId, 't1');
    expect(state.tasks.single.courseId, 'c1');
    expect(state.tasks.single.priority, TaskPriority.important);

    late List<TaskItem> persistedTasks;
    await tester.runAsync(() async {
      persistedTasks = (await state.store.load()).tasks;
    });
    expect(persistedTasks.single.id, 'backup-task');
    expect(persistedTasks.single.timetableId, 't1');
  });
}
