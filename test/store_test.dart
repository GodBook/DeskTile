import 'dart:convert';
import 'dart:io';

import 'package:desktile/core/models/exam.dart';
import 'package:desktile/core/models/settings.dart';
import 'package:desktile/core/week_math.dart';
import 'package:desktile/data/store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  late Directory tmp;
  late DataStore store;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('desktile_test');
    store = DataStore(overrideDirectory: tmp);
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('首次运行给出一张空课表，学期从本周周一算起', () async {
    final data = await store.load();
    expect(data.timetables.length, 1);
    expect(data.activeTimetable!.name, '我的课表');
    expect(data.activeTimetable!.termStart, mondayOf(DateTime.now()));
    expect(data.exams, isEmpty);
  });

  test('存取往返：课表、考试、设置都不丢', () async {
    final original = AppData(
      timetables: [buildTestTimetable()],
      exams: [
        Exam(
          id: 'e1',
          name: '高等数学',
          startAt: DateTime(2027, 1, 5, 9),
          endAt: DateTime(2027, 1, 5, 11),
          room: '教三-305',
          seat: '12',
        ),
      ],
      settings: const AppSettings(
        reminderMode: ReminderMode.everyClass,
        leadMinutes: 15,
        widgetOpacity: 0.8,
        widgetForm: WidgetForm.mini,
        autoStart: true,
        theme: ThemePref.dark,
      ),
      activeTimetableId: 't1',
    );
    await store.save(original);

    final loaded = await store.load();
    expect(loaded.activeTimetableId, 't1');
    expect(loaded.timetables.single.courses.length, 4);
    expect(loaded.timetables.single.sessions.length, 4);
    expect(loaded.timetables.single.termStart, testTermStart);

    final linear =
        loaded.timetables.single.sessions.firstWhere((s) => s.id == 's3');
    expect(linear.weeks, oddWeeks(16));
    expect(linear.room, '教三-208');

    expect(loaded.exams.single.seat, '12');
    expect(loaded.settings.reminderMode, ReminderMode.everyClass);
    expect(loaded.settings.leadMinutes, 15);
    expect(loaded.settings.widgetForm, WidgetForm.mini);
    expect(loaded.settings.autoStart, isTrue);
    expect(loaded.settings.theme, ThemePref.dark);
  });

  test('保存后不留下临时文件', () async {
    await store.save(AppData.initial());
    final names = tmp.listSync().map((e) => e.path.split(Platform.pathSeparator).last);
    expect(names, contains('desktile_data.json'));
    expect(names.where((n) => n.endsWith('.tmp')), isEmpty);
  });

  test('文件损坏时备份并回到初始数据，而不是崩掉', () async {
    final file = await store.dataFile();
    await file.parent.create(recursive: true);
    await file.writeAsString('{ 这不是 JSON');

    final data = await store.load();
    expect(data.timetables.length, 1);
    expect(File('${file.path}.broken').existsSync(), isTrue);
  });

  test('顶层不是对象时也能兜住', () async {
    final file = await store.dataFile();
    await file.parent.create(recursive: true);
    await file.writeAsString('[1,2,3]');
    final data = await store.load();
    expect(data.timetables.length, 1);
  });

  test('写出的 JSON 带 schemaVersion，便于以后迁移', () async {
    await store.save(AppData.initial());
    final file = await store.dataFile();
    final json = jsonDecode(utf8.decode(file.readAsBytesSync()));
    expect(json['schemaVersion'], AppData.schemaVersion);
  });

  test('newId 不重复', () {
    final ids = {for (var i = 0; i < 500; i++) newId('c')};
    expect(ids.length, 500);
  });
}
