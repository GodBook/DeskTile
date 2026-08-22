import 'dart:async';

import 'package:flutter/widgets.dart';

import '../core/models/exam.dart';
import '../core/models/settings.dart';
import '../core/models/timetable.dart';
import 'store.dart';

/// 应用状态。没有引入状态管理库 —— 一个 [ChangeNotifier] + [ListenableBuilder]
/// 就够用了，少一层概念。
///
/// 写盘只发生在主窗口进程（`readOnly == false`）。挂件进程只读，靠
/// [startWatching] 监听文件变化重新加载，从设计上避免跨进程写冲突。
class AppState extends ChangeNotifier {
  AppState({required this.store, this.readOnly = false});

  final DataStore store;
  final bool readOnly;

  AppData _data = AppData.initial();
  bool _loaded = false;
  StreamSubscription<void>? _watchSub;

  AppData get data => _data;
  bool get loaded => _loaded;
  AppSettings get settings => _data.settings;
  Timetable? get activeTimetable => _data.activeTimetable;
  List<Exam> get exams => _data.exams;

  Future<void> load() async {
    _data = await store.load();
    _loaded = true;
    notifyListeners();
  }

  /// 挂件进程用：数据文件被主窗口改写后重新读取。
  void startWatching() {
    _watchSub ??= store.watch().listen((_) async {
      _data = await store.load();
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _watchSub?.cancel();
    super.dispose();
  }

  Future<void> _mutate(AppData Function(AppData) change) async {
    assert(!readOnly, '挂件进程不应该写数据');
    _data = change(_data);
    notifyListeners();
    await store.save(_data);
  }

  Future<void> updateSettings(AppSettings settings) =>
      _mutate((d) => d.copyWith(settings: settings));

  /// 挂件进程改设置项时走这条路：先把磁盘上的最新数据读回来，只替换设置再写回，
  /// 这样即使主窗口刚保存过课表编辑，也不会被挂件整份覆盖掉。
  Future<void> mutateSettingsSafely(
      AppSettings Function(AppSettings) change) async {
    final fresh = await store.load();
    _data = fresh.copyWith(settings: change(fresh.settings));
    notifyListeners();
    await store.save(_data);
  }

  Future<void> setActiveTimetableId(String id) =>
      _mutate((d) => d.copyWith(activeTimetableId: id));

  /// 修改当前课表（改课程、改时段、改学期信息都走这里）。
  Future<void> updateActiveTimetable(Timetable Function(Timetable) change) =>
      _mutate((d) {
        final current = d.activeTimetable;
        if (current == null) return d;
        final updated = change(current);
        return d.copyWith(
          timetables: [
            for (final t in d.timetables) if (t.id == updated.id) updated else t,
          ],
          activeTimetableId: updated.id,
        );
      });

  /// 导入：整表替换（同 id 覆盖，新 id 追加）并设为当前课表。
  Future<void> putTimetable(Timetable timetable) => _mutate((d) {
        final exists = d.timetables.any((t) => t.id == timetable.id);
        return d.copyWith(
          timetables: exists
              ? [
                  for (final t in d.timetables)
                    if (t.id == timetable.id) timetable else t,
                ]
              : [...d.timetables, timetable],
          activeTimetableId: timetable.id,
        );
      });

  Future<void> deleteTimetable(String id) => _mutate((d) {
        final rest = d.timetables.where((t) => t.id != id).toList();
        if (rest.isEmpty) {
          final fresh = AppData.initial();
          return d.copyWith(
            timetables: fresh.timetables,
            activeTimetableId: fresh.activeTimetableId,
          );
        }
        return d.copyWith(
          timetables: rest,
          activeTimetableId:
              d.activeTimetableId == id ? rest.first.id : d.activeTimetableId,
        );
      });

  Future<void> putExam(Exam exam) => _mutate((d) {
        final exists = d.exams.any((e) => e.id == exam.id);
        return d.copyWith(
          exams: exists
              ? [for (final e in d.exams) if (e.id == exam.id) exam else e]
              : [...d.exams, exam],
        );
      });

  Future<void> deleteExam(String id) =>
      _mutate((d) => d.copyWith(exams: d.exams.where((e) => e.id != id).toList()));
}

/// 让子树能拿到 [AppState]，并在它变化时重建。
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
      : super(notifier: state);

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope?.notifier != null, '组件树上没有 AppScope');
    return scope!.notifier!;
  }

  /// 只读取、不订阅变化（回调里用）。
  static AppState read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    assert(scope?.notifier != null, '组件树上没有 AppScope');
    return scope!.notifier!;
  }
}
