// 直接触发测试提醒，绕开 UI，用来验证通知链路
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:desktile/platform/notifications.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();

  print('初始化通知服务...');
  final service = ReminderService();
  final ready = await service.init();
  print('ready=$ready lastError=${service.lastError}');

  if (!ready) {
    print('初始化失败，退出');
    exit(1);
  }

  print('排定 5 秒后的测试提醒...');
  final ok = await service.scheduleTest(delay: Duration(seconds: 5));
  print('scheduleTest返回=$ok lastError=${service.lastError}');

  if (ok) {
    final pending = await service.pendingCount();
    print('pendingCount=$pending');
    print('5 秒后应该弹出通知，请留意右下角。脚本会等 10 秒再退出。');
    await Future.delayed(Duration(seconds: 10));
  }

  print('退出');
  exit(0);
}
