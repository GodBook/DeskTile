# DeskTile 课表岛

桌面极简课程表小组件。无广告、无账号、纯本地，冷启动即用。

**当前状态**：Windows 端（Phase 1）已完成并验证；Android 端（Phase 2）尚未实现，
跨平台核心逻辑已经写好并被单元测试覆盖，Android 只需接原生小组件与闹钟。

> 接手开发请先读 **[HANDOVER.md](HANDOVER.md)** —— 环境坑、架构决策、文件职责、
> 验证记录、Phase 2/3 落地步骤和排错手册都在那里。本文件只是使用向导。

截图见 [docs/screenshots/](docs/screenshots/)。

## 已实现（Windows）

- **周视图**：节次时间轴 + 周一~周日，今天所在列高亮，课程块按课名稳定配色
- **单双周**：周次是一个集合，「每周 / 单周 / 双周 / 自定义（1-8,10,12-16）」走同一条路径；
  顶栏可以逐周切换并显示当前是单周还是双周
- **桌面挂件**：无边框圆角卡片，贴在桌面上（不遮挡其它窗口），任意位置拖动、位置记忆，
  托盘常驻。显示「第 N 周 · 周几 · 单/双周 → 下一节（课名 + **教室** + 倒计时）→ 今日课程 →
  最近考试倒计时」，另有只显示下一节的迷你形态
- **早八教室提醒**：每天第一节课前 N 分钟弹 Windows 通知，正文必带教室；
  可切换成「每节课都提醒」；「早八」判定阈值可调（拉到 24:00 就等于每天第一节都提醒）
- **考试倒计时**：科目 / 时间 / 考场 / 座位，按开考时间排序，考完的自动折叠
- **导入**：CSV、CSES v2 YAML、ICS、小爱课程表 `courseInfos` JSON，导入前先给解析预览和警告
- **导出**：CSES v2 YAML（可被 ClassIsland 等读取）、完整备份 JSON
- **开机自启**：写 `HKCU\...\CurrentVersion\Run`，启动的是挂件模式，不需要管理员权限

## 运行与构建

本机 Windows SDK 注册表的 64 位视图指向了一个没有 `Include/Lib` 的空目录，
CMake 驱动的 64 位 MSBuild 因此拿不到 ucrt 库路径，链接会报 `LNK1104: ucrtd.lib`。
`tool/flutter-msvc.bat` 通过覆盖 `UCRTContentRoot` 环境变量绕开它，**不改注册表**。
在这台机器上请统一用它代替 `flutter`：

```bash
tool/flutter-msvc.bat analyze
tool/flutter-msvc.bat test
tool/flutter-msvc.bat run -d windows
tool/flutter-msvc.bat build windows --release
```

产物：`build\windows\x64\runner\Release\desktile.exe`

两种运行模式（同一个 exe）：

```bash
desktile.exe            # 主窗口：编辑课表、导入导出、设置
desktile.exe --widget   # 桌面挂件 + 托盘，常驻，负责排提醒
```

Flutter stable 目前不支持多窗口，所以两者是两个进程：主窗口是唯一的写入方，
挂件只读并用 `Directory.watch` 监听数据文件变化，1 秒内自动刷新。
每种模式各自绑定一个回环端口（45677 / 45678）当互斥锁，重复启动会把已有窗口叫到前面。

## 数据

单个 JSON 文件：`%APPDATA%\com.desktile\desktile\desktile_data.json`
（设置里「导入导出 → 打开数据目录」可直接打开）。写入走「临时文件 + rename」原子替换；
文件损坏时会备份成 `.broken` 并回到初始状态，不会让程序起不来。
挂件位置单独存 `widget_pos.json`，避免两个进程互相覆盖。

## 导入格式

