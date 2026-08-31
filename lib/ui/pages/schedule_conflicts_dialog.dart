import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/agenda.dart';
import '../../core/models/time_slot.dart';
import '../../core/schedule_conflict.dart';
import '../../core/week_math.dart';

Future<int?> showScheduleConflictsDialog(
  BuildContext context, {
  required List<ScheduleConflict> conflicts,
}) {
  return showDialog<int>(
    context: context,
    builder: (context) => _ScheduleConflictsDialog(conflicts: conflicts),
  );
}

class _ScheduleConflictsDialog extends StatelessWidget {
  const _ScheduleConflictsDialog({required this.conflicts});

  final List<ScheduleConflict> conflicts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context);
    final contentHeight = math.min(
      72.0 + conflicts.length * 112.0,
      size.height * 0.62,
    );

    return AlertDialog(
      key: const ValueKey('schedule-conflicts-dialog'),
      title: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: theme.colorScheme.error),
          const SizedBox(width: 10),
          const Expanded(child: Text('课表冲突')),
        ],
      ),
      content: SizedBox(
        width: size.width < 600 ? double.maxFinite : 520,
        height: contentHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '共 ${conflicts.length} 处实际课程时间重叠',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                itemCount: conflicts.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final conflict = conflicts[index];
                  return ListTile(
                    key: ValueKey(
                      'schedule-conflict-${conflict.date.millisecondsSinceEpoch}',
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 6),
                    title: Text(
                      '第 ${conflict.week} 周 · '
                      '${conflict.date.month}月${conflict.date.day}日 '
                      '${weekDayName(conflict.date.weekday)}',
                      style: theme.textTheme.titleSmall,
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${formatMinutes(conflict.startMinutes)}-'
                            '${formatMinutes(conflict.endMinutes)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          for (final session in conflict.sessions)
                            Text(
                              _sessionText(session),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).pop(conflict.week),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

String _sessionText(ResolvedSession session) {
  final details = <String>[
    session.course.name,
    session.sectionText,
    if (session.session.room?.isNotEmpty ?? false) session.session.room!,
    switch (session.occurrence) {
      SessionOccurrenceKind.rescheduledTarget => '调课',
      SessionOccurrenceKind.extraClass => '补课',
      _ => '常规',
    },
  ];
  return details.join(' · ');
}
