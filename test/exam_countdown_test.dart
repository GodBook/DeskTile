import 'package:desktile/core/exam_countdown.dart';
import 'package:desktile/core/models/exam.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 12, 20, 10, 0);
  final exams = [
    Exam(
      id: 'e1',
      name: '高等数学',
      startAt: DateTime(2027, 1, 5, 9, 0),
      endAt: DateTime(2027, 1, 5, 11, 0),
      room: '教三-305',
      seat: '12',
    ),
    Exam(id: 'e2', name: '大学英语', startAt: DateTime(2026, 12, 25, 14, 0)),
    Exam(id: 'e3', name: '已考完的课', startAt: DateTime(2026, 12, 1, 9, 0)),
    Exam(id: 'e4', name: '正在考', startAt: DateTime(2026, 12, 20, 9, 0)),
  ];

  group('upcomingExams', () {
    test('按开考时间升序，排除考完的', () {
      final list = upcomingExams(exams, now);
      expect(list.map((c) => c.exam.name), ['正在考', '大学英语', '高等数学']);
    });

    test('limit 生效', () {
      expect(upcomingExams(exams, now, limit: 2).length, 2);
    });

    test('正在考的剩余时间为负', () {
      final first = upcomingExams(exams, now).first;
      expect(first.started, isTrue);
      expect(first.remainingText, '已开始');
    });

    test('nearestExam 取最近一场', () {
      expect(nearestExam(exams, now)?.exam.name, '正在考');
    });

    test('没有考试时 nearestExam 为 null', () {
      expect(nearestExam(const [], now), isNull);
    });
  });

  group('pastExams', () {
    test('倒序列出考完的', () {
      expect(pastExams(exams, now).map((e) => e.name), ['已考完的课']);
    });
  });

  group('examEndAt', () {
    test('没填结束时间时按 2 小时估算', () {
      expect(examEndAt(exams[1]), DateTime(2026, 12, 25, 16, 0));
    });

    test('填了就用填的', () {
      expect(examEndAt(exams[0]), DateTime(2027, 1, 5, 11, 0));
    });
  });

  group('formatRemaining', () {
    test('天 + 小时', () {
      expect(formatRemaining(const Duration(days: 12, hours: 3)), '12 天 3 小时');
    });

    test('整天不带小时', () {
      expect(formatRemaining(const Duration(days: 5)), '5 天');
    });

    test('小时 + 分', () {
      expect(formatRemaining(const Duration(hours: 3, minutes: 20)), '3 小时 20 分');
    });

    test('整小时', () {
      expect(formatRemaining(const Duration(hours: 2)), '2 小时');
    });

    test('分钟', () {
      expect(formatRemaining(const Duration(minutes: 18)), '18 分钟');
    });

    test('不到一分钟', () {
      expect(formatRemaining(const Duration(seconds: 30)), '不到 1 分钟');
    });

    test('已开始', () {
      expect(formatRemaining(const Duration(minutes: -5)), '已开始');
    });
  });
}
