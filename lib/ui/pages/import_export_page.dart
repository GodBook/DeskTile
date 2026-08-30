import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/import/course_info_dto.dart';
import '../../core/import/cses_importer.dart';
import '../../core/import/csv_importer.dart';
import '../../core/import/exporter.dart';
import '../../core/import/ics_importer.dart';
import '../../core/import/json_importer.dart';
import '../../core/models/timetable.dart';
import '../../core/models/task_item.dart';
import '../../core/week_math.dart';
import '../../data/app_state.dart';
import '../../data/store.dart';

/// 导入导出页。本期只做文件导入 + 手动录入；教务系统直连留在后续版本，
/// 解析通路（courseInfos）已经在 core 里备好。
class ImportExportPage extends StatelessWidget {
  const ImportExportPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('导入课表', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('支持这些格式，选文件后会先显示解析结果再确认导入：'),
                const SizedBox(height: 10),
                const _FormatLine(
                  ext: '.csv',
                  desc: '通用表格。表头：课程名称,教师,教室,星期,节次,周次',
                ),
                const _FormatLine(
                  ext: '.yaml / .yml',
                  desc: 'CSES 课表交换格式（可与 ClassIsland 等互通）',
                ),
                const _FormatLine(ext: '.ics', desc: '日历文件，教务系统常见的导出格式'),
                const _FormatLine(
                  ext: '.json',
                  desc: '小爱课程表 courseInfos 结构，或本程序导出的备份',
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: () => _pickAndImport(context),
                      icon: const Icon(Icons.file_open, size: 18),
                      label: const Text('选择文件导入…'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _saveCsvTemplate(context),
                      icon: const Icon(Icons.download, size: 18),
                      label: const Text('保存 CSV 模板'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text('导出与备份', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _exportBackup(context),
                  icon: const Icon(Icons.save_alt, size: 18),
                  label: const Text('导出备份 JSON（跨设备搬运用）'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _exportCses(context),
                  icon: const Icon(Icons.ios_share, size: 18),
                  label: const Text('导出 CSES YAML'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _openDataFolder(context),
                  icon: const Icon(Icons.folder_open, size: 18),
                  label: const Text('打开数据目录'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _FormatLine extends StatelessWidget {
  const _FormatLine({required this.ext, required this.desc});

  final String ext;
  final String desc;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              ext,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: 'Consolas',
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              desc,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 提前抓好 messenger 和主题色，避免 await 之后再碰 BuildContext。
class _Toast {
  _Toast(BuildContext context)
    : _messenger = ScaffoldMessenger.of(context),
      _errorColor = Theme.of(context).colorScheme.error;

  final ScaffoldMessengerState _messenger;
  final Color _errorColor;

  void show(String message, {bool error = false}) {
    _messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? _errorColor : null,
      ),
    );
  }
}

Future<void> _pickAndImport(BuildContext context) async {
  final toast = _Toast(context);
  final state = AppScope.read(context);
  final current = state.activeTimetable;
  if (current == null) return;

  final picked = await FilePicker.pickFile(
    dialogTitle: '选择课表文件',
    type: FileType.custom,
    allowedExtensions: const ['csv', 'yaml', 'yml', 'ics', 'json'],
  );
  if (picked == null) return;

  final String text;
  try {
    text = utf8.decode(await picked.readAsBytes(), allowMalformed: true);
  } catch (e) {
    toast.show('读取文件失败：$e', error: true);
    return;
  }

  final ext = picked.name.toLowerCase().split('.').last;
  ImportedSchedule imported;
  try {
    imported = switch (ext) {
      'csv' => importCsv(text, totalWeeks: current.totalWeeks),
      'yaml' || 'yml' => importCses(text, totalWeeks: current.totalWeeks),
      'ics' => importIcs(text),
      'json' => importCourseInfosJson(text, totalWeeks: current.totalWeeks),
      _ => throw FormatException('不支持的文件类型：.$ext'),
    };
  } on FormatException catch (e) {
    toast.show('解析失败：${e.message}', error: true);
    return;
  } catch (e) {
    toast.show('解析失败：$e', error: true);
    return;
  }

  if (!context.mounted) return;
  await showImportPreview(
    context,
    fileName: picked.name,
    imported: imported,
    base: current,
  );
}

/// 显示导入预览（解析结果 + 学期设置 + 警告），确认后整表覆盖当前课表。
///
/// 单独暴露出来是为了能直接测这一步 —— 只有前面选文件的原生对话框测不了。
Future<void> showImportPreview(
  BuildContext context, {
  required String fileName,
  required ImportedSchedule imported,
  required Timetable base,
}) => showDialog<void>(
  context: context,
  builder: (context) =>
      _ImportPreviewDialog(fileName: fileName, imported: imported, base: base),
);

class _ImportPreviewDialog extends StatefulWidget {
  const _ImportPreviewDialog({
    required this.fileName,
    required this.imported,
    required this.base,
  });

  final String fileName;
  final ImportedSchedule imported;
  final Timetable base;

  @override
  State<_ImportPreviewDialog> createState() => _ImportPreviewDialogState();
}

class _ImportPreviewDialogState extends State<_ImportPreviewDialog> {
  late DateTime _termStart;
  late int _totalWeeks;
  bool _replaceCurrent = true;

  @override
  void initState() {
    super.initState();
    _termStart = widget.imported.termStart ?? widget.base.termStart;
    _totalWeeks = widget.imported.totalWeeks ?? widget.base.totalWeeks;
  }

  Future<void> _confirm() async {
    final toast = _Toast(context);
    final state = AppScope.read(context);
    final navigator = Navigator.of(context);
    final warnings = <String>[...widget.imported.warnings];
    final timetableId = _replaceCurrent ? widget.base.id : newId('timetable');
    final timetable = buildTimetable(
      id: timetableId,
      name:
          widget.imported.name ??
          (_replaceCurrent ? widget.base.name : '${widget.base.name} 导入'),
      termStart: _termStart,
      imported: widget.imported,
      warnings: warnings,
      totalWeeks: _totalWeeks,
      timeSlots: widget.imported.timeSlots ?? widget.base.timeSlots,
    );
    await state.putTimetable(timetable);
    final importedTasks = widget.imported.tasks;
    if (importedTasks != null) {
      final sourceTimetableId = widget.imported.sourceTimetable?.id;
      final mapped = [
        for (final task in importedTasks)
          _importedTask(
            task,
            timetableId: timetable.id,
            sourceTimetableId: sourceTimetableId,
            assignNewId: !_replaceCurrent,
          ),
      ];
      await state.replaceTasks(
        _replaceCurrent ? mapped : [...state.tasks, ...mapped],
      );
    }
    navigator.pop();
    toast.show(
      '已导入 ${timetable.courses.length} 门课、${timetable.sessions.length} 个时段'
      '${importedTasks == null ? '' : '、${importedTasks.length} 项作业与待办'}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final imported = widget.imported;
    return AlertDialog(
      title: const Text('导入预览'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.fileName, style: theme.textTheme.bodySmall),
              const SizedBox(height: 10),
              Text(
                '解析到 ${imported.courseNames.length} 门课、'
                '${imported.sessionCount} 个上课时段',
              ),
              if (imported.tasks != null) ...[
                const SizedBox(height: 4),
                Text('备份包含 ${imported.tasks!.length} 项作业与待办'),
              ],
              const SizedBox(height: 14),
              SegmentedButton<bool>(
                key: const ValueKey('import-mode'),
                segments: const [
                  ButtonSegment(
                    value: true,
                    icon: Icon(Icons.refresh, size: 18),
                    label: Text('覆盖当前'),
                  ),
                  ButtonSegment(
                    value: false,
                    icon: Icon(Icons.add_box_outlined, size: 18),
                    label: Text('新建课表'),
                  ),
                ],
                selected: {_replaceCurrent},
                onSelectionChanged: (value) =>
                    setState(() => _replaceCurrent = value.single),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.event, size: 18),
                      label: Text(
                        '第一周周一：'
                        '${_termStart.month}月${_termStart.day}日',
                      ),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _termStart,
                          firstDate: DateTime(_termStart.year - 2),
                          lastDate: DateTime(_termStart.year + 3),
                        );
                        if (picked != null) {
                          setState(() => _termStart = mondayOf(picked));
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Row(
                      children: [
                        const Text('总周数'),
                        Expanded(
                          child: Slider(
                            value: _totalWeeks.toDouble(),
                            min: 10,
                            max: 30,
                            divisions: 20,
                            label: '$_totalWeeks',
                            onChanged: (v) =>
                                setState(() => _totalWeeks = v.round()),
                          ),
                        ),
                        Text('$_totalWeeks'),
                      ],
                    ),
                  ),
                ],
              ),
              if (imported.warnings.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  '需要注意（${imported.warnings.length}）',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
                const SizedBox(height: 4),
                for (final w in imported.warnings)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text('· $w', style: theme.textTheme.bodySmall),
                  ),
              ],
              const SizedBox(height: 12),
              Text(
                _replaceCurrent
                    ? '导入会覆盖当前课表「${widget.base.name}」的全部课程'
                          '${imported.tasks == null ? '' : '，并替换作业与待办列表'}。'
                    : '导入会创建一张新课表，当前课表不会改变'
                          '${imported.tasks == null ? '' : '；备份中的待办会追加到现有列表'}。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: _replaceCurrent
                      ? theme.colorScheme.error
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _confirm,
          child: Text(_replaceCurrent ? '导入并覆盖' : '导入为新课表'),
        ),
      ],
    );
  }
}

TaskItem _importedTask(
  TaskItem source, {
  required String timetableId,
  required String? sourceTimetableId,
  required bool assignNewId,
}) => TaskItem(
  id: assignNewId ? newId('task') : source.id,
  title: source.title,
  kind: source.kind,
  createdAt: source.createdAt,
  dueAt: source.dueAt,
  reminderAt: source.reminderAt,
  timetableId:
      sourceTimetableId != null && source.timetableId == sourceTimetableId
      ? timetableId
      : source.timetableId,
  courseId: source.courseId,
  note: source.note,
  priority: source.priority,
  completedAt: source.completedAt,
);

const _csvTemplate =
    '课程名称,教师,教室,星期,节次,周次\n'
    '高等数学A,张伟,教三-305,周一,1-2,1-16\n'
    '线性代数,王强,教三-208,周二,1-2,1-16单\n'
    '体育,刘洋,体育馆,周二,3-4,1-16双\n'
    '概率论,周涛,教三-401,周五,1-2,9-16\n';

Future<void> _saveCsvTemplate(BuildContext context) async {
  final toast = _Toast(context);
  try {
    final uri = await FilePicker.saveFile(
      fileName: 'DeskTile课表模板.csv',
      // 带 UTF-8 BOM，Excel 打开中文才不乱码。
      bytes: Uint8List.fromList([
        0xEF,
        0xBB,
        0xBF,
        ...utf8.encode(_csvTemplate),
      ]),
      dialogTitle: '保存 CSV 模板',
      allowedExtensions: const ['csv'],
    );
    if (uri != null) toast.show('模板已保存');
  } catch (e) {
    toast.show('保存失败：$e', error: true);
  }
}

Future<void> _exportBackup(BuildContext context) async {
  final toast = _Toast(context);
  final state = AppScope.read(context);
  try {
    final json = const JsonEncoder.withIndent('  ')
        .convert(state.data.toJson());
    final uri = await FilePicker.saveFile(
      fileName: 'DeskTile备份.json',
      bytes: Uint8List.fromList(utf8.encode(json)),
      dialogTitle: '导出备份',
      allowedExtensions: const ['json'],
    );
    if (uri != null) toast.show('备份已导出');
  } catch (e) {
    toast.show('导出失败：$e', error: true);
  }
}

Future<void> _exportCses(BuildContext context) async {
  final toast = _Toast(context);
  final state = AppScope.read(context);
  final t = state.activeTimetable;
  if (t == null) return;
  CsesExport result;
  try {
    result = exportCses(t);
  } on FormatException catch (e) {
    toast.show('无法导出：${e.message}', error: true);
    return;
  }
  try {
    final uri = await FilePicker.saveFile(
      fileName: '${t.name}.cses.yaml',
      bytes: Uint8List.fromList(utf8.encode(result.yaml)),
      dialogTitle: '导出 CSES',
      allowedExtensions: const ['yaml'],
    );
    if (uri == null) return;
    toast.show(
      result.warnings.isEmpty
          ? '已导出 CSES'
          : '已导出，但有 ${result.warnings.length} 处无法精确表达：${result.warnings.first}',
    );
  } catch (e) {
    toast.show('导出失败：$e', error: true);
  }
}

Future<void> _openDataFolder(BuildContext context) async {
  final toast = _Toast(context);
  final store = AppScope.read(context).store;
  try {
    final dir = await store.directory();
    await dir.create(recursive: true);
    if (Platform.isWindows) {
      await Process.run('explorer', [dir.path]);
    }
  } catch (e) {
    toast.show('打开失败：$e', error: true);
  }
}
