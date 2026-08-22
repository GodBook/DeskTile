import 'dart:io';

import 'package:flutter/services.dart';

/// 打开 Android 针对当前应用的系统设置页。
class AndroidSystemSettings {
  AndroidSystemSettings._();

  static const _channel = MethodChannel(
    'com.desktile.desktile/system_settings',
  );

  static Future<bool> openAppDetails() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('openAppDetails') ?? false;
    } on PlatformException {
      return false;
    }
  }
}
