# DeskTile 课表岛 — 项目交接文档

> 交接时间：2026-08-21 · 对应提交：Phase 1（Windows 端）完成
> 代码位置：`D:\CLAUDE\DeskTile`（原中文目录 `D:\CLAUDE\DeskTile课表岛` 未使用，见 §1.2）
> 规模：`lib/` 37 个文件 5399 行，`test/` 10 个文件 1303 行 / 117 个用例

---

## 0. 现状一句话

Windows 端功能完整、构建通过、117 个测试全绿、实机跑过并截图；
Android 端**一行都没写**，但跨平台核心逻辑（周次计算、单双周、提醒计划、导入解析）
已经全部在 `lib/core/` 里做完并被测试覆盖，Android 只需要接原生小组件和闹钟。

---

## 1. 环境

### 1.1 本机已装什么

| 组件 | 版本 / 位置 | 备注 |
|---|---|---|
| Flutter SDK | 3.47.1 stable，`D:\dev\flutter` | Dart 3.13.1；已加入用户 PATH（原 PATH 备份在 `D:\dev\user-path-backup.txt`） |
| VS Build Tools 2022 | 17.14.37，含 MSVC 14.44.35207 + ATL | `flutter doctor` 认它，不需要装完整 Visual Studio |
| Windows SDK | 10.0.26100.0（另有 10.0.19041.0） | 实际文件在 `C:\Program Files (x86)\Windows Kits\10` |
| 开发者模式 | 已开启 | 见 §1.2 第 1 条 |
| Android 工具链 | ❌ 无 JDK、无 Android SDK | 只有 winget 装的 adb 37.0.1，`adb devices` 为空 |

`flutter doctor -v` 只有 Android toolchain 一项报错，Windows / Visual Studio / Network 全部 ✅。

### 1.2 三个必须知道的环境坑

**① 开发者模式（已解决，动过注册表）**

Flutter Windows 带插件构建需要创建符号链接（`windows/flutter/ephemeral/.plugin_symlinks`），
没有开发者模式时 `flutter pub get` 只会警告，构建阶段找不到插件源码。
已通过一次 UAC 提权写入：

```
HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock\AllowDevelopmentWithoutDevLicense = 1
```

在「设置 → 系统 → 开发者选项」里可以随时关掉，但关掉后本项目就构建不了。

**② ATL 组件（已解决，装过东西）**

`flutter_local_notifications_windows` 的 `plugin.cpp` 第一行就 `#include <atlbase.h>`，
而 VS Build Tools 默认不带 ATL。已通过一次 UAC 提权装上：

```bat
"C:\Program Files (x86)\Microsoft Visual Studio\Installer\setup.exe" modify ^
  --installPath "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools" ^
  --add Microsoft.VisualStudio.Component.VC.ATL --passive --norestart
```

**③ Windows SDK 注册表坏了（未修复，用脚本绕开）**

这台机器上两个注册表视图指向不同位置：

