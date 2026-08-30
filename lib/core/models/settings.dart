/// 提醒模式。
enum ReminderMode {
  /// 只提醒每天第一节课，且要求它开始得足够早（早八提醒）。
  firstClassOfDay,

  /// 每节课都提醒。
  everyClass,
}

/// 桌面挂件形态。
enum WidgetForm {
  /// 标准：今日课程 + 考试倒计时。
  standard,

  /// 迷你：只显示下一节课。
  mini,
}

enum ThemePref { system, light, dark }

class AppSettings {
  const AppSettings({
    this.reminderEnabled = true,
    this.reminderMode = ReminderMode.firstClassOfDay,
    this.leadMinutes = 30,
    this.earlyClassCutoffMinutes = 9 * 60,
    this.taskReminderEnabled = true,
    this.defaultTaskReminderLeadMinutes = 24 * 60,
    this.widgetOpacity = 0.95,
    this.widgetForm = WidgetForm.standard,
    this.widgetAlwaysOnBottom = true,
    this.autoStart = false,
    this.theme = ThemePref.system,
  });

  final bool reminderEnabled;
  final ReminderMode reminderMode;

  /// 提前多少分钟提醒。
  final int leadMinutes;

  /// 「早八」的判定阈值：第一节课开始时间早于这个时刻才提醒。默认 09:00。
  final int earlyClassCutoffMinutes;

  final bool taskReminderEnabled;

  /// 新建事项默认提前多久提醒。当前界面提供提前一天和提前两小时。
  final int defaultTaskReminderLeadMinutes;

  final double widgetOpacity;
  final WidgetForm widgetForm;

  /// true = 贴在桌面上（不遮挡其它窗口）；false = 始终置顶。
  final bool widgetAlwaysOnBottom;

  final bool autoStart;
  final ThemePref theme;

  AppSettings copyWith({
    bool? reminderEnabled,
    ReminderMode? reminderMode,
    int? leadMinutes,
    int? earlyClassCutoffMinutes,
    bool? taskReminderEnabled,
    int? defaultTaskReminderLeadMinutes,
    double? widgetOpacity,
    WidgetForm? widgetForm,
    bool? widgetAlwaysOnBottom,
    bool? autoStart,
    ThemePref? theme,
  }) => AppSettings(
    reminderEnabled: reminderEnabled ?? this.reminderEnabled,
    reminderMode: reminderMode ?? this.reminderMode,
    leadMinutes: leadMinutes ?? this.leadMinutes,
    earlyClassCutoffMinutes:
        earlyClassCutoffMinutes ?? this.earlyClassCutoffMinutes,
    taskReminderEnabled: taskReminderEnabled ?? this.taskReminderEnabled,
    defaultTaskReminderLeadMinutes:
        defaultTaskReminderLeadMinutes ?? this.defaultTaskReminderLeadMinutes,
    widgetOpacity: widgetOpacity ?? this.widgetOpacity,
    widgetForm: widgetForm ?? this.widgetForm,
    widgetAlwaysOnBottom: widgetAlwaysOnBottom ?? this.widgetAlwaysOnBottom,
    autoStart: autoStart ?? this.autoStart,
    theme: theme ?? this.theme,
  );

  Map<String, dynamic> toJson() => {
    'reminderEnabled': reminderEnabled,
    'reminderMode': reminderMode.name,
    'leadMinutes': leadMinutes,
    'earlyClassCutoffMinutes': earlyClassCutoffMinutes,
    'taskReminderEnabled': taskReminderEnabled,
    'defaultTaskReminderLeadMinutes': defaultTaskReminderLeadMinutes,
    'widgetOpacity': widgetOpacity,
    'widgetForm': widgetForm.name,
    'widgetAlwaysOnBottom': widgetAlwaysOnBottom,
    'autoStart': autoStart,
    'theme': theme.name,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
    reminderEnabled: (json['reminderEnabled'] as bool?) ?? true,
    reminderMode: _enumByName(
      ReminderMode.values,
      json['reminderMode'],
      ReminderMode.firstClassOfDay,
    ),
    leadMinutes: (json['leadMinutes'] as int?) ?? 30,
    earlyClassCutoffMinutes:
        (json['earlyClassCutoffMinutes'] as int?) ?? 9 * 60,
    taskReminderEnabled: (json['taskReminderEnabled'] as bool?) ?? true,
    defaultTaskReminderLeadMinutes:
        (json['defaultTaskReminderLeadMinutes'] as int?) ?? 24 * 60,
    widgetOpacity: (json['widgetOpacity'] as num?)?.toDouble() ?? 0.95,
    widgetForm: _enumByName(
      WidgetForm.values,
      json['widgetForm'],
      WidgetForm.standard,
    ),
    widgetAlwaysOnBottom: (json['widgetAlwaysOnBottom'] as bool?) ?? true,
    autoStart: (json['autoStart'] as bool?) ?? false,
    theme: _enumByName(ThemePref.values, json['theme'], ThemePref.system),
  );
}

T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}
