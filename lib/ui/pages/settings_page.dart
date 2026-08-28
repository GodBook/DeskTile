import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/models/settings.dart';
import '../../core/models/time_slot.dart';
import '../../data/app_state.dart';
import '../../platform/android_system_settings.dart';
import '../../platform/android_update.dart';
import '../../platform/android_widget.dart';
import '../../platform/autostart.dart';
import '../../platform/notifications.dart';
import '../../platform/single_instance.dart';
import '../theme.dart';

@visibleForTesting
bool shouldRequestAndroidReminderPermissions({
  required bool isAndroid,
  required bool wasEnabled,
  required bool willBeEnabled,
  bool explicitlyRequested = false,
}) {
  return isAndroid && (explicitlyRequested || (!wasEnabled && willBeEnabled));
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.reminders});

  final ReminderService reminders;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _autoStart = false;
  int _pending = 0;

  @override
  void initState() {
    super.initState();
    _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    final auto = Platform.isWindows ? await AutoStart.isEnabled() : false;
    final pending = await widget.reminders.pendingCount();
    if (mounted) {
      setState(() {
        _autoStart = auto;
        _pending = pending;
      });
    }
  }

  Future<void> _applySettings(
    AppSettings settings, {
    bool explicitlyRequestPermissions = false,
  }) async {
    final state = AppScope.read(context);
    final requestPermissions = shouldRequestAndroidReminderPermissions(
      isAndroid: Platform.isAndroid,
      wasEnabled: state.settings.reminderEnabled,
      willBeEnabled: settings.reminderEnabled,
      explicitlyRequested: explicitlyRequestPermissions,
    );
    await state.updateSettings(settings);
    if (requestPermissions) {
      await widget.reminders.requestAndroidPermissions();
    }
    await widget.reminders.reschedule(
      timetable: state.activeTimetable,
      settings: settings,
    );
    await _refreshStatus();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final s = state.settings;
    final t = state.activeTimetable;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _Section(
          title: '学期',
          children: [
            if (t != null) ...[
              ListTile(
                title: const Text('课表名称'),
                subtitle: Text(t.name),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () => _editName(t.name),
              ),
              ListTile(
                title: const Text('第一周的周一'),
                subtitle: Text(
                  '${monthDayText(t.termStart)}'
                  '（${t.termStart.year} 年）· 选任意一天都会自动对齐到周一',
                ),
                trailing: const Icon(Icons.event),
                onTap: () async {
                  final state = AppScope.read(context);
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: t.termStart,
                    firstDate: DateTime(t.termStart.year - 2),
                    lastDate: DateTime(t.termStart.year + 3),
                  );
                  if (picked != null) {
                    await state.updateActiveTimetable(
                      (c) => c.copyWith(termStart: picked),
                    );
                    await _applySettings(s);
                  }
                },
              ),
              ListTile(
                title: const Text('总周数'),
                subtitle: Slider(
                  value: t.totalWeeks.toDouble(),
                  min: 10,
                  max: 30,
                  divisions: 20,
                  label: '${t.totalWeeks} 周',
                  onChanged: (v) => AppScope.read(context)
                      .updateActiveTimetable(
                        (c) => c.copyWith(totalWeeks: v.round()),
                      ),
                ),
                trailing: Text('${t.totalWeeks} 周'),
              ),
              SwitchListTile(
                title: const Text('显示周末'),
                value: t.showWeekend,
                onChanged: (v) => AppScope.read(context)
                    .updateActiveTimetable((c) => c.copyWith(showWeekend: v)),
              ),
            ],
          ],
        ),
        if (t != null) _TimeSlotsSection(slots: t.timeSlots),
        _Section(
          title: '早八提醒',
          children: [
            SwitchListTile(
              title: const Text('开启上课提醒'),
              subtitle: Text('当前已排定 $_pending 条通知'),
              value: s.reminderEnabled,
              onChanged: (v) => _applySettings(s.copyWith(reminderEnabled: v)),
            ),
            RadioGroup<ReminderMode>(
              groupValue: s.reminderMode,
              onChanged: (v) => v == null
                  ? null
                  : _applySettings(s.copyWith(reminderMode: v)),
              child: const Column(
                children: [
                  RadioListTile<ReminderMode>(
                    value: ReminderMode.firstClassOfDay,
                    title: Text('只提醒每天第一节（早八）'),
                    subtitle: Text('第一节课开始得够早才提醒，正文里带教室'),
                  ),
                  RadioListTile<ReminderMode>(
                    value: ReminderMode.everyClass,
                    title: Text('每节课都提醒'),
                  ),
                ],
              ),
            ),
            ListTile(
              title: const Text('提前多久提醒'),
              subtitle: Slider(
                value: s.leadMinutes.toDouble(),
                min: 5,
                max: 90,
                divisions: 17,
                label: '${s.leadMinutes} 分钟',
                onChanged: (v) =>
                    _applySettings(s.copyWith(leadMinutes: v.round())),
              ),
              trailing: Text('${s.leadMinutes} 分钟'),
            ),
            ListTile(
              enabled: s.reminderMode == ReminderMode.firstClassOfDay,
              title: const Text('「早八」判定阈值'),
              subtitle: Slider(
                value: s.earlyClassCutoffMinutes.toDouble(),
                min: 7 * 60,
                max: 24 * 60,
                divisions: 34,
                label: formatMinutes(s.earlyClassCutoffMinutes),
                onChanged: s.reminderMode == ReminderMode.firstClassOfDay
                    ? (v) => _applySettings(
                        s.copyWith(
                          earlyClassCutoffMinutes: (v / 30).round() * 30,
                        ),
                      )
                    : null,
              ),
              trailing: Text('早于 ${formatMinutes(s.earlyClassCutoffMinutes)}'),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: () async {
                      final ok = await widget.reminders.scheduleTest();
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            ok
                                ? '10 秒后会弹一条测试提醒，请留意右下角'
                                : '通知没能排上：${widget.reminders.lastError ?? '未知原因'}',
                          ),
                        ),
                      );
                      await _refreshStatus();
                    },
                    icon: const Icon(
                      Icons.notifications_active_outlined,
                      size: 18,
                    ),
                    label: const Text('10 秒后测试提醒'),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: () =>
                        _applySettings(s, explicitlyRequestPermissions: true),
                    child: const Text('重新排定'),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (Platform.isWindows)
          _Section(
            title: '桌面挂件',
            children: [
              ListTile(
                title: const Text('不透明度'),
                subtitle: Slider(
                  value: s.widgetOpacity,
                  min: 0.3,
                  max: 1.0,
                  divisions: 14,
                  label: '${(s.widgetOpacity * 100).round()}%',
                  onChanged: (v) =>
                      _applySettings(s.copyWith(widgetOpacity: v)),
                ),
                trailing: Text('${(s.widgetOpacity * 100).round()}%'),
              ),
              SwitchListTile(
                title: const Text('迷你模式'),
                subtitle: const Text('只显示下一节课'),
                value: s.widgetForm == WidgetForm.mini,
                onChanged: (v) => _applySettings(
                  s.copyWith(
                    widgetForm: v ? WidgetForm.mini : WidgetForm.standard,
                  ),
                ),
              ),
              SwitchListTile(
                title: const Text('贴在桌面上'),
                subtitle: const Text('开启后不会遮挡其它窗口；关闭则始终置顶'),
                value: s.widgetAlwaysOnBottom,
                onChanged: (v) =>
                    _applySettings(s.copyWith(widgetAlwaysOnBottom: v)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Row(
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: ModeLauncher.openWidget,
                      icon: const Icon(
                        Icons.desktop_windows_outlined,
                        size: 18,
                      ),
                      label: const Text('显示桌面挂件'),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '挂件是一个独立的常驻进程，带托盘图标。拖动任意位置即可移动，'
                        '位置会被记住。',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        if (Platform.isAndroid) ...[
          const _AndroidBackgroundSection(),
          const _AndroidWidgetSection(),
          const _AndroidUpdateSection(),
        ],
        _Section(
          title: '启动与外观',
          children: [
            if (Platform.isWindows)
              SwitchListTile(
                title: const Text('开机自动启动桌面挂件'),
                subtitle: const Text(
                  r'写入 HKCU\...\CurrentVersion\Run，不需要管理员权限',
                ),
                value: _autoStart,
                onChanged: (v) async {
                  await AutoStart.setEnabled(v);
                  await _refreshStatus();
                },
              ),
            RadioGroup<ThemePref>(
              groupValue: s.theme,
              onChanged: (v) =>
                  v == null ? null : _applySettings(s.copyWith(theme: v)),
              child: const Column(
                children: [
                  RadioListTile<ThemePref>(
                    value: ThemePref.system,
                    title: Text('跟随系统'),
                  ),
                  RadioListTile<ThemePref>(
                    value: ThemePref.light,
                    title: Text('浅色'),
                  ),
                  RadioListTile<ThemePref>(
                    value: ThemePref.dark,
                    title: Text('深色'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _editName(String current) async {
    final state = AppScope.read(context);
    final controller = TextEditingController(text: current);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('课表名称'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      await state.updateActiveTimetable((c) => c.copyWith(name: result));
    }
  }
}

class _AndroidBackgroundSection extends StatelessWidget {
  const _AndroidBackgroundSection();

  Future<void> _openSettings(BuildContext context) async {
    final opened = await AndroidSystemSettings.openAppDetails();
    if (!context.mounted || opened) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('无法打开系统设置，请从系统应用列表中找到 DeskTile')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: '后台可靠性',
      children: [
        const ListTile(
          leading: Icon(Icons.battery_saver_outlined),
          title: Text('允许后台运行'),
          subtitle: Text('部分手机会限制课程提醒；请在应用详情中允许后台运行，并按需开启自启动。'),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              onPressed: () => _openSettings(context),
              icon: const Icon(Icons.settings_outlined, size: 18),
              label: const Text('打开应用详情'),
            ),
          ),
        ),
      ],
    );
  }
}

/// Android 主屏小组件的轻量控制面板。小组件由系统启动，不需要也不应该
/// 复用 Windows 的独立桌面进程/托盘入口。
class _AndroidWidgetSection extends StatelessWidget {
  const _AndroidWidgetSection();

  Future<void> _pin(BuildContext context) async {
    final ok = await AndroidWidgetService.requestPin();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? '已向系统发送添加小组件请求，请在主屏确认' : '当前启动器不支持一键添加，请在主屏的小组件列表中选择 DeskTile',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: '主屏小组件',
      children: [
        const ListTile(
          leading: Icon(Icons.widgets_outlined),
          title: Text('课表岛小组件'),
          subtitle: Text('显示下一节课、今日剩余课程和最近考试；数据会随课表保存自动刷新。'),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              onPressed: () => _pin(context),
              icon: const Icon(Icons.add_to_home_screen_outlined, size: 18),
              label: const Text('添加到主屏'),
            ),
          ),
        ),
      ],
    );
  }
}

class _AndroidUpdateSection extends StatefulWidget {
  const _AndroidUpdateSection();

  @override
  State<_AndroidUpdateSection> createState() => _AndroidUpdateSectionState();
}

class _AndroidUpdateSectionState extends State<_AndroidUpdateSection> {
  late final AndroidUpdateService _updates;
  AndroidUpdateCheckResult? _checkResult;
  AndroidDownloadedApk? _downloaded;
  String? _error;
  bool _checking = false;
  bool _downloading = false;
  bool _installing = false;
  int _receivedBytes = 0;
  int? _totalBytes;

  @override
  void initState() {
    super.initState();
    _updates = AndroidUpdateService();
  }

  @override
  void dispose() {
    _updates.dispose();
    super.dispose();
  }

  Future<void> _checkForUpdate() async {
    if (_checking || _downloading || _installing) return;
    setState(() {
      _checking = true;
      _error = null;
      _checkResult = null;
      _downloaded = null;
    });
    try {
      final result = await _updates.checkForUpdate();
      if (!mounted) return;
      setState(() => _checkResult = result);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.hasUpdate ? '发现新版本 v${result.update!.version}' : '当前已经是最新版本',
          ),
        ),
      );
    } on AndroidUpdateException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = '检查更新失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _downloadAndInstall() async {
    final info = _checkResult?.update;
    if (info == null || _downloading || _installing) return;

    setState(() {
      _downloading = true;
      _error = null;
      _receivedBytes = 0;
      _totalBytes = info.sizeBytes;
    });
    try {
      final apk = await _updates.download(
        info,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _receivedBytes = received;
            _totalBytes = total ?? info.sizeBytes;
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _downloaded = apk;
        _downloading = false;
        _receivedBytes = apk.bytes;
        _totalBytes = apk.bytes;
      });
      await _installDownloaded(apk);
    } on AndroidUpdateException catch (error) {
      if (mounted) {
        setState(() {
          _downloading = false;
          _error = error.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _downloading = false;
          _error = '下载更新失败，请稍后重试';
        });
      }
    }
  }

  Future<void> _installDownloaded(AndroidDownloadedApk apk) async {
    if (_installing) return;
    setState(() => _installing = true);
    try {
      final result = await _updates.install(apk);
      if (!mounted) return;
      if (result == AndroidInstallResult.permissionRequired) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请在系统设置中允许 DeskTile 安装未知应用，返回后再次点击安装')),
        );
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('系统安装器已打开，请确认升级')));
      }
    } on AndroidUpdateException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = '无法启动系统安装器');
    } finally {
      if (mounted) setState(() => _installing = false);
    }
  }

  String _versionLabel() {
    final current = _checkResult?.currentVersion ?? defaultAndroidVersion;
    return '当前版本 v$current';
  }

  String? _subtitle() {
    if (_checking) return '正在检查最新稳定版…';
    if (_installing) return '正在打开系统安装器…';
    if (_downloading) {
      final total = _totalBytes;
      if (total != null && total > 0) {
        return '正在下载 ${(100 * _receivedBytes / total).clamp(0, 100).round()}%';
      }
      return '正在下载…';
    }
    if (_error != null) return _error;
    final info = _checkResult?.update;
    if (info != null) return '发现 v${info.version}，可直接覆盖安装';
    if (_checkResult != null) return '已是最新版本';
    return '从发布页获取最新 Android 安装包';
  }

  @override
  Widget build(BuildContext context) {
    final info = _checkResult?.update;
    final downloaded = _downloaded;
    final subtitle = _subtitle();
    final progress = _totalBytes != null && _totalBytes! > 0
        ? (_receivedBytes / _totalBytes!).clamp(0.0, 1.0)
        : null;

    return _Section(
      title: '应用更新',
      children: [
        ListTile(
          leading: const Icon(Icons.system_update_outlined),
          title: Text(_versionLabel()),
          subtitle: subtitle == null
              ? null
              : Text(
                  subtitle,
                  style: _error == null
                      ? null
                      : TextStyle(color: Theme.of(context).colorScheme.error),
                ),
          trailing: _checking || _downloading || _installing
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
        ),
        if (info != null) ...[
          ListTile(
            leading: const Icon(Icons.new_releases_outlined),
            title: Text('新版本 v${info.version}'),
            subtitle: info.notes == null || info.notes!.trim().isEmpty
                ? const Text('下载后由系统安装器完成升级')
                : Text(
                    info.notes!.trim(),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
          ),
          if (progress != null && _downloading)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: LinearProgressIndicator(value: progress),
            ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: _checking || _downloading || _installing
                    ? null
                    : _checkForUpdate,
                icon: const Icon(Icons.refresh_outlined, size: 18),
                label: const Text('检查更新'),
              ),
              if (info != null)
                FilledButton.icon(
                  onPressed: _downloading || _installing
                      ? null
                      : () => downloaded == null
                            ? _downloadAndInstall()
                            : _installDownloaded(downloaded),
                  icon: Icon(
                    downloaded == null
                        ? Icons.download_outlined
                        : Icons.install_mobile_outlined,
                    size: 18,
                  ),
                  label: Text(downloaded == null ? '下载并安装' : '继续安装'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 4),
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          Card(child: Column(children: children)),
        ],
      ),
    );
  }
}

