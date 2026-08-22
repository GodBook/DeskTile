/// 一门课程（课程本身的信息，与具体上课时段分离）。
class Course {
  const Course({
    required this.id,
    required this.name,
    this.teacher,
    this.note,
    this.colorSeed = 0,
  });

  final String id;
  final String name;
  final String? teacher;
  final String? note;

  /// 用于生成课程块配色，导入时按课程名 hash 生成，用户可改。
  final int colorSeed;

  Course copyWith({
    String? name,
    String? teacher,
    String? note,
    int? colorSeed,
  }) =>
      Course(
        id: id,
        name: name ?? this.name,
        teacher: teacher ?? this.teacher,
        note: note ?? this.note,
        colorSeed: colorSeed ?? this.colorSeed,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (teacher != null) 'teacher': teacher,
        if (note != null) 'note': note,
        'colorSeed': colorSeed,
      };

  factory Course.fromJson(Map<String, dynamic> json) => Course(
        id: json['id'] as String,
        name: json['name'] as String,
        teacher: json['teacher'] as String?,
        note: json['note'] as String?,
        colorSeed: (json['colorSeed'] as int?) ?? 0,
      );
}

/// 一个上课时段：星期几、第几节到第几节、哪些周、在哪个教室。
///
/// 单双周不是一个独立开关，而是 [weeks] 集合的一种形态 —— 只填奇数周就是单周课。
/// 这样自定义周次（例如 1-8 周、10 周、12-16 周）和单双周走同一条路径。
class CourseSession {
  const CourseSession({
    required this.id,
    required this.courseId,
    required this.day,
    required this.startSection,
    required this.endSection,
    required this.weeks,
    this.room,
  });

  final String id;
  final String courseId;

  /// 1 = 周一 … 7 = 周日
  final int day;

  /// 起止节次，闭区间。
  final int startSection;
  final int endSection;

  final Set<int> weeks;
  final String? room;

  int get sectionCount => endSection - startSection + 1;

  bool activeInWeek(int week) => weeks.contains(week);

  /// 与另一个时段在同一天是否有节次重叠（用于编辑时的冲突提示）。
  bool overlaps(CourseSession other) {
    if (day != other.day) return false;
    if (startSection > other.endSection || endSection < other.startSection) {
      return false;
    }
    return weeks.intersection(other.weeks).isNotEmpty;
  }

  CourseSession copyWith({
    String? courseId,
    int? day,
    int? startSection,
    int? endSection,
    Set<int>? weeks,
    String? room,
  }) =>
      CourseSession(
        id: id,
        courseId: courseId ?? this.courseId,
        day: day ?? this.day,
        startSection: startSection ?? this.startSection,
        endSection: endSection ?? this.endSection,
        weeks: weeks ?? this.weeks,
        room: room ?? this.room,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'courseId': courseId,
        'day': day,
        'startSection': startSection,
        'endSection': endSection,
        'weeks': (weeks.toList()..sort()),
        if (room != null) 'room': room,
      };

  factory CourseSession.fromJson(Map<String, dynamic> json) => CourseSession(
        id: json['id'] as String,
        courseId: json['courseId'] as String,
        day: json['day'] as int,
        startSection: json['startSection'] as int,
        endSection: json['endSection'] as int,
        weeks: (json['weeks'] as List).map((e) => e as int).toSet(),
        room: json['room'] as String?,
      );
}