| 视图 | 键 | 值 |
|---|---|---|
| 32 位（WOW6432Node） | `HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows Kits\Installed Roots\KitsRoot10` | `C:\Program Files (x86)\Windows Kits\10\` ← 真正的 SDK |
| 64 位（原生） | `HKLM\SOFTWARE\Microsoft\Windows Kits\Installed Roots\KitsRoot10` | `C:\Program Files\Windows Kits\10\` ← **只有 App Certification Kit，没有 Include/Lib** |

CMake 调用的是 **64 位** MSBuild，于是 `$(UCRTContentRoot)` 落到那个空目录，
`LibraryPath` 里的 ucrt 路径不存在，链接直接报：

```
LINK : fatal error LNK1104: 无法打开文件"ucrtd.lib"
```

诊断过程记录：32 位 MSBuild 手动构建同一个 vcxproj **能过**，64 位的不过；
`-getProperty:LibraryPath` 对比确认差异就在 ucrt 那一段。

解决办法是覆盖一个环境变量，**没有改注册表**，全部封装在 `tool/flutter-msvc.bat` 里：

```bat
set "UCRTContentRoot=C:\Program Files (x86)\Windows Kits\10\"
```

> **在这台机器上一律用 `tool\flutter-msvc.bat` 代替 `flutter`。**
> 直接跑 `flutter build windows` 一定失败，而且报错信息完全指不到根因。
> 如果换机器或者哪天把 64 位视图的 `KitsRoot10` 改对了，这个包装脚本就可以删掉。

顺带两条：`.bat` 文件必须保持纯 ASCII（本机控制台是 GBK 代码页，UTF-8 中文注释会让 cmd 解析炸掉）；
`tool/flutter-msvc.bat` 里硬编码了 `D:\dev\flutter\bin`，Flutter 换位置要改这里。

### 1.3 常用命令

```bash
tool/flutter-msvc.bat analyze                  # 静态检查，目前 0 问题
tool/flutter-msvc.bat test                     # 全部 117 个测试
tool/flutter-msvc.bat test test/ui_test.dart   # 只跑界面测试
tool/flutter-msvc.bat run -d windows           # 调试运行（主窗口模式）
tool/flutter-msvc.bat build windows --release  # 出包
```

产物：`build\windows\x64\runner\Release\desktile.exe`（整个 Release 目录一起拷才能跑，
Dart 代码在 `data\app.so`，插件 DLL 和 `data\flutter_assets\` 都要带上）。

灌示例数据（用的是真实的导入代码，不是手写 JSON）：

```bash
dart run tool/seed_demo_data.dart                  # 示例课表，本周 = 第 1 周
dart run tool/seed_demo_data.dart --weeks-back 1   # 本周 = 第 2 周，用来看双周
dart run tool/seed_demo_data.dart --reminder-test  # 造一节 4 分钟后开始的课，验证提醒
dart run tool/seed_demo_data.dart --export-cses out.yaml
```

> `dart` 在 PATH 里（`D:\dev\flutter\bin`）；从 Python/脚本里调用要用绝对路径
> `D:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe`，因为 `dart` 本身是 `.bat`。

### 1.4 网络

**不要设 Flutter 国内镜像。** 实测：

| 源 | 结果 |
|---|---|
| `storage.googleapis.com/flutter_infra_release` | HTTP 200，0.75s |
| `pub.dev` | HTTP 200，0.88s |
| `mirrors.tuna.tsinghua.edu.cn/flutter` | **HTTP 403** |
| `mirrors.tuna.tsinghua.edu.cn/dart-pub` | **HTTP 403** |

清华镜像已经不可用，官方源直连反而更快。所以 `FLUTTER_STORAGE_BASE_URL` /
`PUB_HOSTED_URL` 都没有设置，也别去设。

（另：SDK zip 有 1.79GB，第一次下载被服务器中断过一次，用 `curl -C -` 续传补齐后
`Content-Length` 完全吻合。以后重下记得带 `-C -`。）

---

## 2. 产品范围

### 2.1 已实现（Windows）

- **周视图**：左侧节次时间轴（节次号 + 起止时刻），上方周一~周日（可隐藏周末），
  今天所在列高亮；课程块按课名的稳定哈希取色，跨节次的课竖向合并成一块
- **切周**：`‹ 第 N 周 · 单/双周 ›` + 「回到本周」；学期外自动落到第 1 周或最后一周
- **单双周**：见 §6.1
- **课程编辑**：点空格新增、点课程块编辑；周次选择支持「每周 / 单周 / 双周」快捷 chip
  加自由输入（`1-16`、`1-16单`、`1-8,10,12-16`），实时显示解析结果和「本周是否上」
- **节次时间表**：可增删改每一节的起止时间，可一键恢复默认 12 节
- **桌面挂件**：见 §6.3
- **早八教室提醒**：见 §6.2
- **考试倒计时**：科目 / 日期 / 开考-结束 / 考场 / 座位 / 备注；按开考时间升序，
  3 天内变红，考完的收进「已结束（N）」折叠区
- **导入**：CSV、CSES v2 YAML、ICS、小爱课程表 JSON，见 §6.4
- **导出**：CSES v2 YAML、完整备份 JSON、CSV 模板（带 UTF-8 BOM，Excel 打开不乱码）
- **开机自启**：写 `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`，
  值是 `"<exe>" --widget`，不需要管理员权限
- **主题**：跟随系统 / 浅色 / 深色

### 2.2 明确不做（当时和需求方确认过的）

账号系统、云同步、广告位、课程社区。也没有引入 SQLite、状态管理库、多窗口插件，
理由见 §3.2。

### 2.3 未实现

| 项 | 状态 |
|---|---|
| Android 端（含 Glance 桌面小组件、精准闹钟） | Phase 2，见 §10。核心逻辑已就绪 |
| 教务系统直连（登录 + 抓课表） | Phase 3，见 §11。解析通路已预留 |
| 多张课表切换 | 数据结构支持（`timetables` 是数组、有 `activeTimetableId`），界面没做入口 |
| 课程冲突提示 | `CourseSession.overlaps()` 已实现且可用，界面没接 |

---

## 3. 架构

### 3.1 分层

```
                  ┌──────────────────────────────────────────┐
  desktile.exe    │ ui/app.dart      主窗口（唯一写入方）      │
   （无参数）      │  ├─ timetable_page   周视图 + 切周         │
                  │  ├─ session_editor   课程编辑弹窗          │
                  │  ├─ exams_page       考试倒计时            │
                  │  ├─ import_export    导入预览 / 导出        │
                  │  └─ settings_page    学期/节次/提醒/挂件    │
                  └──────────────────────────────────────────┘
                                    │ 写
                        desktile_data.json
                                    │ 读 + Directory.watch
                  ┌──────────────────────────────────────────┐
  desktile.exe    │ ui/widget_app.dart  桌面挂件（只读）       │
   --widget       │ platform/tray.dart  托盘菜单               │
   （常驻）        │ platform/notifications  提醒调度（主责）    │
                  └──────────────────────────────────────────┘

  两个进程共用：
    core/    纯 Dart 领域层，不 import flutter，测试全覆盖
    data/    AppData（纯数据）· DataStore（原子读写 + 监听）· AppState（ChangeNotifier）
    platform/ 窗口 · 托盘 · 通知 · 自启 · 单实例