| 扩展名 | 说明 |
|---|---|
| `.csv` | 表头 `课程名称,教师,教室,星期,节次,周次`。星期认 `1..7` / `周三` / `星期三` / `Wed`；周次认 `1-16`、`1-16单`、`双`、`1-8,10,12-16`、全角逗号。模板见 `docs/示例课表.csv`，设置页也能直接导出模板 |
| `.yaml` / `.yml` | [CSES v2](https://github.com/CSES-org/CSES)。它用「循环中的第几个工作日」定位课程，导入时会按 `cycle.spans` 还原成星期几 + 单双周；只支持 1 周和 2 周循环，更长的循环会明确报错而不是悄悄算错 |
| `.ics` | 每次课一条 VEVENT 的日历文件。学期第一周周一按最早的事件推算，节次时间表按出现过的时间段推算；带 `RRULE` 的重复事件不展开，会在警告里说明 |
| `.json` | 小爱课程表的 `{"courseInfos":[...]}` 结构（`sections` 支持 `[{section:1}]` 和 `[1]` 两种写法），或本程序导出的备份 |

导入是**整表覆盖**当前课表，确认前会先显示解析到多少门课、多少个时段以及全部警告。

## 目录结构

```
lib/
├─ core/                 纯 Dart，不依赖 Flutter，测试全覆盖
│  ├─ models/            Timetable / Course / CourseSession / Exam / TimeSlot / AppSettings
│  ├─ week_math.dart     学期周次换算（UTC 归一化，不受时区影响）
│  ├─ weeks_parser.dart  周次串解析与格式化（导入与未来教务解析共用）
│  ├─ agenda.dart        某周某天的课、下一节、今日剩余
│  ├─ reminder_plan.dart 提醒计划（决定性 id + 含教室的正文）
│  ├─ exam_countdown.dart
│  └─ import/            course_info_dto / csv / cses / ics / json / exporter
├─ data/                 app_data（纯数据）、store（原子 JSON 读写 + 文件监听）、app_state
├─ platform/             窗口、托盘、通知、开机自启、单实例
└─ ui/                   主窗口与挂件

tool/
├─ flutter-msvc.bat      带 ucrt 修补的 flutter 包装
└─ seed_demo_data.dart   用真实导入代码灌示例数据，验证界面用
```

没有引入状态管理库和 SQLite：一个 `ChangeNotifier` + `InheritedNotifier` 够用，
课表数据只有几百行，单 JSON 文件更适合备份和跨端搬运（`sqlite3_flutter_libs` 也已 EOL）。

## 验证情况

已实测通过：

- `flutter analyze` 无任何问题；`flutter test` 116 个测试全绿（含 5 个界面测试）
- Release 构建成功，主窗口与挂件都实际运行并截图确认
- 单双周：第 1 周显示单周课、第 2 周显示双周课，界面测试与真机截图双向确认
- 早八提醒：示例课表下启动即排定 2 条（周一、周四第一节 08:00），
  `pendingNotificationRequests` 确认系统已接收
- 跨进程同步：外部改写数据文件后挂件 ~1 秒内刷新
- 导出的 CSES YAML 通过官方 `cses.schema.json`（draft-07）校验

未能实测：

- **Windows Toast 的视觉弹出**。排定与系统接收都验证过，但验证时桌面有全屏程序在前台，
  Windows 会自动抑制通知，所以没截到弹窗。请在设置页点一下「10 秒后测试提醒」自行确认。
- Android 端全部功能（Phase 2 未开工）。

## 后续路线

- **Phase 2（Android）**：装 JDK 17 + Android SDK；桌面小组件用 `home_widget` +
  Kotlin `GlanceAppWidgetReceiver`；提醒用 `zonedSchedule` + `exactAllowWhileIdle`，
  需要引导国产 ROM 加自启动白名单（这是这类 App 提醒失效的头号原因）。
  注意 `platform/notifications.dart` 里目前用 UTC 表示提醒时刻（Windows 只看绝对时间戳），
  接 Android 时要换成真正的本地时区。
- **Phase 3（教务系统直连）**：内嵌 WebView 登录 + 注入小爱课程表兼容的
  `scheduleHtmlProvider` / `scheduleHtmlParser`，产出的 `courseInfos` 直接走
  `core/import/course_info_dto.dart` 这条已经建好的通路，社区 `.js` 解析器可由用户粘贴导入。

