import 'dart:io';

import 'windows_registry.dart';

/// 开机自启动：往 HKCU 的 Run 键写一条指向挂件模式的记录。
///
/// 注册的是 `desktile.exe --widget`，也就是开机后直接出现桌面挂件 + 托盘图标，
/// 而不是弹出主窗口。
class AutoStart {
  static const _runKey =
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
  static const _valueName = 'DeskTile';

  static String get _command => '"${Platform.resolvedExecutable}" --widget';

  static Future<bool> isEnabled() async {
    final value = await WindowsRegistry.read(_runKey, _valueName);
    if (value == null) return false;
    // 程序被移动过就当作没启用，下次开关会写入新路径。
    return value.contains(Platform.resolvedExecutable);
  }

  static Future<bool> setEnabled(bool enabled) async {
    if (enabled) {
      return WindowsRegistry.write(_runKey, _valueName, _command);
    }
    return WindowsRegistry.delete(_runKey, _valueName);
  }
}