```

### 3.2 六个关键决策与理由

**① 挂件和主窗口是两个进程，不是两个窗口**

Flutter stable 3.47 不支持多窗口（要 main 通道 + `flutter config --enable-windowing`）。
社区插件 `desktop_multi_window` 在子窗口里插件基本用不了，风险更高。
所以同一个 exe 用 `--widget` 参数分流，靠文件同步。代价是两个进程各占约 120MB 内存。

**② 主窗口独占写，挂件只读**

从设计上消除跨进程写冲突（`AppState.readOnly` + `_mutate` 里的 assert）。
两个例外用专门的窄接口处理：
- 挂件位置存**另一个文件** `widget_pos.json`（`data/widget_position.dart`）
- 托盘切换迷你模式/贴桌面走 `AppState.mutateSettingsSafely()`，它会**先重读磁盘**
  再只替换 settings 写回，不会把主窗口刚保存的课表编辑整份覆盖掉

**③ 单 JSON 文件，不用 SQLite**

课表数据只有几百行；`sqlite3_flutter_libs` 已经是 `0.6.0+eol`；
单文件让备份/跨端搬运变成拷一个文件，也让挂件能直接 `Directory.watch`。

**④ 没有状态管理库**

`AppState extends ChangeNotifier` + `AppScope extends InheritedNotifier<AppState>`
（`data/app_state.dart` 末尾）+ `ListenableBuilder`。整个应用只有一份状态，
Riverpod/Provider 在这个规模下只是多一层概念。

取用方式：
- `AppScope.of(context)` — 订阅变化（build 里用）
- `AppScope.read(context)` — 只取不订阅（回调里用）

**⑤ 挂件用「不透明卡片 + 窗口整体透明度」，不用真透明背景**

Flutter Windows 的透明窗口有已知的发黑问题。现在的做法是
`setAsFrameless()` + 圆角 `Card` + `windowManager.setOpacity(0.3~1.0)`，
效果稳定。想试真透明的话入口在 `platform/desktop_window.dart`。

**⑥ 通知 id 是决定性的**

`reminder_plan.dart` 的 `reminderId(date, sessionId)` 用自己实现的
`stableHash`（不用 `String.hashCode`，它不保证跨进程稳定）。
配合「每次重排先 `cancelAll` 再全量写入」，两个进程同时排也不会产生重复通知。

---

## 4. 文件职责

### `lib/core/` — 纯 Dart，不依赖 Flutter

| 文件 | 行 | 职责 |
|---|---|---|
| `models/time_slot.dart` | 78 | `TimeSlot`（第几节 + 起止「当日分钟数」）、`parseMinutes`/`formatMinutes`、`kDefaultTimeSlots`（大学常见 12 节） |
| `models/course.dart` | 128 | `Course`（课程本身）、`CourseSession`（星期 + 起止节次 + **周次集合** + 教室），含 `overlaps()` |
| `models/timetable.dart` | 101 | `Timetable`；构造时把 `termStart` **自动对齐到周一** |
| `models/exam.dart` | 60 | `Exam` |
| `models/settings.dart` | 109 | `AppSettings` + `ReminderMode` / `WidgetForm` / `ThemePref` |
| `week_math.dart` | 69 | 周次换算。跨天计算统一归一化到 UTC 午夜再相减，避免时区/夏令时少算一天 |
| `weeks_parser.dart` | 132 | 周次串解析与格式化，见 §6.1 |
| `stable_hash.dart` | 12 | 跨进程稳定的字符串哈希（31 位内，Android 通知 id 要求 32 位 int） |
| `agenda.dart` | 112 | `ResolvedSession`、`sessionsOnWeekDay`、`agendaForDate`、`currentSession`、`nextSession`、`remainingToday` |
| `reminder_plan.dart` | 92 | `buildReminders()` → `PlannedReminder` 列表，见 §6.2 |
| `exam_countdown.dart` | 59 | `upcomingExams` / `pastExams` / `formatRemaining` |

### `lib/core/import/` — 所有格式先转成同一个中间结构

| 文件 | 行 | 职责 |
|---|---|---|
| `course_info_dto.dart` | 210 | **枢纽**。`CourseInfoDto` 字段与小爱课程表 `courseInfos` 一一对应；`ImportedSchedule`（课程 + 警告 + 可选元信息）；`mergeCourseInfos()` 合并同星期同课同周次的记录；`buildTimetable()` 把 DTO 装配成 `Timetable`（同名同教师合并成一门课、连续节次压成一个时段、非法数据进警告不中断） |
| `field_parsers.dart` | 40 | `parseWeekDay`（认 `1..7`/`周三`/`星期三`/`Wed`）、`parseSections` |
| `csv_importer.dart` | 120 | CSV，表头别名匹配，缺列给可读错误，坏行进警告 |
| `cses_importer.dart` | 210 | CSES v2 YAML，含「工作日循环 → 星期几 + 单双周」的还原算法 |
| `ics_importer.dart` | 119 | ICS，推算学期起点和节次时间表 |
| `json_importer.dart` | 83 | 小爱课程表 `courseInfos` / 自有备份 |
| `exporter.dart` | 156 | 导出 CSES v2 YAML（手写 YAML，无额外依赖），无法表达的时段进 warnings |

### `lib/data/`

| 文件 | 行 | 职责 |
|---|---|---|
| `app_data.dart` | 80 | `AppData`（全部应用数据）+ `toJson`/`fromJson`/`initial`。**刻意不依赖 Flutter 和 path_provider**，所以 `tool/seed_demo_data.dart` 这种纯 Dart 脚本能直接读写 |
| `store.dart` | 88 | `DataStore`：定位目录、原子写（tmp + rename）、损坏兜底（备份成 `.broken`）、`watch()` 文件监听（300ms 防抖）；`newId()` |
| `app_state.dart` | 148 | `AppState`（ChangeNotifier）+ `AppScope`（InheritedNotifier）。写入方法：`updateSettings` / `setActiveTimetableId` / `updateActiveTimetable` / `putTimetable` / `deleteTimetable` / `putExam` / `deleteExam` / `mutateSettingsSafely` |
| `widget_position.dart` | 47 | 挂件位置单独存 `widget_pos.json` |

### `lib/platform/` — 全部 Windows 相关

| 文件 | 行 | 职责 |
|---|---|---|
| `desktop_window.dart` | 87 | `isWidgetMode(args)`、`setupMainWindow()`、`setupWidgetWindow()`、`applyWidgetAppearance()`、`defaultWidgetPosition()`（贴主屏右下角）、两种挂件尺寸常量 |
| `tray.dart` | 121 | 托盘图标与菜单（显示/隐藏挂件、迷你模式、贴桌面、打开主窗口、开机自启、退出）；左键点图标显示挂件、右键弹菜单 |
| `notifications.dart` | 160 | `ReminderService`：初始化（含在 `HKCU\Software\Classes\AppUserModelId` 下登记 AUMID）、`reschedule()`、`scheduleTest()`、`pendingCount()` |
| `autostart.dart` | 29 | 读写 `Run` 键 |
| `windows_registry.dart` | 50 | 直接调 `reg.exe` 的极简封装。**没用 `win32_registry`**，因为它依赖的 win32 版本和 `file_picker 12` 冲突 |
| `single_instance.dart` | 95 | 绑定回环端口当互斥锁（挂件 45677 / 主窗口 45678），兼作「唤起已有窗口」的 IPC；`ModeLauncher` 启动另一种模式的进程 |

### `lib/ui/`

| 文件 | 行 | 职责 |
|---|---|---|
| `theme.dart` | 57 | M3 主题、10 色课程配色板、`courseColor(seed)`、日期/时刻格式化 |
| `app.dart` | 98 | 主窗口壳（NavigationRail 四个页面） |
| `pages/timetable_page.dart` | 429 | 周视图：`_Toolbar` / `_Grid`（表头固定，只纵向滚动）/ `_TimeColumn` / `_DayColumn`（Stack + Positioned 放课程块）/ `_CourseBlock`（按可用高度决定显示到教室还是教师） |
| `pages/session_editor.dart` | 337 | 课程时段编辑弹窗；保存时同名同教师复用 Course，并清理没有时段的孤儿课程 |
| `pages/exams_page.dart` | 321 | 考试列表 + 编辑弹窗 |
| `pages/import_export_page.dart` | 442 | 格式说明、选文件导入、`showImportPreview()`（公开出来是为了能测）、三个导出动作 |
| `pages/settings_page.dart` | 409 | 学期 / 节次时间表 / 提醒 / 挂件 / 启动与外观五组设置 |
| `widget_app.dart` | 380 | 挂件：`_WidgetSurface`（拖动 + 位置保存 + 20s 刷新计时器）、`_Header`、`_NextUp`、`_TodayList`、`_ExamLine` |
| `main.dart` | 131 | 按 `--widget` 分流；两种模式各自的启动序列；挂件里的每日 00:05 重排 |

---

## 5. 数据

### 5.1 模型关系

```
AppData
 ├─ activeTimetableId
 ├─ timetables: [Timetable]
 │                ├─ termStart（第一周的周一，构造时自动对齐）
 │                ├─ totalWeeks / showWeekend
 │                ├─ timeSlots: [TimeSlot]     第几节 → 起止时刻
 │                ├─ courses:   [Course]       课名 / 教师 / 配色种子
 │                └─ sessions:  [CourseSession] 星期 + 起止节次 + 周次集合 + 教室
 ├─ exams: [Exam]
 └─ settings: AppSettings
