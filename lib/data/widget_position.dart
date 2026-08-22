import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'store.dart';

/// 挂件窗口位置单独存一个小文件。
///
/// 主数据文件只由主窗口进程写；挂件被拖动后需要记住位置，如果也去写主文件，
/// 就会把主窗口刚保存的编辑整份覆盖掉。拆成两个文件，两个进程各写各的，
/// 从根上没有冲突。
class WidgetPositionStore {
  WidgetPositionStore(this.store);

  final DataStore store;

  Future<File> _file() async =>
      File('${(await store.directory()).path}${Platform.pathSeparator}widget_pos.json');

  Future<Offset?> load() async {
    try {
      final file = await _file();
      if (!file.existsSync()) return null;
      final json = jsonDecode(utf8.decode(await file.readAsBytes()));
      if (json is! Map) return null;
      final x = (json['x'] as num?)?.toDouble();
      final y = (json['y'] as num?)?.toDouble();
      if (x == null || y == null) return null;
      return Offset(x, y);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(Offset position) async {
    try {
      final file = await _file();
      await file.parent.create(recursive: true);
      await file.writeAsBytes(
        utf8.encode(jsonEncode({'x': position.dx, 'y': position.dy})),
        flush: true,
      );
    } catch (_) {
      // 位置记不住不是什么大事，不要因此打扰用户。
    }
  }
}
