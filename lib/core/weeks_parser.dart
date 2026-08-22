/// 周次串的解析与格式化。
///
/// 这是 CSV 导入、CSES 导入以及（未来）教务系统解析器共用的一段逻辑，
/// 语义对齐小爱课程表社区解析器的 `weekStr2IntList` / `getWeeks`：
/// 先展开区间，再按「单/双」过滤奇偶周。
///
/// 支持的写法：
///   1-16 / 1-16周 / 第1-16周 / 1，3，5-9 / 1-16单 / 双周 / 1-8,10,12-16
library;

import 'week_math.dart';

const _fullWidthDigits = '０１２３４５６７８９';

String _normalize(String input) {
  final sb = StringBuffer();
  for (final ch in input.trim().split('')) {
    final fw = _fullWidthDigits.indexOf(ch);
    if (fw >= 0) {
      sb.write(fw);
      continue;
    }
    switch (ch) {
      case '，':
      case '、':
      case '；':
      case ';':
      case '/':
        sb.write(',');
      case '－':
      case '–':
      case '—':
      case '~':
      case '～':
      case '至':
      case '到':
        sb.write('-');
      default:
        sb.write(ch);
    }
  }
  return sb.toString();
}

/// 解析 "1-2" / "1,3,5-9" / "3" 这类整数区间串。
/// 不做单双周过滤、不裁剪范围，节次解析也用它。
Set<int> parseIntRanges(String input) {
  final cleaned = _normalize(input).replaceAll(RegExp(r'[^0-9,\-]'), '');
  final result = <int>{};
  for (final token in cleaned.split(',')) {
    if (token.isEmpty) continue;
    final range = RegExp(r'^(\d+)-(\d+)$').firstMatch(token);
    if (range != null) {
      var a = int.parse(range.group(1)!);
      var b = int.parse(range.group(2)!);
      if (a > b) (a, b) = (b, a);
      for (var v = a; v <= b; v++) {
        result.add(v);
      }
      continue;
    }
    final single = RegExp(r'^(\d+)$').firstMatch(token);
    if (single != null) result.add(int.parse(single.group(1)!));
  }
  return result;
}

/// 解析周次串。`totalWeeks` 用于「单/双」这类没写具体周次的情况以及越界裁剪。
///
/// 完全解析不出周次时抛 [FormatException]。
Set<int> parseWeeks(String input, {required int totalWeeks}) {
  final text = _normalize(input);
  final hasOdd = text.contains('单') || text.contains('奇');
  final hasEven = text.contains('双') || text.contains('偶');
  // 「单双周」两个字都出现时视为不过滤。
  final oddOnly = hasOdd && !hasEven;
  final evenOnly = hasEven && !hasOdd;

  final weeks = parseIntRanges(text);

  if (weeks.isEmpty) {
    if (oddOnly) return oddWeeks(totalWeeks);
    if (evenOnly) return evenWeeks(totalWeeks);
    // 「单双周」两个字都写了、又没给具体周次，按每周处理。
    if (hasOdd && hasEven) return allWeeks(totalWeeks);
    throw FormatException('无法解析周次: $input');
  }

  weeks.removeWhere((w) => w < 1 || w > totalWeeks);
  if (oddOnly) weeks.removeWhere((w) => w.isEven);
  if (evenOnly) weeks.removeWhere((w) => w.isOdd);
  return weeks;
}

/// 解析失败时返回 null，而不是抛异常（导入时用来收集警告）。
Set<int>? tryParseWeeks(String input, {required int totalWeeks}) {
  try {
    final result = parseWeeks(input, totalWeeks: totalWeeks);
    return result.isEmpty ? null : result;
  } on FormatException {
    return null;
  }
}

/// 把连续的数字压成区间：{1,2,3,5,7,8} -> [(1,3),(5,5),(7,8)]
List<(int, int)> compressRanges(Iterable<int> values) {
  final sorted = values.toSet().toList()..sort();
  final result = <(int, int)>[];
  for (final v in sorted) {
    if (result.isNotEmpty && result.last.$2 == v - 1) {
      result[result.length - 1] = (result.last.$1, v);
    } else {
      result.add((v, v));
    }
  }
  return result;
}

/// 面向界面的周次描述：每周 / 单周 / 双周 / 1-8,10,12-16周
String formatWeeks(Set<int> weeks, {required int totalWeeks}) {
  if (weeks.isEmpty) return '未设置';
  if (weeks.length == totalWeeks) return '每周';
  if (setEquals(weeks, oddWeeks(totalWeeks))) return '单周';
  if (setEquals(weeks, evenWeeks(totalWeeks))) return '双周';
  final parts = compressRanges(weeks)
      .map((r) => r.$1 == r.$2 ? '${r.$1}' : '${r.$1}-${r.$2}')
      .join(',');
  return '$parts周';
}

bool setEquals(Set<int> a, Set<int> b) =>
    a.length == b.length && a.containsAll(b);
