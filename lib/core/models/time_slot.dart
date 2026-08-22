/// 一节课的时间定义（第几节 + 起止时刻）。
///
/// 时刻统一用「从 00:00 起的分钟数」表示，这样 core 层不依赖 Flutter 的
/// TimeOfDay，可以直接跑单元测试。
class TimeSlot {
  const TimeSlot({
    required this.index,
    required this.startMinutes,
    required this.endMinutes,
  });

  /// 第几节，1 起。
  final int index;
  final int startMinutes;
  final int endMinutes;

  String get startText => formatMinutes(startMinutes);
  String get endText => formatMinutes(endMinutes);

  TimeSlot copyWith({int? index, int? startMinutes, int? endMinutes}) =>
      TimeSlot(
        index: index ?? this.index,
        startMinutes: startMinutes ?? this.startMinutes,
        endMinutes: endMinutes ?? this.endMinutes,
      );

  Map<String, dynamic> toJson() => {
        'index': index,
        'start': startText,
        'end': endText,
      };

  factory TimeSlot.fromJson(Map<String, dynamic> json) => TimeSlot(
        index: json['index'] as int,
        startMinutes: parseMinutes(json['start'] as String),
        endMinutes: parseMinutes(json['end'] as String),
      );

  @override
  String toString() => '第$index节 $startText-$endText';
}

/// "08:05" -> 485。也接受 "8:5" 与 "08:05:00"。
int parseMinutes(String text) {
  final parts = text.trim().split(':');
  if (parts.length < 2) {
    throw FormatException('无法解析时刻: $text');
  }
  final h = int.parse(parts[0]);
  final m = int.parse(parts[1]);
  if (h < 0 || h > 23 || m < 0 || m > 59) {
    throw FormatException('时刻超出范围: $text');
  }
  return h * 60 + m;
}

/// 485 -> "08:05"
String formatMinutes(int minutes) {
  final h = (minutes ~/ 60).toString().padLeft(2, '0');
  final m = (minutes % 60).toString().padLeft(2, '0');
  return '$h:$m';
}

/// 大学常见的 12 节作息，新建课表时的默认值。
const List<TimeSlot> kDefaultTimeSlots = [
  TimeSlot(index: 1, startMinutes: 8 * 60, endMinutes: 8 * 60 + 45),
  TimeSlot(index: 2, startMinutes: 8 * 60 + 50, endMinutes: 9 * 60 + 35),
  TimeSlot(index: 3, startMinutes: 9 * 60 + 55, endMinutes: 10 * 60 + 40),
  TimeSlot(index: 4, startMinutes: 10 * 60 + 45, endMinutes: 11 * 60 + 30),
  TimeSlot(index: 5, startMinutes: 11 * 60 + 35, endMinutes: 12 * 60 + 20),
  TimeSlot(index: 6, startMinutes: 14 * 60, endMinutes: 14 * 60 + 45),
  TimeSlot(index: 7, startMinutes: 14 * 60 + 50, endMinutes: 15 * 60 + 35),
  TimeSlot(index: 8, startMinutes: 15 * 60 + 55, endMinutes: 16 * 60 + 40),
  TimeSlot(index: 9, startMinutes: 16 * 60 + 45, endMinutes: 17 * 60 + 30),
  TimeSlot(index: 10, startMinutes: 18 * 60 + 30, endMinutes: 19 * 60 + 15),
  TimeSlot(index: 11, startMinutes: 19 * 60 + 20, endMinutes: 20 * 60 + 5),
  TimeSlot(index: 12, startMinutes: 20 * 60 + 10, endMinutes: 20 * 60 + 55),
];