/// 节次时间表编辑。导入 CSES/ICS 时节次是推算出来的，这里可以修正。
class _TimeSlotsSection extends StatelessWidget {
  const _TimeSlotsSection({required this.slots});

  final List<TimeSlot> slots;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: '节次时间表',
      children: [
        for (final slot in slots)
          ListTile(
            dense: true,
            leading: SizedBox(
              width: 44,
              child: Text(
                '第${slot.index}节',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
            title: Text('${slot.startText} - ${slot.endText}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: '修改时间',
                  icon: const Icon(Icons.schedule, size: 18),
                  onPressed: () => _editSlot(context, slot),
                ),
                IconButton(
                  tooltip: '删除该节',
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: slots.length <= 1
                      ? null
                      : () => AppScope.read(context).updateActiveTimetable(
                          (c) => c.copyWith(
                            timeSlots: _renumber(
                              c.timeSlots.where((s) => s.index != slot.index),
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Row(
            children: [
              OutlinedButton.icon(
                onPressed: () => AppScope.read(context).updateActiveTimetable((
                  c,
                ) {
                  final last = c.timeSlots.isEmpty ? null : c.timeSlots.last;
                  final start = last == null ? 8 * 60 : last.endMinutes + 10;
                  return c.copyWith(
                    timeSlots: [
                      ...c.timeSlots,
                      TimeSlot(
                        index: c.timeSlots.length + 1,
                        startMinutes: start % (24 * 60),
                        endMinutes: (start + 45) % (24 * 60),
                      ),
                    ],
                  );
                }),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('添加一节'),
              ),
              const SizedBox(width: 12),
              TextButton(
                onPressed: () => AppScope.read(context).updateActiveTimetable(
                  (c) => c.copyWith(timeSlots: kDefaultTimeSlots),
                ),
                child: const Text('恢复默认 12 节'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static List<TimeSlot> _renumber(Iterable<TimeSlot> input) {
    final list = input.toList()..sort((a, b) => a.index.compareTo(b.index));
    return [
      for (var i = 0; i < list.length; i++) list[i].copyWith(index: i + 1),
    ];
  }

  Future<void> _editSlot(BuildContext context, TimeSlot slot) async {
    final state = AppScope.read(context);
    final start = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: slot.startMinutes ~/ 60,
        minute: slot.startMinutes % 60,
      ),
      helpText: '第${slot.index}节 开始时间',
    );
    if (start == null || !context.mounted) return;
    final end = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: slot.endMinutes ~/ 60,
        minute: slot.endMinutes % 60,
      ),
      helpText: '第${slot.index}节 结束时间',
    );
    if (end == null) return;

    await state.updateActiveTimetable(
      (c) => c.copyWith(
        timeSlots: [
          for (final s in c.timeSlots)
            if (s.index == slot.index)
              s.copyWith(
                startMinutes: start.hour * 60 + start.minute,
                endMinutes: end.hour * 60 + end.minute,
              )
            else
              s,
        ],
      ),
    );
  }
}
