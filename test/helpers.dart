import 'package:desktile/core/models/course.dart';
import 'package:desktile/core/models/time_slot.dart';
import 'package:desktile/core/models/timetable.dart';
import 'package:desktile/core/week_math.dart';

/// 2026-09-07 是周一，测试里统一当作学期第一周的周一。
final testTermStart = DateTime(2026, 9, 7);

/// 构造一张小课表：
///   周一 1-2 节 高等数学 @ 教三-305（每周）
///   周一 3-4 节 大学英语 @ 外语楼-201（每周）
///   周二 1-2 节 线性代数 @ 教三-208（单周）
///   周三 6-7 节 下午的课 @ 教一-401（每周，用来测「第一节课太晚不提醒」）
///
/// [termStart] 默认是固定的 2026-09-07，界面测试可以传 `mondayOf(DateTime.now())`
/// 让「本周」稳定落在第 1 周。
Timetable buildTestTimetable({int totalWeeks = 16, DateTime? termStart}) {
  const courses = [
    Course(id: 'c1', name: '高等数学', teacher: '张伟'),
    Course(id: 'c2', name: '大学英语', teacher: '李娜'),
    Course(id: 'c3', name: '线性代数', teacher: '王强'),
    Course(id: 'c4', name: '下午的课'),
  ];
  final sessions = [
    CourseSession(
      id: 's1',
      courseId: 'c1',
      day: 1,
      startSection: 1,
      endSection: 2,
      weeks: allWeeks(totalWeeks),
      room: '教三-305',
    ),
    CourseSession(
      id: 's2',
      courseId: 'c2',
      day: 1,
      startSection: 3,
      endSection: 4,
      weeks: allWeeks(totalWeeks),
      room: '外语楼-201',
    ),
    CourseSession(
      id: 's3',
      courseId: 'c3',
      day: 2,
      startSection: 1,
      endSection: 2,
      weeks: oddWeeks(totalWeeks),
      room: '教三-208',
    ),
    CourseSession(
      id: 's4',
      courseId: 'c4',
      day: 3,
      startSection: 6,
      endSection: 7,
      weeks: allWeeks(totalWeeks),
      room: '教一-401',
    ),
  ];
  return Timetable(
    id: 't1',
    name: '测试课表',
    termStart: termStart ?? testTermStart,
    totalWeeks: totalWeeks,
    timeSlots: kDefaultTimeSlots,
    courses: courses,
    sessions: sessions,
  );
}
