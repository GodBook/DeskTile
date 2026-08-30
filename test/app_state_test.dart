import 'dart:io';

import 'package:desktile/core/models/settings.dart';
import 'package:desktile/core/models/task_item.dart';
import 'package:desktile/core/models/timetable.dart';
import 'package:desktile/data/app_state.dart';
import 'package:desktile/data/store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  late Directory temporaryDirectory;
  late DataStore store;

  setUp(() {
    temporaryDirectory = Directory.systemTemp.createTempSync(
      'desktile_state_test',
    );
    store = DataStore(overrideDirectory: temporaryDirectory);
  });

  tearDown(() {
    if (temporaryDirectory.existsSync()) {
      temporaryDirectory.deleteSync(recursive: true);
    }
  });

  Timetable timetable(String id, String name) {
    final source = buildTestTimetable();
    return Timetable(
      id: id,
      name: name,
      termStart: source.termStart,
      totalWeeks: source.totalWeeks,
      timeSlots: source.timeSlots,
      courses: source.courses,
      sessions: source.sessions,
    );
  }

  Future<AppState> stateWith({
    required List<Timetable> timetables,
    required String activeTimetableId,
    List<TaskItem> tasks = const [],
  }) async {
    await store.save(
      AppData(
        timetables: timetables,
        exams: const [],
        settings: const AppSettings(),
        activeTimetableId: activeTimetableId,
        tasks: tasks,
      ),
    );
    final state = AppState(store: store);
    await state.load();
    return state;
  }

  test('归档当前课表后自动切换到另一张未归档课表', () async {
    final state = await stateWith(
      timetables: [timetable('t1', '当前课表'), timetable('t2', '新学期')],
      activeTimetableId: 't1',
    );

    await state.setTimetableArchived('t1', true);

    expect(state.activeTimetable?.id, 't2');
    expect(state.timetables.first.archived, isTrue);
    expect((await store.load()).activeTimetable?.id, 't2');
  });

  test('归档唯一课表时创建 id 不重复的空白课表', () async {
    final state = await stateWith(
      timetables: [timetable('t1', '唯一课表')],
      activeTimetableId: 't1',
    );

    await state.setTimetableArchived('t1', true);

    expect(state.timetables, hasLength(2));
    expect(state.timetables.map((item) => item.id).toSet(), hasLength(2));
    expect(state.activeTimetable?.id, isNot('t1'));
    expect(state.activeTimetable?.archived, isFalse);
    expect(state.activeTimetable?.courses, isEmpty);
  });

  test('删除课表保留关联待办，但解除课程关联', () async {
    final reminderAt = DateTime(2026, 9, 7, 9);
    final state = await stateWith(
      timetables: [timetable('t1', '旧学期'), timetable('t2', '新学期')],
      activeTimetableId: 't1',
      tasks: [
        TaskItem(
          id: 'task1',
          title: '高数作业',
          kind: TaskKind.homework,
          createdAt: DateTime(2026, 9, 1),
          reminderAt: reminderAt,
          timetableId: 't1',
          courseId: 'c1',
        ),
      ],
    );

    await state.deleteTimetable('t1');

    expect(state.activeTimetable?.id, 't2');
    expect(state.tasks, hasLength(1));
    expect(state.tasks.single.timetableId, isNull);
    expect(state.tasks.single.courseId, isNull);
    expect(state.tasks.single.reminderAt, reminderAt);
  });

  test('稍后提醒把未完成事项改到十分钟后', () async {
    final now = DateTime(2026, 9, 7, 8);
    final state = await stateWith(
      timetables: [timetable('t1', '当前课表')],
      activeTimetableId: 't1',
      tasks: [
        TaskItem(
          id: 'task1',
          title: '高数作业',
          kind: TaskKind.homework,
          createdAt: DateTime(2026, 9, 1),
          reminderAt: DateTime(2026, 9, 7, 7),
        ),
      ],
    );

    await state.snoozeTask('task1', now: now);

    expect(state.tasks.single.reminderAt, DateTime(2026, 9, 7, 8, 10));
    expect(
      (await store.load()).tasks.single.reminderAt,
      DateTime(2026, 9, 7, 8, 10),
    );
  });
}
