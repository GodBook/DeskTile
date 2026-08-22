import 'package:desktile/core/import/field_parsers.dart';
import 'package:desktile/core/week_math.dart';
import 'package:desktile/core/weeks_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseWeeks', () {
    test('连续区间', () {
      expect(parseWeeks('1-16', totalWeeks: 20), allWeeks(16));
    });

    test('带「周」字和「第」字', () {
      expect(parseWeeks('第1-8周', totalWeeks: 20), {1, 2, 3, 4, 5, 6, 7, 8});
    });

    test('全角逗号与混合区间', () {
      expect(parseWeeks('1，3，5-9', totalWeeks: 20), {1, 3, 5, 6, 7, 8, 9});
    });

    test('单周过滤', () {
      expect(parseWeeks('1-16单', totalWeeks: 20), {1, 3, 5, 7, 9, 11, 13, 15});
    });

    test('双周过滤', () {
      expect(parseWeeks('1-16双周', totalWeeks: 20), {2, 4, 6, 8, 10, 12, 14, 16});
    });

    test('只写「双」时用总周数展开', () {
      expect(parseWeeks('双', totalWeeks: 8), {2, 4, 6, 8});
    });

    test('「单双周」当作每周', () {
      expect(parseWeeks('单双周', totalWeeks: 6), allWeeks(6));
    });

    test('超出总周数会被裁掉', () {
      expect(parseWeeks('1-30', totalWeeks: 20), allWeeks(20));
    });

    test('区间写反也能认', () {
      expect(parseWeeks('9-5', totalWeeks: 20), {5, 6, 7, 8, 9});
    });

    test('全角波浪号当作区间符', () {
      expect(parseWeeks('3～6', totalWeeks: 20), {3, 4, 5, 6});
    });

    test('完全看不懂时抛异常', () {
      expect(() => parseWeeks('每周都有', totalWeeks: 20), throwsFormatException);
    });

    test('tryParseWeeks 失败返回 null', () {
      expect(tryParseWeeks('每周都有', totalWeeks: 20), isNull);
      expect(tryParseWeeks('1-4', totalWeeks: 20), {1, 2, 3, 4});
    });
  });

  group('formatWeeks', () {
    test('每周 / 单周 / 双周', () {
      expect(formatWeeks(allWeeks(16), totalWeeks: 16), '每周');
      expect(formatWeeks(oddWeeks(16), totalWeeks: 16), '单周');
      expect(formatWeeks(evenWeeks(16), totalWeeks: 16), '双周');
    });

    test('压成区间', () {
      expect(formatWeeks({1, 2, 3, 5, 7, 8}, totalWeeks: 16), '1-3,5,7-8周');
    });

    test('空集合', () {
      expect(formatWeeks({}, totalWeeks: 16), '未设置');
    });

    test('parseWeeks 与 formatWeeks 往返一致', () {
      const text = '1-8,10,12-16周';
      final parsed = parseWeeks(text, totalWeeks: 20);
      expect(formatWeeks(parsed, totalWeeks: 20), text);
    });
  });

  group('compressRanges', () {
    test('合并连续段', () {
      expect(compressRanges([1, 2, 3, 5, 7, 8]), [(1, 3), (5, 5), (7, 8)]);
    });

    test('乱序与重复', () {
      expect(compressRanges([3, 1, 2, 2]), [(1, 3)]);
    });
  });

  group('parseWeekDay', () {
    test('数字', () {
      expect(parseWeekDay('1'), 1);
      expect(parseWeekDay('7'), 7);
      expect(parseWeekDay('8'), isNull);
    });

    test('中文', () {
      expect(parseWeekDay('周三'), 3);
      expect(parseWeekDay('星期五'), 5);
      expect(parseWeekDay('星期日'), 7);
      expect(parseWeekDay('星期天'), 7);
      expect(parseWeekDay('六'), 6);
    });

    test('英文', () {
      expect(parseWeekDay('Wed'), 3);
      expect(parseWeekDay('sunday'), 7);
    });

    test('认不出返回 null', () {
      expect(parseWeekDay('foo'), isNull);
      expect(parseWeekDay(''), isNull);
    });
  });

  group('parseSections', () {
    test('区间与列表', () {
      expect(parseSections('1-2'), [1, 2]);
      expect(parseSections('1,2,5'), [1, 2, 5]);
      expect(parseSections('3'), [3]);
    });
  });
}
