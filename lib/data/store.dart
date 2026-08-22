import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'app_data.dart';

export 'app_data.dart';

/// JSON 文件读写。写入走「临时文件 + rename」，避免掉电/崩溃留下半截文件。
class DataStore {
  DataStore({this.overrideDirectory});

  /// 测试时可以指定目录。
  final Directory? overrideDirectory;

  Directory? _dir;

  Future<Directory> directory() async =>
      _dir ??= overrideDirectory ?? await getApplicationSupportDirectory();

  Future<File> dataFile() async => File(
      '${(await directory()).path}${Platform.pathSeparator}desktile_data.json');

  Future<AppData> load() async {
    final file = await dataFile();
    if (!file.existsSync()) return AppData.initial();
    try {
      final text = utf8.decode(await file.readAsBytes());
      final json = jsonDecode(text);
      if (json is! Map<String, dynamic>) return AppData.initial();
      return AppData.fromJson(json);
    } catch (_) {
      // 文件坏了不能让程序起不来：备份一份再从空数据开始。
      try {
        final backup = File('${file.path}.broken');
        if (backup.existsSync()) backup.deleteSync();
        file.renameSync(backup.path);
      } catch (_) {}
      return AppData.initial();
    }
  }

  Future<void> save(AppData data) async {
    final file = await dataFile();
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsBytes(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(data.toJson())),
      flush: true,
    );
    if (file.existsSync()) file.deleteSync();
    await tmp.rename(file.path);
  }

  /// 监听数据文件变化（挂件进程用）。事件做 300ms 防抖，
  /// 因为一次保存会产生 .tmp 创建、删除、重命名等多个事件。
  Stream<void> watch({Duration debounce = const Duration(milliseconds: 300)}) {
    final controller = StreamController<void>.broadcast();
    Timer? timer;
    StreamSubscription<FileSystemEvent>? sub;

    controller.onListen = () async {
      final dir = await directory();
      await dir.create(recursive: true);
      final target = (await dataFile()).path;
      sub = dir.watch().listen((event) {
        if (!event.path.startsWith(target)) return;
        timer?.cancel();
        timer = Timer(debounce, () {
          if (!controller.isClosed) controller.add(null);
        });
      });
    };
    controller.onCancel = () async {
      timer?.cancel();
      await sub?.cancel();
    };
    return controller.stream;
  }
}

var _idCounter = 0;

/// 生成本地唯一 id。
String newId(String prefix) =>
    '$prefix${DateTime.now().microsecondsSinceEpoch}${_idCounter++}';
