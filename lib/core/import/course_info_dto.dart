import '../models/course.dart';
import '../models/time_slot.dart';
import '../models/timetable.dart';
import '../stable_hash.dart';
import '../weeks_parser.dart';

/// 导入过程中的中间结构，字段与小爱课程表社区解析器的 `courseInfos` 一一对应。
///
/// 所有导入格式（CSV / CSES / ICS / JSON）都先转成这个结构，再统一装配成
/// [Timetable]。将来接教务系统直连时，社区 `.js` 解析器的输出可以原样喂进来，
/// 不需要改动模型层。
class CourseInfoDto {
  const CourseInfoDto({
    required this.name,
    required this.day,
    required this.weeks,
    required this.sections,
    this.teacher,
    this.position,
  });

  final String name;

  /// 1 = 周一 … 7 = 周日
  final int day;
  final List<int> weeks;

  /// 展开后的节次列表，例如第 1-2 节是 [1, 2]。
  final List<int> sections;

  final String? teacher;

  /// 教室。字段名沿用小爱课程表的 `position`。
  final String? position;

  factory CourseInfoDto.fromAiSchedule(Map<String, dynamic> json) {
    final rawSections = (json['sections'] as List?) ?? const [];
    final sections = <int>[];
    for (final s in rawSections) {
      if (s is int) {
        sections.add(s);
      } else if (s is Map && s['section'] is int) {
        sections.add(s['section'] as int);
      } else if (s is num) {
        sections.add(s.toInt());
      }
    }
    return CourseInfoDto(
      name: (json['name'] as String? ?? '').trim(),
      day: (json['day'] as num?)?.toInt() ?? 0,
      weeks: ((json['weeks'] as List?) ?? const [])
          .map((e) => (e as num).toInt())
          .toList(),
      sections: sections..sort(),
      teacher: _clean(json['teacher']),
      position: _clean(json['position']),
    );
  }

  Map<String, dynamic> toAiSchedule() => {
        'name': name,
        'teacher': teacher ?? '',
        'position': position ?? '',
        'day': day,
        'weeks': weeks,
        'sections': sections.map((s) => {'section': s}).toList(),
      };
}

String? _clean(Object? value) {
  if (value is! String) return null;
  final t = value.trim();
  return t.isEmpty ? null : t;
}

/// 把「星期 / 课程 / 教师 / 教室 / 周次」完全相同的记录合并成一条，节次取并集。
///
/// CSES 和 ICS 都是按「一个时间段一条记录」给数据的，合并之后连续节次才能
/// 在 [buildTimetable] 里被压成一个 1-2 节这样的时段，而不是拆成两条。
List<CourseInfoDto> mergeCourseInfos(Iterable<CourseInfoDto> input) {
  final grouped = <String, ({CourseInfoDto sample, Set<int> sections})>{};
  for (final dto in input) {
    final key = [
      dto.day,
      dto.name,
      dto.teacher ?? '',
      dto.position ?? '',
      (dto.weeks.toList()..sort()).join(','),
    ].join('|');
    final entry =
        grouped.putIfAbsent(key, () => (sample: dto, sections: <int>{}));
    entry.sections.addAll(dto.sections);
  }
  return [
    for (final g in grouped.values)
      CourseInfoDto(
        name: g.sample.name,
        day: g.sample.day,
        weeks: g.sample.weeks,
        sections: g.sections.toList()..sort(),
        teacher: g.sample.teacher,
        position: g.sample.position,
      ),
  ];
}

/// 一次导入的结果：课程数据 + 可选的课表元信息 + 需要提示用户的警告。
class ImportedSchedule {
  ImportedSchedule({
    required this.courses,
    this.warnings = const [],
    this.name,
    this.termStart,
    this.totalWeeks,
    this.timeSlots,
  });

  final List<CourseInfoDto> courses;
  final List<String> warnings;
  final String? name;
  final DateTime? termStart;
  final int? totalWeeks;
  final List<TimeSlot>? timeSlots;

  int get sessionCount => courses.length;
  Set<String> get courseNames => courses.map((c) => c.name).toSet();
}

/// 把导入结果装配成一张完整课表。
///
/// 同名同教师的课合并成一个 [Course]；节次不连续的时段（例如 1,2,5,6）
/// 会拆成多个 [CourseSession]。非法数据不会中断导入，而是写进 [warnings]。
Timetable buildTimetable({
  required String id,
  required String name,
  required DateTime termStart,
  required ImportedSchedule imported,
  required List<String> warnings,
  int? totalWeeks,
  List<TimeSlot>? timeSlots,
}) {
  final weeks = totalWeeks ?? imported.totalWeeks ?? 20;
  final slots = timeSlots ?? imported.timeSlots ?? kDefaultTimeSlots;
  final courses = <String, Course>{};
  final sessions = <CourseSession>[];

  for (final dto in imported.courses) {
    if (dto.name.isEmpty) {
      warnings.add('跳过一条没有课程名的记录');
      continue;
    }
    if (dto.day < 1 || dto.day > 7) {
      warnings.add('${dto.name}：星期值 ${dto.day} 非法，已跳过');
      continue;
    }
    if (dto.sections.isEmpty) {
      warnings.add('${dto.name}：没有节次信息，已跳过');
      continue;
    }
    final validWeeks = dto.weeks.where((w) => w >= 1 && w <= weeks).toSet();
    if (validWeeks.isEmpty) {
      warnings.add('${dto.name}：周次为空或全部超出 1-$weeks，已跳过');
      continue;
    }

    final key = '${dto.name}|${dto.teacher ?? ''}';
    final course = courses.putIfAbsent(
      key,
      () => Course(
        id: 'c${stableHash(key)}',
        name: dto.name,
        teacher: dto.teacher,
        colorSeed: stableHash(dto.name),
      ),
    );

    for (final range in compressRanges(dto.sections)) {
      final sid = 's${stableHash('${course.id}|${dto.day}|${range.$1}-${range.$2}|'
          '${(validWeeks.toList()..sort()).join(",")}|${dto.position ?? ""}')}';
      sessions.add(CourseSession(
        id: sid,
        courseId: course.id,
        day: dto.day,
        startSection: range.$1,
        endSection: range.$2,
        weeks: validWeeks,
        room: dto.position,
      ));
    }
  }

  final maxSection = slots.map((s) => s.index).fold<int>(0, (a, b) => a > b ? a : b);
  for (final s in sessions) {
    if (s.endSection > maxSection) {
      final courseName = courses.values.firstWhere((c) => c.id == s.courseId).name;
      warnings.add('$courseName：第${s.endSection}节超出作息表的 $maxSection 节，'
          '请到设置里补充节次时间');
    }
  }

  return Timetable(
    id: id,
    name: name,
    termStart: termStart,
    totalWeeks: weeks,
    timeSlots: slots,
    courses: courses.values.toList(),
    sessions: sessions,
  );
}
