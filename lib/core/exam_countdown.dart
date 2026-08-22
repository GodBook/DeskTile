import 'models/exam.dart';

/// 一场考试的倒计时。
class ExamCountdown {
  const ExamCountdown({required this.exam, required this.remaining});

  final Exam exam;

  /// 距离开考还有多久；已开考为负。
  final Duration remaining;

  bool get started => remaining.isNegative;

  String get remainingText => formatRemaining(remaining);
}

/// 考试的结束时刻；没填结束时间时按 2 小时估算，用于判断是否已经考完。
DateTime examEndAt(Exam exam) =>
    exam.endAt ?? exam.startAt.add(const Duration(hours: 2));

/// 还没考完的考试，按开考时间升序。[limit] > 0 时只取前若干场。
List<ExamCountdown> upcomingExams(
  List<Exam> exams,
  DateTime now, {
  int limit = 0,
}) {
  final list = exams.where((e) => examEndAt(e).isAfter(now)).toList()
    ..sort((a, b) => a.startAt.compareTo(b.startAt));
  final result = list
      .map((e) => ExamCountdown(exam: e, remaining: e.startAt.difference(now)))
      .toList();
  if (limit > 0 && result.length > limit) return result.sublist(0, limit);
  return result;
}

/// 已经考完的考试，按开考时间倒序（界面上折叠展示）。
List<Exam> pastExams(List<Exam> exams, DateTime now) =>
    exams.where((e) => !examEndAt(e).isAfter(now)).toList()
      ..sort((a, b) => b.startAt.compareTo(a.startAt));

ExamCountdown? nearestExam(List<Exam> exams, DateTime now) {
  final list = upcomingExams(exams, now, limit: 1);
  return list.isEmpty ? null : list.first;
}

/// "12 天 3 小时" / "3 小时 20 分" / "18 分钟" / "已开始"
String formatRemaining(Duration d) {
  if (d.isNegative) return '已开始';
  if (d.inDays >= 1) {
    final hours = d.inHours % 24;
    return hours == 0 ? '${d.inDays} 天' : '${d.inDays} 天 $hours 小时';
  }
  if (d.inHours >= 1) {
    final minutes = d.inMinutes % 60;
    return minutes == 0 ? '${d.inHours} 小时' : '${d.inHours} 小时 $minutes 分';
  }
  final minutes = d.inMinutes;
  return minutes <= 0 ? '不到 1 分钟' : '$minutes 分钟';
}
