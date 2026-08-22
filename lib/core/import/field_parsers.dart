import '../weeks_parser.dart';

const _dayNames = {
  '一': 1, '二': 2, '三': 3, '四': 4, '五': 5, '六': 6, '日': 7, '天': 7,
  'mon': 1, 'tue': 2, 'wed': 3, 'thu': 4, 'fri': 5, 'sat': 6, 'sun': 7,
  'monday': 1, 'tuesday': 2, 'wednesday': 3, 'thursday': 4,
  'friday': 5, 'saturday': 6, 'sunday': 7,
};

/// 解析星期：接受 "1".."7"、"一".."日/天"、"周三"、"星期三"、"Wed" 等写法。
/// 解析不出来返回 null。
int? parseWeekDay(String input) {
  final text = input.trim();
  if (text.isEmpty) return null;

  final digits = RegExp(r'\d+').firstMatch(text);
  if (digits != null) {
    final n = int.parse(digits.group(0)!);
    if (n >= 1 && n <= 7) return n;
    return null;
  }

  final lower = text.toLowerCase();
  for (final entry in _dayNames.entries) {
    if (lower == entry.key) return entry.value;
  }
  // "周三" / "星期三" 这类：去掉前缀后取剩下的中文数字。
  final stripped = text
      .replaceAll('星期', '')
      .replaceAll('周', '')
      .replaceAll('礼拜', '')
      .trim();
  if (stripped.length == 1) return _dayNames[stripped];
  final lowerStripped = stripped.toLowerCase();
  return _dayNames[lowerStripped];
}

/// 解析节次串 "1-2" / "1,2" / "3"，返回升序节次列表。
List<int> parseSections(String input) =>
    (parseIntRanges(input).toList()..sort());
