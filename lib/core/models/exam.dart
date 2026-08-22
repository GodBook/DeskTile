/// 一场考试。倒计时只依赖 [startAt]。
class Exam {
  const Exam({
    required this.id,
    required this.name,
    required this.startAt,
    this.endAt,
    this.room,
    this.seat,
    this.note,
  });

  final String id;
  final String name;
  final DateTime startAt;
  final DateTime? endAt;
  final String? room;
  final String? seat;
  final String? note;

  Exam copyWith({
    String? name,
    DateTime? startAt,
    DateTime? endAt,
    String? room,
    String? seat,
    String? note,
  }) =>
      Exam(
        id: id,
        name: name ?? this.name,
        startAt: startAt ?? this.startAt,
        endAt: endAt ?? this.endAt,
        room: room ?? this.room,
        seat: seat ?? this.seat,
        note: note ?? this.note,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'startAt': startAt.toIso8601String(),
        if (endAt != null) 'endAt': endAt!.toIso8601String(),
        if (room != null) 'room': room,
        if (seat != null) 'seat': seat,
        if (note != null) 'note': note,
      };

  factory Exam.fromJson(Map<String, dynamic> json) => Exam(
        id: json['id'] as String,
        name: json['name'] as String,
        startAt: DateTime.parse(json['startAt'] as String),
        endAt: json['endAt'] == null
            ? null
            : DateTime.parse(json['endAt'] as String),
        room: json['room'] as String?,
        seat: json['seat'] as String?,
        note: json['note'] as String?,
      );
}
