import 'agenda.dart';
import 'exam_countdown.dart';
import 'models/exam.dart';
import 'models/task_item.dart';
import 'models/timetable.dart';
import 'task_query.dart';

class TodayOverview {
  const TodayOverview({
    required this.sessions,
    required this.dueTasks,
    required this.upcomingExams,
  });

  final List<ResolvedSession> sessions;
  final List<TaskItem> dueTasks;
  final List<ExamCountdown> upcomingExams;
}

TodayOverview buildTodayOverview({
  required Timetable? timetable,
  required Iterable<TaskItem> tasks,
  required List<Exam> exams,
  required DateTime now,
  int examLimit = 3,
}) {
  final tomorrow = DateTime(now.year, now.month, now.day + 1);
  final dueTasks = sortedTasks(
    tasks.where(
      (task) =>
          !task.isCompleted &&
          task.dueAt != null &&
          task.dueAt!.isBefore(tomorrow),
    ),
    now,
  );
  return TodayOverview(
    sessions: timetable == null
        ? const []
        : sessionsOnDate(timetable, now, includeChangedSources: true),
    dueTasks: dueTasks,
    upcomingExams: upcomingExams(exams, now, limit: examLimit),
  );
}
