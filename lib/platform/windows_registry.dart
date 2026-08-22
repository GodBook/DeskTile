import 'dart:io';

/// 一点点 Windows 注册表操作，直接调 reg.exe。
///
/// 只碰 HKCU，不需要管理员权限，用户随时能在注册表编辑器里删掉。
/// 为此没有引入 win32_registry —— 它和 file_picker 依赖的 win32 版本冲突。
class WindowsRegistry {
  static Future<String?> read(String keyPath, String valueName) async {
    if (!Platform.isWindows) return null;
    final result = await Process.run(
      'reg',
      ['query', keyPath, '/v', valueName],
      stdoutEncoding: SystemEncoding(),
    );
    if (result.exitCode != 0) return null;
    // 输出形如:    ValueName    REG_SZ    the value
    for (final line in '${result.stdout}'.split('\n')) {
      final trimmed = line.trim();
      if (!trimmed.startsWith(valueName)) continue;
      final match = RegExp(r'REG_[A-Z_]+\s+(.*)$').firstMatch(trimmed);
      if (match != null) return match.group(1)!.trim();
    }
    return null;
  }

  static Future<bool> write(
    String keyPath,
    String valueName,
    String value, {
    String type = 'REG_SZ',
  }) async {
    if (!Platform.isWindows) return false;
    final result = await Process.run(
      'reg',
      ['add', keyPath, '/v', valueName, '/t', type, '/d', value, '/f'],
      stdoutEncoding: SystemEncoding(),
    );
    return result.exitCode == 0;
  }

  static Future<bool> delete(String keyPath, String valueName) async {
    if (!Platform.isWindows) return false;
    final result = await Process.run(
      'reg',
      ['delete', keyPath, '/v', valueName, '/f'],
      stdoutEncoding: SystemEncoding(),
    );
    return result.exitCode == 0;
  }
}
