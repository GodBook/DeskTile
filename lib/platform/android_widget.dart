import 'dart:io';

import 'package:home_widget/home_widget.dart';

import '../core/models/exam.dart';
import '../core/models/timetable.dart';
import '../core/widget_payload.dart';

/// Dart 与 Android Glance 小组件之间的窄桥。
///
/// 只有 Android 会真正调用 HomeWidget 的 MethodChannel；Windows/Linux 测试
/// 和桌面挂件进程直接返回 false，避免误触发平台插件。
class AndroidWidgetService {
  AndroidWidgetService._();

  static String? _lastError;

  static bool get supported => Platform.isAndroid;
  static String? get lastError => _lastError;

  /// 计算并写入当前课表快照，然后通知原生小组件刷新。
  static Future<bool> update({
    required Timetable? timetable,
    List<Exam> exams = const [],
    DateTime? now,
  }) async {
    if (!supported) return false;
    try {
      final payload = buildWidgetPayload(
        timetable: timetable,
        exams: exams,
        now: now,
      );
      final saved = await HomeWidget.saveWidgetData<String>(
        androidWidgetPayloadKey,
        payload.encode(),
      );
      final refreshed = await HomeWidget.updateWidget(
        qualifiedAndroidName: androidWidgetProviderName,
      );
      _lastError = null;
      return saved != false && refreshed != false;
    } catch (e) {
      _lastError = '$e';
      return false;
    }
  }

  /// 请求系统把小组件固定到主屏（Android 8+ 且取决于启动器支持）。
  static Future<bool> requestPin() async {
    if (!supported) return false;
    try {
      final supportedByLauncher =
          await HomeWidget.isRequestPinWidgetSupported() ?? false;
      if (!supportedByLauncher) return false;
      await HomeWidget.requestPinWidget(
        qualifiedAndroidName: androidWidgetProviderName,
      );
      return true;
    } catch (e) {
      _lastError = '$e';
      return false;
    }
  }
}
