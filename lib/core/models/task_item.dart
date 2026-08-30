enum TaskKind { homework, todo }

enum TaskPriority { normal, important }

class TaskItem {
  const TaskItem({
    required this.id,
    required this.title,
    required this.kind,
    required this.createdAt,
    this.dueAt,
    this.reminderAt,
    this.timetableId,
    this.courseId,
    this.note,
    this.priority = TaskPriority.normal,
    this.completedAt,
  });

  final String id;
  final String title;
  final TaskKind kind;
  final DateTime createdAt;
  final DateTime? dueAt;
  final DateTime? reminderAt;
  final String? timetableId;
  final String? courseId;
  final String? note;
  final TaskPriority priority;
  final DateTime? completedAt;

  bool get isCompleted => completedAt != null;

  TaskItem withCompletion(bool completed, {DateTime? at}) => TaskItem(
    id: id,
    title: title,
    kind: kind,
    createdAt: createdAt,
    dueAt: dueAt,
    reminderAt: reminderAt,
    timetableId: timetableId,
    courseId: courseId,
    note: note,
    priority: priority,
    completedAt: completed ? (at ?? DateTime.now()) : null,
  );

  TaskItem withTimetableId(String? value) => TaskItem(
    id: id,
    title: title,
    kind: kind,
    createdAt: createdAt,
    dueAt: dueAt,
    reminderAt: reminderAt,
    timetableId: value,
    courseId: courseId,
    note: note,
    priority: priority,
    completedAt: completedAt,
  );

  TaskItem withReminderAt(DateTime? value) => TaskItem(
    id: id,
    title: title,
    kind: kind,
    createdAt: createdAt,
    dueAt: dueAt,
    reminderAt: value,
    timetableId: timetableId,
    courseId: courseId,
    note: note,
    priority: priority,
    completedAt: completedAt,
  );

  TaskItem withoutCourseLink() => TaskItem(
    id: id,
    title: title,
    kind: kind,
    createdAt: createdAt,
    dueAt: dueAt,
    reminderAt: reminderAt,
    note: note,
    priority: priority,
    completedAt: completedAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'kind': kind == TaskKind.homework ? 'homework' : 'todo',
    'createdAt': createdAt.toIso8601String(),
    if (dueAt != null) 'dueAt': dueAt!.toIso8601String(),
    if (reminderAt != null) 'reminderAt': reminderAt!.toIso8601String(),
    if (timetableId != null) 'timetableId': timetableId,
    if (courseId != null) 'courseId': courseId,
    if (note != null) 'note': note,
    'priority': priority == TaskPriority.important ? 'important' : 'normal',
    if (completedAt != null) 'completedAt': completedAt!.toIso8601String(),
  };

  factory TaskItem.fromJson(Map<String, dynamic> json) => TaskItem(
    id: json['id'] as String,
    title: json['title'] as String,
    kind: json['kind'] == 'homework' ? TaskKind.homework : TaskKind.todo,
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
    dueAt: _parseDateTime(json['dueAt']),
    reminderAt: _parseDateTime(json['reminderAt']),
    timetableId: json['timetableId'] as String?,
    courseId: json['courseId'] as String?,
    note: json['note'] as String?,
    priority: json['priority'] == 'important'
        ? TaskPriority.important
        : TaskPriority.normal,
    completedAt: _parseDateTime(json['completedAt']),
  );
}

DateTime? _parseDateTime(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;
