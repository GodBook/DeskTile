import 'dart:convert';
import 'dart:io';

import 'package:desktile/core/import/course_info_dto.dart';
import 'package:desktile/core/import/csv_importer.dart';
import 'package:desktile/core/models/course.dart';
import 'package:desktile/core/models/exam.dart';
import 'package:desktile/core/models/settings.dart';
import 'package:desktile/core/week_math.dart';
import 'package:desktile/data/app_state.dart';
import 'package:desktile/data/store.dart';
import 'package:desktile/data/widget_position.dart';
import 'package:desktile/ui/pages/exams_page.dart';
import 'package:desktile/ui/pages/import_export_page.dart';
import 'package:desktile/ui/pages/timetable_page.dart';
import 'package:desktile/ui/widget_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// 用真实的 DataStore（临时目录）装配 AppState。
///
/// testWidgets 跑在 fake async 区里，真实的文件 IO 必须放到 [WidgetTester.runAsync]
/// 里才会完成，否则 await 永远挂住。
Future<AppState> _makeState(
  WidgetTester tester, {
  List<Exam> exams = const [],
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
      courses: [...base.courses, const Course(id: 'c_today', name: '今天的课')],
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
    await store.save(AppData(
      timetables: [withToday],
      activeTimetableId: 't1',
      exams: exams,
      settings: settings,
    ));
    state = AppState(store: store);
    await state.load();
  });
  return state;
}

Widget _host(AppState state, Widget child) => AppScope(
      state: state,
      child: MaterialApp(home: Scaffold(body: child)),
    );

void main() {
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

  testWidgets('考试页：列出倒计时、考场和座位，考完的折叠起来', (tester) async {
    final state = await _makeState(tester, exams: [
      Exam(
        id: 'e1',
        name: '高等数学 期末',
        startAt: DateTime.now().add(const Duration(days: 12, hours: 3, minutes: 1)),
        room: '教三-305',
        seat: '18',
      ),
      Exam(
        id: 'e2',
        name: '已经考完的',
        startAt: DateTime.now().subtract(const Duration(days: 3)),
      ),
    ]);
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
    final state = await _makeState(tester, exams: [
      Exam(
        id: 'e1',
        name: '线性代数 期末',
        startAt: DateTime.now().add(const Duration(days: 5)),
      ),
    ]);
    await tester.pumpWidget(WidgetApp(
      state: state,
      positionStore: WidgetPositionStore(state.store),
    ));
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
    await tester.pumpWidget(WidgetApp(
      state: state,
      positionStore: WidgetPositionStore(state.store),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('第 1 周 · '), findsOneWidget);
    expect(find.text('今日课程'), findsNothing);
  });

  testWidgets('导入预览：确认后整表覆盖，课程数与警告都对', (tester) async {
    final state = await _makeState(tester);
    late ImportedSchedule imported;
    await tester.runAsync(() async {
      final csv = utf8.decode(File('docs/示例课表.csv').readAsBytesSync());
      imported = importCsv(csv, totalWeeks: 16);
    });

    await tester.pumpWidget(_host(
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
    ));
    await tester.tap(find.text('打开导入预览'));
    await tester.pumpAndSettle();

    expect(find.text('导入预览'), findsOneWidget);
    expect(find.textContaining('解析到 8 门课、9 个上课时段'), findsOneWidget);
    expect(find.textContaining('会覆盖当前课表'), findsOneWidget);

    await tester.tap(find.text('导入并覆盖'));
    // putTimetable 要写盘，交给 runAsync 真正跑完
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();

    final t = state.activeTimetable!;
    expect(t.courses.length, 8);
    expect(t.sessions.length, 9);
    expect(t.courses.map((c) => c.name), contains('高等数学A'));
  });
}
