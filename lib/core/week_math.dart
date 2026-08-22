/// 学期周次相关的纯计算。
///
/// 约定：`termStart` 是**第一周周一**的日期（只有日期部分有意义）。
/// 所有跨天计算都先归一化到 UTC 午夜再相减，避免本地时区/夏令时导致
/// `Duration.inDays` 少算一天。
library;

/// 去掉时间部分。
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// 归一化成 UTC 午夜，仅用于「相差多少天」这类计算。
DateTime _utcMidnight(DateTime d) => DateTime.utc(d.year, d.month, d.day);

/// b - a，单位为天。
int daysBetween(DateTime a, DateTime b) =>
    _utcMidnight(b).difference(_utcMidnight(a)).inDays;

/// 给定日期所在周的周一。
DateTime mondayOf(DateTime d) =>
    dateOnly(d).subtract(Duration(days: d.weekday - 1));

/// `now` 处于第几周；学期还没开始或已经结束时返回 null。
int? currentWeek(DateTime termStart, DateTime now, int totalWeeks) {
  final diff = daysBetween(termStart, now);
  if (diff < 0) return null;
  final week = diff ~/ 7 + 1;
  if (week > totalWeeks) return null;
  return week;
}

/// 用于界面默认展示：学期前显示第 1 周，学期后显示最后一周。
int clampedWeek(DateTime termStart, DateTime now, int totalWeeks) {
  final diff = daysBetween(termStart, now);
  if (diff < 0) return 1;
  final week = diff ~/ 7 + 1;
  return week > totalWeeks ? totalWeeks : week;
}

/// 第 `week` 周、星期 `day`（1=周一）对应的日期。
DateTime dateOfWeekDay(DateTime termStart, int week, int day) {
  assert(week >= 1 && day >= 1 && day <= 7);
  return dateOnly(termStart).add(Duration(days: (week - 1) * 7 + (day - 1)));
}

/// 日期对应的 (周次, 星期)；不在学期范围内返回 null。
({int week, int day})? weekDayOfDate(
  DateTime termStart,
  DateTime date,
  int totalWeeks,
) {
  final diff = daysBetween(termStart, date);
  if (diff < 0) return null;
  final week = diff ~/ 7 + 1;
  if (week > totalWeeks) return null;
  return (week: week, day: diff % 7 + 1);
}

Set<int> allWeeks(int totalWeeks) =>
    {for (var w = 1; w <= totalWeeks; w++) w};

Set<int> oddWeeks(int totalWeeks) =>
    {for (var w = 1; w <= totalWeeks; w += 2) w};

Set<int> evenWeeks(int totalWeeks) =>
    {for (var w = 2; w <= totalWeeks; w += 2) w};

const List<String> kWeekDayNames = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

String weekDayName(int day) => kWeekDayNames[day - 1];