```

一门课多个时段共用一个 `Course`；`CourseSession.courseId` 指向它。
**单双周不是独立字段**，就是 `weeks` 集合的一种形态。

### 5.2 磁盘格式

位置：`%APPDATA%\com.desktile\desktile\desktile_data.json`
（`getApplicationSupportDirectory()`；`com.desktile\desktile` 来自 `windows/runner/Runner.rc`
的 CompanyName / ProductName，改它会换数据目录）

```json
{
  "schemaVersion": 1,
  "activeTimetableId": "t1",
  "timetables": [{
    "id": "t1", "name": "2026 秋季学期",
    "termStart": "2026-08-17", "totalWeeks": 16, "showWeekend": true,
    "timeSlots": [{"index": 1, "start": "08:00", "end": "08:45"}],
    "courses":   [{"id": "c1214213202", "name": "高等数学A", "teacher": "张伟",
                   "colorSeed": 1553760393}],
    "sessions":  [{"id": "s1948299589", "courseId": "c1216448261", "day": 2,
                   "startSection": 1, "endSection": 2,
                   "weeks": [1,3,5,7,9,11,13,15], "room": "教三-208"}]
  }],
  "exams": [{"id": "e1", "name": "高等数学A 期末",
             "startAt": "2026-09-02T09:00:00.000", "endAt": "...",
             "room": "教三-305", "seat": "18"}],
  "settings": {"reminderEnabled": true, "reminderMode": "firstClassOfDay",
               "leadMinutes": 30, "earlyClassCutoffMinutes": 540,
               "widgetOpacity": 0.95, "widgetForm": "standard",
               "widgetAlwaysOnBottom": true, "autoStart": false, "theme": "system"}
}
```

另一个文件 `widget_pos.json`：`{"x": 1993.0, "y": 857.0}`（物理像素，挂件位置）。

**迁移策略**：顶层 `schemaVersion` 目前是 1。加字段直接在 `fromJson` 里给默认值即可
（现有代码全部这么写的）；真要破坏性改动就在 `DataStore.load()` 里按 `schemaVersion` 分支。
解析抛异常时会把坏文件改名成 `.broken` 并回到初始数据，**不会让程序起不来**。

---

## 6. 关键功能怎么实现的

### 6.1 周次与单双周

`week_math.dart` 的约定：`termStart` 是**第一周周一**，`Timetable` 构造时用 `mondayOf()`
强制对齐，所以用户在设置里选哪天都不会算错。所有「相差多少天」都走 `daysBetween()`，
它先把两个日期归一化到 `DateTime.utc(y,m,d)` 再相减 —— 直接用本地 `DateTime.difference().inDays`
在夏令时切换那天会少算一天。

`currentWeek()` 学期外返回 `null`（界面显示「不在学期内」），`clampedWeek()`
夹到 `[1, totalWeeks]`（界面默认展示用）。

`weeks_parser.dart` 的 `parseWeeks(input, totalWeeks:)`：

1. 归一化：全角数字 `０-９` → ASCII；`，、；/` → `,`；`－–—~～至到` → `-`
2. 检测「单/奇」「双/偶」；两个字都出现时视为不过滤（`单双周` = 每周）
3. 剥掉除数字/逗号/连字符外的一切（于是 `第1-8周`、`1-16单` 都能认）
4. 展开区间（写反了也认，`9-5` = `5-9`）
5. 裁到 `[1, totalWeeks]`，再按奇偶过滤

语义对齐小爱课程表社区解析器的 `weekStr2IntList` / `getWeeks`，将来接 Phase 3 不用改。
反向的 `formatWeeks()` 会把集合压回 `每周` / `单周` / `双周` / `1-3,5,7-8周`，
并且和 `parseWeeks` 往返一致（有测试）。

### 6.2 早八提醒

纯函数 `buildReminders({timetable, settings, from, daysAhead})` 产出
`PlannedReminder(id, fireAt, title, body)` 列表：

- `firstClassOfDay` 模式：每天只取第一节，且要求它的开始时间 **早于**
  `earlyClassCutoffMinutes`（默认 540 = 09:00）。这就是「早八」的定义。
  把阈值拉到 24:00 就等于「每天第一节都提醒」。
- `everyClass` 模式：当天每节课都排。
- `fireAt = 上课时刻 - leadMinutes`，已经过去的直接跳过。
- **正文一定带教室**：`08:00 上课 · 第1-2节 · 教三-305 · 张伟`。
  「早八不知道在哪间教室」是这个功能存在的理由，所以 room 不是可选装饰。
- id 由 `stableHash('年-月-日|sessionId')` 得出，决定性。

`platform/notifications.dart` 负责落地：滚动排未来 7 天，触发点是
①应用启动 ②数据/设置变更（挂件监听到）③每天 00:05（`main.dart` 的 `_armDailyRefresh`）。
每次都先 `cancelAll()` 再全量写入。

Windows 侧两个细节：
- 未打包的 Win32 程序要让 Toast 显示正确的应用名和图标，得在
  `HKCU\Software\Classes\AppUserModelId\DeskTile.KeBiaoDao.Desktop` 下写
  `DisplayName` 和 `IconUri`，`init()` 里自动做了，纯用户级。
- 传给 `zonedSchedule` 的时刻用 `tz.TZDateTime.from(fireAt, tz.UTC)`。
  这是刻意的：Windows 插件只读 `millisecondsSinceEpoch`，用 UTC 表示同一瞬间完全等价，
  能省掉查系统 IANA 时区名这一大堆麻烦。**接 Android 时必须改成真正的本地时区**
  （代码里有注释标记）。

### 6.3 桌面挂件与双进程

启动序列（`main.dart` → `_runWidget`）：

1. 抢 45677 端口 —— 抢不到说明已有挂件在跑，已经把它叫到前面了，`exit(0)`
2. `AppState(readOnly: true)` + `load()`
3. `setupWidgetWindow()`：`setAsFrameless` / `setResizable(false)` /
   `setSkipTaskbar(true)` / 恢复上次位置（没有就贴主屏右下角）/
   `setAlwaysOnBottom` / `setOpacity`
4. `state.startWatching()` 开始监听数据文件
5. 初始化通知并排一次
6. 注册 listener：设置变了就 `applyWidgetAppearance()` 并重排提醒
7. `_armDailyRefresh()` 每天 00:05 重排
8. 初始化托盘
9. `runApp(WidgetApp(...))`

交互：整个卡片 `onPanStart → windowManager.startDragging()`；
`onWindowMoved` 里把位置写进 `widget_pos.json`；右上角小图标打开主窗口。
倒计时用 20 秒一次的 `Timer.periodic` 刷新（够用且不费电）。

「贴在桌面上」= `setAlwaysOnBottom(true)`：在壁纸之上、其它窗口之下。
关掉这个开关会变成 `setAlwaysOnTop(true)` 始终置顶。

### 6.4 导入

四种格式统一先转成 `List<CourseInfoDto>`，再由 `buildTimetable()` 装配。
**导入是整表覆盖**当前课表，确认前 `showImportPreview()` 会显示解析到多少门课、
多少个时段、全部警告，并允许调整学期第一周和总周数。

| 格式 | 关键点 |
|---|---|
| CSV | 表头别名匹配（`课程名称/课程名/课程/name/course` 等）；节次可以写成一列 `1-2`，也可以 `开始节次`+`结束节次` 两列；缺必需列时报出「缺哪几列 + 实际表头」；单行解析失败进 warnings 不中断整份导入 |
| CSES v2 | 它用 `enable_day`（循环中的第几个**工作日**）定位课程，不是星期几。`_resolveCycle()` 走一遍 `cycle.spans` 把工作日序号还原成 (星期几, 第几个循环周)：循环长度必须是整数周，1 周 → 每周，2 周 → 单/双周，**3 周以上明确抛异常**而不是悄悄算错。CSES 没有节次概念，节次时间表由文件里出现过的所有 `(start_time, end_time)` 排序推出。`enable_day: [1, 6]`（两个循环周的周一）会在合并阶段还原成「每周」 |
| ICS | 面向「每次课一条 VEVENT」的导出。学期第一周周一 = `mondayOf(最早事件)`；总周数按最晚事件推；节次时间表同样由时间段推算（会给一条警告说明一段可能对应现实的连续两节）；带 `RRULE` 的不展开，给警告 |
| JSON | 顶层可以是 `{"courseInfos":[...]}` 或直接是数组；`sections` 支持 `[{"section":1}]` 和 `[1]` 两种写法；可选的 `sectionTimes` 会变成节次时间表。这也是本程序备份文件的读入口 |

### 6.5 导出

- **备份 JSON**：`AppData.toJson()` 原样吐出，跨设备搬运用。
- **CSES YAML**：`exporter.dart` 手写 YAML（不引 YAML 写库）。因为 CSES 的
  `work_count`/`rest_count` 都要求 ≥ 2，映射规则是：周一~周五有课 → 工作 5 休息 2；
  周六也有课 → 工作 6 休息 1（为满足 `rest_count>=2` 写成两周循环）；
  **有周日的课直接拒绝导出并说明原因**。周次既不是每周也不是单/双周的时段会被跳过，
  每一条都进 warnings 并在界面上提示。导出结果已用官方 `cses.schema.json` 校验通过。

---

## 7. 测试

### 7.1 清单（117 个用例）

| 文件 | 用例 | 覆盖什么 |
|---|---|---|
| `week_math_test.dart` | 12 | 周次换算、`dateOfWeekDay`↔`weekDayOfDate` 互逆、`mondayOf`、跨时刻 `daysBetween`、构造时对齐周一 |
| `weeks_parser_test.dart` | 23 | 各种周次写法（全角逗号、波浪号、`第..周`、单/双、区间写反、越界裁剪、`单双周`）、`formatWeeks` 往返、`compressRanges`、`parseWeekDay`、`parseSections` |
| `agenda_test.dart` | 12 | 某周某天的课与排序、单周课只在奇数周、上课中/课间/跨天找下一节、今日剩余、学期外 |
| `reminder_plan_test.dart` | 12 | 早八只取第一节、正文含教室、第一节太晚不提醒、阈值拉到 24:00、过去时刻不排、单周课第 2 周无提醒、整周排序、关开关、每节课模式、通知 id 决定性与 32 位范围 |
| `exam_countdown_test.dart` | 15 | 排序与过滤、正在考、`examEndAt` 默认 2 小时、`formatRemaining` 各档 |
| `import_test.dart` | 17 | CSV（9 行全过、中英文星期、单双周、节次区间、部分周次、装配后同名课合并、缺列报错、坏行进警告）、JSON（两种 sections 写法、sectionTimes、裸数组、DTO 往返）、ICS（学期起点推算、多次事件归并、节次推算） |
| `cses_test.dart` | 13 | CSES 导入（配置名、节次推算、两循环周合并成每周、单周、非整数周报错、3 周循环报错）+ 导出（两周循环、单双周分表、subjects 带教师教室、**导出再导入一致**、无法表达的跳过、周日拒绝导出） |
| `store_test.dart` | 7 | 首次运行初始数据、存取往返不丢、不留 `.tmp`、损坏备份兜底、顶层非对象兜底、`schemaVersion`、`newId` 不重复 |
| `ui_test.dart` | 6 | 周视图渲染、**切周后单周课消失/每周课保留**、考试页（倒计时/考场/座位/已结束折叠）、挂件标准与迷你形态、导入预览确认后落盘 |

`docs/示例课表.csv` 和 `docs/示例课表.cses.yaml` 既是用户模板也是测试 fixture，
改动它们会影响 `import_test` / `cses_test` 的断言。

### 7.2 两个必须知道的测试陷阱

**① `testWidgets` 里的真实文件 IO 必须包在 `tester.runAsync()` 里**

`testWidgets` 跑在 fake async 区，真实 IO 的 Future 永远不会完成 —— 表现是测试挂死
10 分钟后超时，**没有任何错误信息**。`ui_test.dart` 的 `_makeState()` 就是这么写的。
（这个坑第一次写界面测试时踩了，花了不少时间才定位。）

**② 测试字体的行高和真机不同**

`flutter test` 用的占位字体行高更大，`Column` 里塞三行文字在真机上刚好、在测试里溢出。
`_TimeColumn`、`_HeaderRow` 用 `FittedBox(fit: BoxFit.scaleDown)` 兜底，
`_CourseBlock` 用 `LayoutBuilder` 按可用高度决定显示到哪一层。
这不只是为了测试 —— 用户把系统字体缩放调大时同样会触发。

---

## 8. 验证记录

已实测通过：

| 项 | 怎么验的 | 结果 |
|---|---|---|
| 静态检查 | `flutter analyze` | 0 问题（含 lint info） |
| 单元/界面测试 | `flutter test` | 117/117 通过 |
| Release 构建 | `build windows --release` | 成功，`desktile.exe` + `data\app.so` |
| 主窗口渲染 | 灌示例数据后实机运行，`PrintWindow` 抓窗口 | 见 `docs/screenshots/主窗口-周视图.png` |
| 挂件渲染 | 同上 | 见 `docs/screenshots/桌面挂件.png` |
| 单双周（第 1 周） | 实机 + 界面测试 | 周二 1-2 节是线性代数（单周） |
| 单双周（第 2 周） | `--weeks-back 1` 重新灌数据后实机 | 线性代数消失、体育（双周）出现，见 `docs/screenshots/主窗口-第2周双周.png` |
| 提醒排定 | 示例课表启动日志 | 「已排定 2 条」＝周一、周四的 08:00 第一节（其余日子第一节晚于 09:00，符合早八规则） |
| 提醒被系统接收 | `pendingNotificationRequests()` | 「系统里待触发 2 条」 |
| 跨进程同步 | 外部改写 JSON 里的课名，前后各抓一次挂件窗口对比 | ~1 秒内挂件文字跟着变，见 `docs/screenshots/跨进程同步-前后对比.png`（上=改前，下=改后） |
| CSES 导出正确性 | 导出后用官方 `cses.schema.json`（draft-07）+ `jsonschema` 校验 | PASS；`docs/示例课表.cses.yaml` 也 PASS |
| CSES 往返 | `cses_test.dart` | 导出再导入，星期/周次/节次数量一致 |

**未能实测的两项**：

1. **Windows Toast 的视觉弹出**。排定和系统接收都验证了，也做过一轮「造一节 4 分钟后
   开始的课 + 提前 3 分钟 → 围绕触发时刻连拍右下角」的尝试，但当时桌面有全屏程序在前台，
   Windows 会自动抑制通知，所以没截到弹窗。
   **接手后请在设置页点一下「10 秒后测试提醒」自行确认**（非全屏状态下）。
   如果不弹，排查顺序见 §12。
2. **选文件的原生对话框**（`FilePicker.pickFile`）。它后面的解析 → 预览 → 覆盖落盘
   全链路有测试覆盖（`showImportPreview` 就是为此特意公开出来的），只有弹窗本身没测。

---

## 9. 已知限制与坑

- **挂件和主窗口不能同时显示同一份"实时"编辑**：主窗口保存后挂件约 1 秒后刷新（300ms 防抖 + 重读）。不是 bug，是双进程方案的固有延迟。
- **两个进程各占约 120MB 内存**，都开着约 240MB。Flutter 桌面的常态。
- **挂件是 `alwaysOnBottom`**，所以任何全屏程序都会盖住它 —— 这是「贴桌面」的设计意图，不是故障。
- **提醒依赖挂件进程常驻**（或主窗口开着）。Windows 计划 Toast 由系统触发，但排定动作需要应用跑一次；所以「开机自启挂件」这个开关对提醒的可靠性很关键。
- **CSES 表达能力有限**：周日的课导不出去，非每周/单双周的周次会被跳过。这是格式本身的限制，代码里已经明确报错/警告而不是静默错。
- **ICS 的节次是推算的**，一段可能对应现实里连续两节；导入后建议去设置里核对节次时间表。
- **`docs/` 下的示例文件同时是测试 fixture**，改了要同步改断言。
- **`tool/*.bat` 必须纯 ASCII**（GBK 控制台会把 UTF-8 中文注释解析炸）。
- **`Runner.rc` 里的 CompanyName/ProductName 决定数据目录**，改了等于换存档位置。
- `windows/flutter/ephemeral/.plugin_symlinks` 是构建产物，删了跑一次 `pub get` 会重建（前提是开发者模式开着）。

---

## 10. Phase 2：Android 落地步骤

工程里 `android/` 目录在 `flutter create` 时已经生成好了，不用重建。

**① 装工具链**

```bat
winget install Microsoft.OpenJDK.17
```

再装 Android SDK cmdline-tools（winget 里有 `Google.AndroidCLI`，或从
developer.android.com 下 command-line tools），然后：

```bash
sdkmanager "platform-tools" "platforms;android-36" "build-tools;36.0.0"
flutter config --android-sdk <SDK 路径>
flutter doctor --android-licenses
```

**需要一台开启 USB 调试的安卓真机，或者同意创建模拟器** —— 现在 `adb devices` 是空的。

**② 加依赖**

`home_widget: ^0.9.3`（当时核对过：要求 Flutter ≥ 3.38.1，与 3.47.1 兼容）。
Android 侧 Gradle 里加 Jetpack Glance 依赖。

**③ 桌面小组件**

- Kotlin 写 `GlanceAppWidgetReceiver` + `GlanceAppWidget`，在
  `android/app/src/main/AndroidManifest.xml` 注册 receiver 和 `appwidget-provider` 元数据
- Dart 侧把挂件需要的信息压成一个紧凑 payload（第几周/星期/下一节课名+教室+时刻/今日剩余/最近考试），
  用 `HomeWidget.saveWidgetData` 写入，再 `HomeWidget.updateWidget`
- **建议新建 `lib/core/widget_payload.dart`**：从 `agenda.dart` + `exam_countdown.dart`
  组装那个 payload，纯函数、可测试。Windows 挂件目前是直接在 UI 里取数的，
  Android 需要一份序列化结构，这一层抽出来两端都能用
- 跨日刷新用 WorkManager（或 `AlarmManager` 定在每天 00:05，和桌面端的重排时机对齐）

**④ 提醒**

`flutter_local_notifications` 已经在依赖里，Android 侧要做的：

- `zonedSchedule` 的 `androidScheduleMode` 用 `exactAllowWhileIdle`（代码里已经这么传了）
- **把 `platform/notifications.dart` 里的 `tz.TZDateTime.from(fireAt, tz.UTC)` 换成真正的本地时区**。
  Windows 只看绝对时间戳所以 UTC 没问题，Android 的精准闹钟要本地时区。
  加 `flutter_timezone` 取 IANA 名，`tz.setLocalLocation(tz.getLocation(name))`
- 权限：`POST_NOTIFICATIONS`（运行时申请）、`SCHEDULE_EXACT_ALARM` / `USE_EXACT_ALARM`、
  `RECEIVE_BOOT_COMPLETED` + 插件自带的开机重排 receiver
- **界面里要引导用户加自启动白名单**。国产 ROM 杀后台是这类 App 提醒失效的头号原因，
  不做引导的话用户只会觉得「提醒不准」

**⑤ 数据搬运**

已有的「导出备份 JSON / 导入 JSON」就是跨端通路，Android 端直接复用
`json_importer.dart`（它认自有备份格式）。

**⑥ 平台判断**

`platform/` 下的文件目前全是 Windows 实现，`desktop_window.dart` 里有
`supportsDesktopWidget`（`Platform.isWindows`）可以作为分流点。
`windows_registry.dart` / `autostart.dart` / `tray.dart` / `single_instance.dart`
在 Android 上不该被调用 —— 加 Android 时要在 `main.dart` 里按平台分流启动序列。

---

## 11. Phase 3：教务系统直连

**不要去写「登录 + 抓包 + 每个学校一个爬虫」**，维护成本会失控。
中国高校这块已经有现成的生态，直接复用：小爱课程表（AISchedule）的解析器约定。

约定就两个纯 JS 函数：

```js
// 在教务系统页面上下文里执行，把（可能嵌在 iframe/frame 里的）课表 HTML 抓出来
function scheduleHtmlProvider(iframeContent = "", frameContent = "", dom = document) { ... }

// 纯函数，HTML -> JSON
function scheduleHtmlParser(html) {
  return { courseInfos: [
    { name, teacher, position, day, weeks: [1,2,3], sections: [{section:1},{section:2}] }
  ]};
}
```

GitHub 上有大量按这个约定写好的各校解析器（正方新旧版、强智、URP、金智……）。

落地路线：

1. 内嵌 WebView（Android 用 `webview_flutter`；Windows 端可以先只做「粘贴 HTML」
   或「粘贴解析器输出的 JSON」兜底）让用户自己登录教务系统 —— **不碰用户密码**
2. 用户到达课表页后，注入选定学校的 `Provider` + `Parser` 并 `runJavaScript` 取回 JSON
3. 拿到的 `{courseInfos: [...]}` **原样丢给已经写好的 `importCourseInfosJson()`**
   （`lib/core/import/json_importer.dart`），后面的装配、周次解析、界面预览全部复用

`CourseInfoDto` 的字段就是照这个约定设计的，`weeks_parser.dart` 的单双周语义也对齐了它的
`weekStr2IntList`/`getWeeks`，所以这一步**不需要动模型层**。

再加一个「粘贴自定义解析器 `.js`」的入口，就能让用户自己适配任何学校，
不用我们逐校维护。

---

## 12. 排错手册

| 现象 | 原因 / 处理 |
|---|---|
| `LNK1104: 无法打开文件"ucrtd.lib"` | 没用 `tool/flutter-msvc.bat`。见 §1.2 ③ |
| `error C1083: 无法打开包括文件 atlbase.h` | VS Build Tools 的 ATL 组件被卸了。见 §1.2 ② |
| `Building with plugins requires symlink support` | 开发者模式被关了。见 §1.2 ① |
| `No CMAKE_CXX_COMPILER could be found` | 通常是 ucrt 那个问题的**表层症状**（CMake 的编译器探测在链接步失败）。看 `build\windows\x64\CMakeFiles\CMakeConfigureLog.yaml` 里的真实错误 |
| CMake 报错改完还是同样的错 | CMake 会缓存失败结果，`rm -rf build` 再来 |
| 测试挂死 10 分钟后超时、无错误信息 | `testWidgets` 里做了真实 IO 没包 `runAsync`。见 §7.2 ① |
| 测试报 `RenderFlex overflowed` 但真机正常 | 测试字体行高差异。见 §7.2 ② |
| 提醒不弹 | ①检查是不是全屏程序在前台（Windows 会抑制通知）②系统设置里「通知」总开关和本应用开关 ③焦点助手 ④设置页点「10 秒后测试提醒」看日志里的 `lastError` ⑤确认挂件进程在跑 |
| 挂件看不见 | 它是 `alwaysOnBottom`，被其它窗口盖住了。点托盘图标会 `show()`；或者在设置里关掉「贴在桌面上」改成置顶 |
| 挂件位置乱了 | 删掉数据目录里的 `widget_pos.json`，下次启动回到主屏右下角 |
| 双击图标没反应 | 单实例机制：已有同模式实例在跑，它会把已有窗口叫到前面。挂件被隐藏时表现为「没反应」，点托盘图标即可 |
| 数据似乎丢了 | 看数据目录有没有 `desktile_data.json.broken`（解析失败时的备份），它里面是原始内容 |
| 界面文字乱码（控制台） | 只是 GBK 控制台的显示问题，文件本身是 UTF-8。用 Python 以 UTF-8 读取确认 |

---

## 13. 相关链接

- CSES 格式与官方 schema：https://github.com/CSES-org/CSES
- 小爱课程表解析器示例（正方新版）：https://github.com/Arkitect-z/Xiaoai-Schedule-For-New-Zhengfang-System
- `window_manager` API：https://pub.dev/documentation/window_manager/latest/
- Flutter 桌面多窗口现状：https://docs.flutter.dev/platform-integration/desktop
- home_widget（Phase 2 会用到）：https://pub.dev/packages/home_widget













