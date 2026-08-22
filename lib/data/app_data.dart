import '../core/models/exam.dart';
import '../core/models/settings.dart';
import '../core/models/timetable.dart';
import '../core/week_math.dart';

/// 全部应用数据。整个程序只有这一份状态，一个 JSON 文件装完。
///
/// 课表数据量很小（几百条），用 SQLite 反而是负担；单文件还带来两个好处：
/// 备份/跨端搬运就是拷一个文件，挂件进程可以直接监听文件变化。
///
/// 这个文件刻意不依赖 Flutter 和 path_provider，纯 Dart 脚本也能读写它。
class AppData {
  const AppData({
    required this.timetables,
    required this.exams,
    required this.settings,
    this.activeTimetableId,
  });

  final List<Timetable> timetables;
  final List<Exam> exams;
  final AppSettings settings;
  final String? activeTimetableId;

  static const schemaVersion = 1;

  Timetable? get activeTimetable {
    if (timetables.isEmpty) return null;
    for (final t in timetables) {
      if (t.id == activeTimetableId) return t;
    }
    return timetables.first;
  }

  AppData copyWith({
    List<Timetable>? timetables,
    List<Exam>? exams,
    AppSettings? settings,
    String? activeTimetableId,
  }) =>
      AppData(
        timetables: timetables ?? this.timetables,
        exams: exams ?? this.exams,
        settings: settings ?? this.settings,
        activeTimetableId: activeTimetableId ?? this.activeTimetableId,
      );

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'activeTimetableId': activeTimetableId,
        'timetables': timetables.map((t) => t.toJson()).toList(),
        'exams': exams.map((e) => e.toJson()).toList(),
        'settings': settings.toJson(),
      };

  factory AppData.fromJson(Map<String, dynamic> json) => AppData(
        activeTimetableId: json['activeTimetableId'] as String?,
        timetables: (json['timetables'] as List? ?? [])
            .map((e) => Timetable.fromJson(e as Map<String, dynamic>))
            .toList(),
        exams: (json['exams'] as List? ?? [])
            .map((e) => Exam.fromJson(e as Map<String, dynamic>))
            .toList(),
        settings: json['settings'] is Map<String, dynamic>
            ? AppSettings.fromJson(json['settings'] as Map<String, dynamic>)
            : const AppSettings(),
      );

  /// 首次运行：给一张空课表，学期从本周周一算起，界面立刻有东西可看。
  factory AppData.initial({DateTime? now}) {
    final start = mondayOf(now ?? DateTime.now());
    final t = Timetable(id: 't1', name: '我的课表', termStart: start);
    return AppData(
      timetables: [t],
      exams: const [],
      settings: const AppSettings(),
      activeTimetableId: t.id,
    );
  }
}
