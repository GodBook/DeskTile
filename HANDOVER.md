# DeskTile 课表岛 — 项目交接文档

> 最后更新：2026-08-30 · 当前状态：Phase 1（Windows）完成 + Phase 2（Android）完成
> 代码位置：`D:\CLAUDE\DeskTile`（原中文目录 `D:\CLAUDE\DeskTile课表岛` 未使用，见 §1.2）
> 仓库：https://github.com/GodBook/DeskTile （公开）· 当前发布与源码版本：`v1.2.7`
> 规模：`lib/` 58 个文件，`test/` 20 个文件 / 205 个 Flutter 用例 + 3 个 Android 原生用例

---

## 0. 现状一句话

**Windows 端**功能完整、Release 构建通过、205 个 Flutter 测试全绿、实机跑过并截图；
唯一已知缺陷是 Toast 弹窗在本机 Windows 11 26200 上不显示（排定逻辑正确，见 §8）。

**Android 端 Phase 2 已完成**：单 Activity 手机界面、Jetpack Glance 主屏小组件、
30 分钟后台刷新、IANA 本地时区精准提醒、每日重排和开机恢复均已落地。
API 36 模拟器已验证小组件即时刷新、10 秒通知、精准闹钟、重启恢复和原生应用详情入口；
`v1.2.7` Release 提供正式签名 APK、AAB、Windows x64 Setup 和校验文件；此前已补齐 Windows
应用内更新、x64 Setup、自动发布、课表 `Ctrl + 滚轮` 缩放，以及双端共用的
临时调课 / 停课 / 补课和作业待办。`v1.2.6` 新增多课表管理与学期归档、作业/待办截止提醒、
默认“今天”日程页及手机“更多”导航；`v1.2.7` 新增学期校历与批量停课；
`v1.2.3` 起 Android 更新使用 `PackageInstaller Session`。

**下次接手的第一件事**：继续做 §10.5 的国产 ROM 真机后台可靠性验证并确定 Play App Signing。

---

## 0.1 版本控制与发布状态

| 项 | 状态 |
|---|---|
| git 仓库 | 已建（`master` 分支，已配置 GitHub 远端） |
| 远端 | `git@github.com:GodBook/DeskTile.git`（**SSH，不是 HTTPS**，原因见下） |
| 提交身份 | 仓库级占位身份 `DeskTile Dev <dev@localhost>`，**全局 git config 未被改动** |
| 标签 | `v1.0.0`（Windows 首发）、`v1.1.0`（Android Phase 2）、`v1.1.1`（线上更新与课表缩放）、`v1.1.2`（安装器兼容性修复）、`v1.2.2`（Windows 更新、临时课程变更、作业待办）、`v1.2.3`（Android 系统安装会话修复）、`v1.2.6`（多课表、待办提醒、今天页）、`v1.2.7`（学期校历与批量停课） |
| Release | https://github.com/GodBook/DeskTile/releases/tag/v1.2.7 · Android APK/AAB、Windows x64 Setup 与校验文件 |
| 当前源码 | `1.2.7+12`；`v1.2.7` 通过 Android/Windows 发布工作流构建 |

版本规则：以后每新增一个独立功能，补丁版本加 1、构建号也加 1。例如下一项新功能从
`1.2.7+12` 迭代到 `1.2.8+13`；修复版本按实际发布需要单独递增。

**为什么 remote 是 SSH**：本机 `github.com:443` 被墙（20 秒超时），
但 `github.com:22` 和 `ssh.github.com:443` 都通，`~/.ssh/id_ed25519` 也早就绑好了
（`ssh -T git@github.com` 返回 `Hi GodBook!`）。而 `api.github.com` 和
`uploads.github.com` 是通的 —— 所以 `gh` 的 API 操作（建仓库、发 Release、传附件）
一切正常，只有 git 传输需要走 SSH。换网络环境后想切回 HTTPS：

```bash
git remote set-url origin https://github.com/GodBook/DeskTile.git
```

---

## 1. 环境

### 1.1 本机已装什么

| 组件 | 版本 / 位置 | 备注 |
|---|---|---|
| Flutter SDK | 3.47.1 stable，`D:\dev\flutter` | Dart 3.13.1；已加入用户 PATH（原 PATH 备份在 `D:\dev\user-path-backup.txt`） |
| VS Build Tools 2022 | 17.14.37，含 MSVC 14.44.35207 + ATL | `flutter doctor` 认它，不需要装完整 Visual Studio |
| Windows SDK | 10.0.26100.0（另有 10.0.19041.0） | 实际文件在 `C:\Program Files (x86)\Windows Kits\10` |
| Inno Setup | 6.7.3，`C:\Users\awxds\Documents\SuperMemo\.tools\InnoSetup` | `ISCC.exe` 不在默认 Program Files 路径，生成 Windows Setup 时使用这里 |
| 开发者模式 | 已开启 | 见 §1.2 第 1 条 |
| JDK | Temurin **24.0.1**，`D:\ssoftware\JAVA24` | 完整 JDK（含 `javac`、`jmods`）。另有 Temurin 21.0.7 LTS 在 `D:\software\MCreator\jdk`（MCreator 自带），可作备用 |
| Android SDK | `D:\dev\android-sdk` | API 35/36、Build Tools 36.0/36.1、NDK 28.2、CMake 3.22.1，详见 §10.1 |
| Android 设备 | `DeskTile_API36` | Pixel 6、Android 16 / API 36、`google_apis/x86_64`；当前设备号通常为 `emulator-5554` |

`flutter doctor -v` 已识别 Android SDK、模拟器和 JDK。Android toolchain 仍显示 `!`，
仅因为新版 Android CLI 与 Flutter 的 license 检测不兼容而报 `license status unknown`；
实际 Debug APK 已反复构建成功。Network 检查会因 `maven.google.com` 超时显示 `!`，
Gradle 实际经 `dl.google.com` 下载依赖，不影响构建。

### 1.2 四个必须知道的环境坑

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

**④ Android 构建必须使用专用 Gradle 用户目录**

全局 `C:\Users\awxds\.gradle\init.gradle` 会改写仓库配置，与 Flutter/AGP 的
repositories 策略冲突。DeskTile 已验证可用的隔离目录是
`C:\Users\awxds\.gradle-desktile`。构建 Android 前必须设置 `GRADLE_USER_HOME`，
不要删除或修改用户的全局 Gradle 配置。

### 1.3 常用命令

```bash
tool/flutter-msvc.bat analyze                  # 静态检查，目前 0 问题
tool/flutter-msvc.bat test                     # 全部 191 个测试
tool/flutter-msvc.bat test test/ui_test.dart   # 只跑界面测试
tool/flutter-msvc.bat run -d windows           # 调试运行（主窗口模式）
tool/flutter-msvc.bat build windows --release  # 出包
```

产物：`build\windows\x64\runner\Release\desktile.exe`（整个 Release 目录一起拷才能跑，
Dart 代码在 `data\app.so`，插件 DLL 和 `data\flutter_assets\` 都要带上）。

本机生成 Windows Setup：

```powershell
& 'C:\Users\awxds\Documents\SuperMemo\.tools\InnoSetup\ISCC.exe' `
  /DAppVersion=1.2.7 installer\DeskTile.iss
```

Android 构建固定使用以下环境（PowerShell）：

```powershell
$env:JAVA_HOME='D:\ssoftware\JAVA24'
$env:ANDROID_HOME='D:\dev\android-sdk'
$env:ANDROID_SDK_ROOT='D:\dev\android-sdk'
$env:GRADLE_USER_HOME='C:\Users\awxds\.gradle-desktile'
D:\dev\flutter\bin\flutter.bat build apk --debug
D:\dev\flutter\bin\flutter.bat build apk --release
D:\dev\flutter\bin\flutter.bat build appbundle --release
```

操作模拟器时显式使用 `D:\dev\android-sdk\platform-tools\adb.exe`，避免 PATH 里的
另一份 Platform Tools 抢到设备连接。

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

Android 依赖方面，`maven.google.com` 在本机仍会超时，但 `google()` 解析到的
`https://dl.google.com/dl/android/maven2/` 可正常下载并完成构建。

---

## 2. 产品范围

### 2.1 已实现（Windows）

- **周视图**：左侧节次时间轴（节次号 + 起止时刻），上方周一~周日（可隐藏周末），
  今天所在列高亮；课程块按课名的稳定哈希取色，跨节次的课竖向合并成一块
- **切周**：`‹ 第 N 周 · 单/双周 ›` + 「回到本周」；学期外自动落到第 1 周或最后一周
- **单双周**：见 §6.1
- **课程编辑**：点空格新增、点课程块编辑；周次选择支持「每周 / 单周 / 双周」快捷 chip
  加自由输入（`1-16`、`1-16单`、`1-8,10,12-16`），实时显示解析结果和「本周是否上」
- **临时课程变更**：常规课程编辑框可对当前日期执行停课或调课；工具栏按钮、空白格右键可添加补课；
  调课 / 补课可选日期、节次和教室并提示冲突，周视图显示停课、调出、调课、补课状态
- **学期校历与批量停课**：按日期范围记录假期、考试周、停课或其他安排；事件可仅标记，
  也可暂停范围内全部常规课程，显式补课和调入保留；周视图、今天页、提醒和挂件走同一日程结果
- **节次时间表**：可增删改每一节的起止时间，可一键恢复默认 12 节
- **桌面挂件**：见 §6.3
- **今天页**：默认首页统一展示当前/下一节、当天课程、今天截止与逾期待办和最近三场考试，见 §6.9
- **多课表与归档**：新建、复制、重命名、切换、归档、恢复和删除，见 §6.9
- **课程与待办提醒**：见 §6.2
- **考试倒计时**：科目 / 日期 / 开考-结束 / 考场 / 座位 / 备注；按开考时间升序，
  3 天内变红，考完的收进「已结束（N）」折叠区
- **作业与待办**：作业/待办类型、课程关联、重要标记、截止日期和时间、备注、完成/恢复、
  编辑和删除；按逾期、今天、接下来、无截止日期、已完成分组，并支持截止提醒与 10 分钟后再次提醒
- **导入**：CSV、CSES v2 YAML、ICS、小爱课程表 JSON，见 §6.4
- **导出**：CSES v2 YAML、完整备份 JSON、CSV 模板（带 UTF-8 BOM，Excel 打开不乱码）
- **开机自启**：写 `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`，
  值是 `"<exe>" --widget`，不需要管理员权限
- **应用内更新**：查询 GitHub Release、选择 x64 Setup、流式下载并校验 SHA-256，
  Inno Setup 覆盖当前程序目录并通过 Restart Manager 关闭主窗口和挂件
- **主题**：跟随系统 / 浅色 / 深色

### 2.2 已实现（Android）

- **手机界面**：默认“今天”页、底部五栏与“更多”页、状态栏/手势区 `SafeArea`、课表双指缩放与平移、320px 窄屏课程编辑器
- **作业与待办**：与 Windows 共用模型、页面和本地 JSON 数据，包含截止提醒和稍后提醒操作
- **临时课程变更**：与 Windows 共用模型和弹窗；长按空白格添加补课，停课 / 调课入口位于常规课程编辑框
- **学期校历与批量停课**：手机“更多”页提供管理入口；今天页、提醒和 Glance 小组件同步排除批量停课
- **主屏小组件**：Glance 展示周次、下一节、教室、今日剩余和最近考试；支持从应用请求固定到主屏
- **数据刷新**：课表保存后约 300ms 内刷新小组件，前台每分钟刷新倒计时，后台每 30 分钟刷新
- **课程提醒**：设备 IANA 时区 + `exactAllowWhileIdle`，每天本地 00:05 重排未来 7 天
- **系统恢复**：通知插件 receiver 恢复开机前闹钟，WorkManager 与 Glance 实例在重启后保留
- **权限与引导**：只在用户明确开启/重排/测试提醒时请求权限；设置页可打开系统应用详情
- **应用内更新**：设置页可查询 GitHub Release、流式下载 APK，并写入 `PackageInstaller Session`；
  系统回调用户确认界面，不再把应用私有缓存交给文件管理器
- **跨端数据**：沿用备份 JSON 导入导出，无需新增 Android 专用数据格式

### 2.3 明确不做（当时和需求方确认过的）

账号系统、云同步、广告位、课程社区。也没有引入 SQLite、状态管理库、多窗口插件，
理由见 §3.2。

### 2.4 未实现 / 发布前事项

| 项 | 状态 |
|---|---|
| 教务系统直连（登录 + 抓课表） | Phase 3，见 §11。解析通路已预留 |
| 常规课程冲突提示 | 临时调课 / 补课已提示冲突；常规重复课程编辑器尚未接冲突提示 |
| Android 发布准备 | `v1.2.7` 正式 APK/AAB 已发布；尚未在国产 ROM 真机验证后台白名单，也未确定 Play App Signing |

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
    platform/ 窗口 · 托盘 · 跨平台通知 · Android 后台任务/小组件桥
```

Android 不使用桌面的双进程路径。`main.dart` 先判断 `Platform.isAndroid`，加载同一份
`AppState` 后直接运行 `MainApp`；状态变化经 300ms 防抖同步 HomeWidget payload，
课表变化还会重排提醒。应用退到后台后，WorkManager 在独立 isolate 中读取
`desktile_data.json`，分别刷新 Glance 小组件和每日提醒。

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
| `models/schedule_change.dart` | 177 | `ScheduleChange`：停课、跨日/跨节次调课、一次性补课；含 JSON 往返和学期日期平移 |
| `models/academic_calendar_event.dart` | 91 | `AcademicCalendarEvent`：假期、考试周、停课或其他日期范围；支持仅标记/暂停课程、JSON 往返和日期平移 |
| `models/timetable.dart` | 136 | `Timetable`；构造时把 `termStart` **自动对齐到周一**，持有常规时段、临时变更和校历事件 |
| `models/exam.dart` | 60 | `Exam` |
| `models/task_item.dart` | 81 | `TaskItem`、作业/待办类型、重要程度、截止与完成状态，含 JSON 往返和课表关联重绑 |
| `models/settings.dart` | 109 | `AppSettings` + `ReminderMode` / `WidgetForm` / `ThemePref` |
| `week_math.dart` | 69 | 周次换算。跨天计算统一归一化到 UTC 午夜再相减，避免时区/夏令时少算一天 |
| `weeks_parser.dart` | 132 | 周次串解析与格式化，见 §6.1 |
| `stable_hash.dart` | 12 | 跨进程稳定的字符串哈希（31 位内，Android 通知 id 要求 32 位 int） |
| `academic_calendar.dart` | 114 | 校历日期查询、批量停课命中、停课天数与受影响常规课程次数统计 |
| `agenda.dart` | 236 | `ResolvedSession`、`sessionsOnDate`、`sessionsOnWeekDay`、`agendaForDate` 等；统一应用临时变更和校历停课，周视图可保留停课来源 |
| `reminder_plan.dart` | 92 | `buildReminders()` → `PlannedReminder` 列表，见 §6.2 |
| `task_reminder_plan.dart` | 59 | 作业与待办提醒计划、课程正文和独立通知 id 命名空间 |
| `today_overview.dart` | 41 | 聚合今天课程、今天/逾期待办和最近三场考试 |
| `exam_countdown.dart` | 59 | `upcomingExams` / `pastExams` / `formatRemaining` |
| `task_query.dart` | 52 | 作业待办的五类分组、显示顺序和最近截止查询 |
| `widget_payload.dart` | 159 | 组装 Android 小组件所需的紧凑 JSON：周次、下一节、今日剩余、最近考试；纯 Dart、可测试 |

### `lib/core/import/` — 所有格式先转成同一个中间结构

| 文件 | 行 | 职责 |
|---|---|---|
| `course_info_dto.dart` | 251 | **枢纽**。`CourseInfoDto` 字段与小爱课程表 `courseInfos` 一一对应；`ImportedSchedule` 可携带原始 DeskTile 课表和任务；`buildTimetable()` 装配普通导入或原样恢复备份、临时变更和校历事件 |
| `field_parsers.dart` | 40 | `parseWeekDay`（认 `1..7`/`周三`/`星期三`/`Wed`）、`parseSections` |
| `csv_importer.dart` | 120 | CSV，表头别名匹配，缺列给可读错误，坏行进警告 |
| `cses_importer.dart` | 210 | CSES v2 YAML，含「工作日循环 → 星期几 + 单双周」的还原算法 |
| `ics_importer.dart` | 119 | ICS，推算学期起点和节次时间表 |
| `json_importer.dart` | 414 | 小爱课程表 `courseInfos` / 自有备份；备份恢复时保留内部 ID、临时变更和作业待办，学期起始日调整时同步平移日期 |
| `exporter.dart` | 180 | 导出 CSES v2 YAML（手写 YAML，无额外依赖）；无法表达的周次、临时变更和校历事件进入 warnings |

### `lib/data/`

| 文件 | 行 | 职责 |
|---|---|---|
| `app_data.dart` | 92 | `AppData`（课表、考试、作业待办、设置）+ `toJson`/`fromJson`/`initial`，当前 `schemaVersion = 5`。**刻意不依赖 Flutter 和 path_provider** |
| `store.dart` | 88 | `DataStore`：定位目录、原子写（tmp + rename）、损坏兜底（备份成 `.broken`）、`watch()` 文件监听（300ms 防抖）；`newId()` |
| `app_state.dart` | 259 | `AppState`（ChangeNotifier）+ `AppScope`（InheritedNotifier）。提供多课表切换/归档/删除、任务提醒/稍后提醒和安全跨进程写入 |
| `widget_position.dart` | 47 | 挂件位置单独存 `widget_pos.json` |

### `lib/platform/` — 平台集成

| 文件 | 行 | 职责 |
|---|---|---|
| `desktop_window.dart` | 87 | `isWidgetMode(args)`、`setupMainWindow()`、`setupWidgetWindow()`、`applyWidgetAppearance()`、`defaultWidgetPosition()`（贴主屏右下角）、两种挂件尺寸常量 |
| `tray.dart` | 121 | 托盘图标与菜单（显示/隐藏挂件、迷你模式、贴桌面、打开主窗口、开机自启、退出）；左键点图标显示挂件、右键弹菜单 |
| `notifications.dart` | 263 | 跨平台 `ReminderService`；统一排课程和待办通知，处理 10 分钟后提醒操作；Windows 注册 AUMID，Android 使用 IANA 时区 |
| `autostart.dart` | 29 | 读写 `Run` 键 |
| `windows_registry.dart` | 50 | 直接调 `reg.exe` 的极简封装。**没用 `win32_registry`**，因为它依赖的 win32 版本和 `file_picker 12` 冲突 |
| `single_instance.dart` | 95 | 绑定回环端口当互斥锁（挂件 45677 / 主窗口 45678），兼作「唤起已有窗口」的 IPC；`ModeLauncher` 启动另一种模式的进程 |
| `android_widget.dart` | 65 | Dart → HomeWidget 桥：保存 payload、触发 Glance 更新、请求固定到主屏 |
| `android_background.dart` | 91 | WorkManager dispatcher；30 分钟小组件刷新、每日 00:05 提醒重排、旧 v1 任务迁移 |
| `android_system_settings.dart` | 21 | MethodChannel 打开当前应用的 Android 系统详情页 |
| `release_update.dart` | 605 | 双端共享的 Release 解析、版本比较、平台资产筛选、HTTPS/大小限制、流式下载与 SHA-256 校验 |
| `android_update.dart` | 167 | Android 版本通道、共享更新核心适配与 APK 系统安装器桥接 |
| `windows_update.dart` | 92 | Windows 文件版本读取、x64 Setup 下载适配与 Inno Setup 启动 |

### `lib/ui/`

| 文件 | 行 | 职责 |
|---|---|---|
| `theme.dart` | 57 | M3 主题、10 色课程配色板、`courseColor(seed)`、日期/时刻格式化 |
| `app.dart` | 181 | 主界面壳：默认进入今天；宽屏六个入口，手机五栏加“更多”二级页 |
| `pages/today_page.dart` | 563 | 今天时间轴、当前/下一节、截止事项、近期考试及就地编辑入口；显示并可编辑校历停课来源 |
| `pages/more_page.dart` | 69 | 手机端学期校历、导入导出与设置二级入口 |
| `pages/academic_calendar_page.dart` | 546 | 校历概览、事件列表、日期范围编辑、仅标记/批量停课切换与实时影响预览 |
| `pages/timetable_manager.dart` | 284 | 多课表切换、新建、复制、重命名、归档、恢复和删除 |
| `pages/timetable_page.dart` | 853 | 响应式周视图：Android 双指缩放、Windows `Ctrl + 滚轮` 缩放；显示临时和校历停课状态，工具栏可进入学期校历 |
| `pages/session_editor.dart` | 402 | 常规课程时段编辑弹窗；提供“临时调整本次课程”入口，删除时同步清理关联停课/调课 |
| `pages/schedule_change_editor.dart` | 421 | 停课 / 调课 / 补课编辑弹窗；日期、节次、教室、课程选择、冲突提示、恢复原安排和删除补课 |
| `pages/tasks_page.dart` | 945 | 作业待办列表、三段筛选、五类分组、截止提醒选择和 10 分钟后提醒 |
| `pages/exams_page.dart` | 321 | 考试列表 + 编辑弹窗 |
| `pages/import_export_page.dart` | 509 | 格式说明、覆盖/新建课表导入、备份任务追加与 ID/课程重绑、三个导出动作 |
| `pages/settings_page.dart` | 850 | 学期 / 节次 / 课程与待办提醒 / Android 后台可靠性、主屏小组件、应用更新 / 桌面挂件 / 外观设置 |
| `widget_app.dart` | 380 | 挂件：`_WidgetSurface`（拖动 + 位置保存 + 20s 刷新计时器）、`_Header`、`_NextUp`、`_TodayList`、`_ExamLine` |
| `main.dart` | 216 | Android/Windows 启动分流；状态变化时同步课程与待办提醒；Windows 两种进程与每日重排 |

---

## 5. 数据

### 5.1 模型关系

```
AppData
 ├─ activeTimetableId
 ├─ timetables: [Timetable]
 │                ├─ termStart（第一周的周一，构造时自动对齐）
 │                ├─ totalWeeks / showWeekend / archived
 │                ├─ timeSlots: [TimeSlot]     第几节 → 起止时刻
 │                ├─ courses:   [Course]       课名 / 教师 / 配色种子
 │                ├─ sessions:  [CourseSession] 星期 + 起止节次 + 周次集合 + 教室
 │                ├─ scheduleChanges: [ScheduleChange] 单次停课 / 调课 / 补课
 │                └─ academicCalendarEvents: [AcademicCalendarEvent] 日期范围 + 类型 + 是否暂停常规课程
 ├─ exams: [Exam]
 ├─ tasks: [TaskItem]              作业 / 待办、课程关联、截止、提醒与完成状态
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
  "schemaVersion": 5,
  "activeTimetableId": "t1",
  "timetables": [{
    "id": "t1", "name": "2026 秋季学期",
    "termStart": "2026-08-17", "totalWeeks": 16, "showWeekend": true, "archived": false,
    "timeSlots": [{"index": 1, "start": "08:00", "end": "08:45"}],
    "courses":   [{"id": "c1214213202", "name": "高等数学A", "teacher": "张伟",
                   "colorSeed": 1553760393}],
    "sessions":  [{"id": "s1948299589", "courseId": "c1214213202", "day": 2,
                   "startSection": 1, "endSection": 2,
                   "weeks": [1,3,5,7,9,11,13,15], "room": "教三-208"}],
    "scheduleChanges": [{"id": "change1", "type": "cancellation",
                         "originalSessionId": "s1948299589",
                         "originalDate": "2026-09-08"}],
    "academicCalendarEvents": [{"id": "holiday1", "title": "国庆假期",
                                 "type": "holiday", "startDate": "2026-10-01",
                                 "endDate": "2026-10-07", "suspendsClasses": true}]
  }],
  "exams": [{"id": "e1", "name": "高等数学A 期末",
             "startAt": "2026-09-02T09:00:00.000", "endAt": "...",
             "room": "教三-305", "seat": "18"}],
  "tasks": [{"id": "task1", "title": "完成高数习题", "kind": "homework",
             "createdAt": "2026-08-29T09:00:00.000", "dueAt": "2026-08-30T20:00:00.000",
             "reminderAt": "2026-08-30T18:00:00.000",
             "timetableId": "t1", "courseId": "c1214213202", "priority": "important"}],
  "settings": {"reminderEnabled": true, "reminderMode": "firstClassOfDay",
               "leadMinutes": 30, "earlyClassCutoffMinutes": 540,
               "taskReminderEnabled": true, "defaultTaskReminderLeadMinutes": 1440,
               "widgetOpacity": 0.95, "widgetForm": "standard",
               "widgetAlwaysOnBottom": true, "autoStart": false, "theme": "system"}
}
```

另一个文件 `widget_pos.json`：`{"x": 1993.0, "y": 857.0}`（物理像素，挂件位置）。

**迁移策略**：顶层 `schemaVersion` 目前是 5；旧数据缺少 `tasks`、旧课表缺少
`scheduleChanges` / `academicCalendarEvents` 时读取为空列表，缺少 `archived`、`reminderAt`
和待办提醒设置时使用兼容默认值。
加字段直接在 `fromJson` 里给默认值即可
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

### 6.2 课程与待办提醒

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

`platform/notifications.dart` 负责落地：滚动排未来 7 天，每次都先 `cancelAll()` 再全量写入。
`task_reminder_plan.dart` 同时把未完成且提醒时间在未来的任务加入计划；待办 id 固定使用
`0x40000000..0x7fffffff`，与课程通知的低 30 位命名空间隔离。通知正文会带关联课程和截止时间，
Android/Windows 通知操作都支持“10 分钟后提醒”，挂件进程会先读磁盘最新数据再安全写回。

Windows 在应用/挂件启动、数据变化和每天 00:05 重排；Android 在应用启动、课表/任务变化和
WorkManager 每日任务中重排。Android 周期任务的唯一名是 `desktile_reminder_refresh_v2`：
旧版任务的 30 分钟 flex 会把首次执行额外推迟约 23.5 小时，初始化时会先取消 v1 再迁移。

平台侧三个细节：
- 未打包的 Win32 程序要让 Toast 显示正确的应用名和图标，得在
  `HKCU\Software\Classes\AppUserModelId\DeskTile.KeBiaoDao.Desktop` 下写
  `DisplayName` 和 `IconUri`，`init()` 里自动做了，纯用户级。
- Windows 的 `_scheduleLocation` 保持 UTC，插件按绝对时间戳调度；Android 通过
  `flutter_timezone` 读取设备 IANA 名并使用对应 `tz.Location`，避免非 UTC 地区和 DST 漂移。
- Android 用 `exactAllowWhileIdle`；通知权限与精准闹钟权限只允许由设置页中的明确用户操作请求，
  WorkManager 后台任务不会尝试弹权限页。Manifest 已注册定时通知和开机恢复 receiver。

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
确认前 `showImportPreview()` 会显示解析到多少门课、多少个时段、全部警告，并允许调整学期第一周
和总周数。用户可选择覆盖当前课表，或新建课表并保留原表。

| 格式 | 关键点 |
|---|---|
| CSV | 表头别名匹配（`课程名称/课程名/课程/name/course` 等）；节次可以写成一列 `1-2`，也可以 `开始节次`+`结束节次` 两列；缺必需列时报出「缺哪几列 + 实际表头」；单行解析失败进 warnings 不中断整份导入 |
| CSES v2 | 它用 `enable_day`（循环中的第几个**工作日**）定位课程，不是星期几。`_resolveCycle()` 走一遍 `cycle.spans` 把工作日序号还原成 (星期几, 第几个循环周)：循环长度必须是整数周，1 周 → 每周，2 周 → 单/双周，**3 周以上明确抛异常**而不是悄悄算错。CSES 没有节次概念，节次时间表由文件里出现过的所有 `(start_time, end_time)` 排序推出。`enable_day: [1, 6]`（两个循环周的周一）会在合并阶段还原成「每周」 |
| ICS | 面向「每次课一条 VEVENT」的导出。学期第一周周一 = `mondayOf(最早事件)`；总周数按最晚事件推；节次时间表同样由时间段推算（会给一条警告说明一段可能对应现实的连续两节）；带 `RRULE` 的不展开，给警告 |
| JSON | 顶层可以是 `{"courseInfos":[...]}` 或直接是数组；`sections` 支持 `[{"section":1}]` 和 `[1]` 两种写法；可选的 `sectionTimes` 会变成节次时间表。这也是本程序备份文件的读入口，完整备份会恢复作业待办并重绑当前课表 ID |

普通 CSV/CSES/ICS/小爱 JSON 不管理也不清空现有任务。顶层带 `tasks` 字段的 DeskTile 完整备份
在覆盖模式下替换待办；新建课表模式会追加待办、生成新 ID，并把课程关联重绑到新课表。

### 6.5 导出

- **备份 JSON**：`AppData.toJson()` 原样吐出，包含课表、临时安排、考试、作业待办和设置，跨设备搬运用。
- **CSES YAML**：`exporter.dart` 手写 YAML（不引 YAML 写库）。因为 CSES 的
  `work_count`/`rest_count` 都要求 ≥ 2，映射规则是：周一~周五有课 → 工作 5 休息 2；
  周六也有课 → 工作 6 休息 1（为满足 `rest_count>=2` 写成两周循环）；
  **有周日的课直接拒绝导出并说明原因**。周次既不是每周也不是单/双周的时段会被跳过，
  每一条都进 warnings 并在界面上提示。导出结果已用官方 `cses.schema.json` 校验通过。

### 6.6 Android 主屏小组件

`buildWidgetPayload()` 复用 `agenda.dart` 和 `exam_countdown.dart`，输出稳定 JSON；
`AndroidWidgetService` 用 HomeWidget shared preferences 写入，再按 receiver 全限定名触发更新。
原生 `DeskTileGlanceWidget` 防御性解析 payload，并在整块点击时打开 `MainActivity`。

刷新链路有三层：

1. 前台状态保存后 300ms 防抖即时更新；课表、任务或设置变化都会重排提醒
2. 前台每分钟重算下一节与倒计时
3. WorkManager 每 30 分钟从磁盘重读；launcher 的 provider 也声明 30 分钟更新周期

Glance 实例和共享 payload 均能跨重启保留；新安装但尚无 payload 时显示轻量 loading 布局。

### 6.7 临时调课 / 停课 / 补课

临时安排存于 `Timetable.scheduleChanges`，不会改写原来的重复 `CourseSession`：

- 停课保存原时段 ID + 原日期；实际日程、提醒和小组件排除本次课程，周视图仍显示灰色删除线来源。
- 调课再保存目标日期、节次和教室；原位置显示“调出”，目标位置生成稳定 ID
  `change:<变更ID>` 并显示“调课”。
- 补课保存课程 ID + 目标日期/节次/教室，按一次性课程显示“补课”。

`agenda.dart` 是唯一的解析入口：提醒、小组件、挂件和下一节查询都消费应用变更后的
`sessionsOnDate()`；只有周视图传 `includeChangedSources: true`，用于展示停课和调出来源。
编辑常规课程时可进入本周对应日期的临时调整；工具栏可添加补课，Android 空白格长按、
Windows 空白格右键也可直达补课编辑器。删除常规时段会清理关联停课/调课，补课引用的课程会保留。

完整 JSON 备份保留原始课程/时段 ID 和全部临时安排；恢复时若修改学期第一周，相关日期按天平移。
CSES 无法表达单次变更，导出会明确警告并建议改用 JSON，而不是静默丢失。

### 6.8 作业与待办

任务独立存于 `AppData.tasks`，不塞进课表模型；可选的 `timetableId` / `courseId` 负责关联课程。
页面按逾期、今天、接下来、无截止日期和已完成分组，排序规则集中在纯 Dart 的
`task_query.dart`，因此 Windows 和 Android 行为一致且不依赖组件测试。

编辑器支持作业/待办类型、课程、重要标记、截止日期与时间、提醒时间和备注；新事项可默认提前
一天或两小时提醒，也可关闭或自定义。完成操作只设置
`completedAt`，恢复时清空它，不改变事项内容。删除与编辑都通过 `AppState` 原子写回 JSON。
删除课表时关联待办会保留，但解除课程关联；通知或列表均可把未完成事项推迟 10 分钟提醒。

### 6.9 多课表与“今天”页

`timetable_manager.dart` 提供切换、新建空表、复制、重命名、归档、恢复和删除。归档当前课表时会
自动切换到其他未归档表；归档唯一课表时创建 ID 唯一的空白表。课表页和今天页标题都是管理入口。

主窗口默认进入 `TodayPage`。宽屏侧栏显示今天、课表、待办、考试、导入导出、设置；手机底栏保留
今天、课表、待办、考试和更多，后两项工具页从“更多”进入。`today_overview.dart` 负责纯数据聚合，
今天时间轴会保留停课/调出来源，同时列出调入、补课、今天截止及逾期事项和最近三场考试。

### 6.10 学期校历与批量停课

每张 `Timetable` 独立保存 `academicCalendarEvents`。事件包含类型、名称、起止日期和
`suspendsClasses`；日期范围允许重叠，统计停课天数和实际课程次数时会按日期去重。

`agenda.dart` 解析常规课程时先应用单次停课/调课，再应用当天校历停课；校历只暂停重复的常规课程，
显式添加的补课和调入课程仍按目标日期出现。周视图用删除线和校历原因保留来源，实际日程、课程提醒、
今天页当前/下一节、Windows 挂件与 Android 小组件都会排除被暂停课程。仅标记事件只显示在校历列表
和周视图日期表头，不改变日程。完整 JSON 备份保留校历，CSES 不支持时会明确给出警告。

---

## 7. 测试

### 7.1 清单（205 个 Flutter 用例 + 3 个 Android 原生用例）

| 文件 | 用例 | 覆盖什么 |
|---|---|---|
| `week_math_test.dart` | 12 | 周次换算、`dateOfWeekDay`↔`weekDayOfDate` 互逆、`mondayOf`、跨时刻 `daysBetween`、构造时对齐周一 |
| `weeks_parser_test.dart` | 23 | 各种周次写法（全角逗号、波浪号、`第..周`、单/双、区间写反、越界裁剪、`单双周`）、`formatWeeks` 往返、`compressRanges`、`parseWeekDay`、`parseSections` |
| `academic_calendar_test.dart` | 3 | 校历事件日期/JSON、受影响课程统计、重叠停课日期去重和仅标记语义 |
| `agenda_test.dart` | 18 | 某周某天的课与排序、单双周、上课中/课间/跨天、今日剩余、学期外，以及单次变更、校历停课和补课优先级 |
| `reminder_plan_test.dart` | 14 | 早八 / 每节课模式、阈值、正文、排序和通知 id；单次或校历停课不提醒、调课按目标时间提醒 |
| `task_reminder_plan_test.dart` | 5 | 待办过滤、排序、课程正文、总开关和通知 id 命名空间 |
| `today_overview_test.dart` | 4 | 今天的单次/校历停课、调课、补课来源、今天与逾期待办、最近三场考试 |
| `exam_countdown_test.dart` | 15 | 排序与过滤、正在考、`examEndAt` 默认 2 小时、`formatRemaining` 各档 |
| `import_test.dart` | 22 | CSV / ICS / 小爱 JSON；DeskTile 备份保留内部 ID、临时安排和任务、平移学期日期，并覆盖仅剩补课的课表 |
| `cses_test.dart` | 15 | CSES 导入/导出、官方约束、往返一致；临时安排或校历无法表达时明确给出 JSON 备份警告 |
| `store_test.dart` | 12 | 初始数据、原子存取、损坏兜底、schema 5、校历/归档/提醒旧数据兼容、任务往返、`newId` |
| `app_state_test.dart` | 4 | 课表归档切换、唯一表归档兜底、删除课表解除任务关联、稍后提醒持久化 |
| `task_test.dart` | 6 | 任务 JSON、完成/恢复、五类分组、未完成/已完成排序和最近截止查询 |
| `ui_test.dart` | 25 | 双端布局/缩放、今天页、多课表、手机更多、校历 320px 编辑/持久化、周视图/考试/挂件/导入 |
| `widget_payload_test.dart` | 4 | Android 小组件 payload、学期外兜底，以及单次或校历停课后不再显示对应课程 |
| `android_background_test.dart` | 3 | 本地 00:05 前后边界，以及午夜前的次日延迟计算 |
| `reminder_permission_policy_test.dart` | 7 | Android 权限只在开启课程/待办提醒或明确重新排定时请求，普通设置和非 Android 不请求 |
| `android_update_test.dart` | 7 | 回退版本、版本比较、Release APK 筛选、降级拦截、完整下载与 HTTPS 校验 |
| `windows_update_test.dart` | 6 | 安装目录参数、设置页入口、x64 Setup 筛选、PE 文件头、临时文件清理与 SHA-256 拦截 |
| `UpdateInstallReceiverTest.kt` | 3 | 系统安装会话待确认、成功与失败状态分类 |

`docs/示例课表.csv` 和 `docs/示例课表.cses.yaml` 既是用户模板也是测试 fixture，
改动它们会影响 `import_test` / `cses_test` 的断言。

### 7.2 两个必须知道的测试陷阱

**① `testWidgets` 里的真实文件 IO 必须包在 `tester.runAsync()` 里**

`testWidgets` 跑在 fake async 区，真实 IO 的 Future 永远不会完成 —— 表现是测试挂死
10 分钟后超时，**没有任何错误信息**。`ui_test.dart` 的 `_makeState()` 和异步保存按钮辅助方法就是这么写的。
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
| 单元/界面测试 | `tool\flutter-msvc.bat test` | 205/205 通过 |
| Android 原生测试 | `gradlew :app:testDebugUnitTest` | 3/3 通过；覆盖安装会话回调状态分类 |
| Windows Release | `tool\flutter-msvc.bat build windows --release` | `1.2.7+12` 构建成功；PE 文件/产品版本均为 `1.2.7+12`；Release 目录 22 个文件、31,800,888 字节 |
| Windows Setup | Inno Setup 6.7.3 编译 + PE/版本/哈希检查 | 11,364,751 字节；产品版本 `1.2.7`；SHA-256 `5EDD8814E3944FF92B52B983BC96DAA788E3E91EFB2DF6B01FDE932E9A7F2D3F` |
| Windows Release 校历视觉复核 | 真实 `desktile.exe` + `--calendar-preview` 演示数据 + `PrintWindow` | 校历概览、事件列表、长日期、停课统计和编辑器均无重叠；周视图正确标记校历停课；截图：`docs/screenshots/Windows发布-学期校历-{宽屏,编辑器}.png`、`Windows发布-v1.2.7-视觉核验-课表.png`；核验后按 SHA-256 恢复原用户数据 |
| Windows Release 今天页视觉复核 | 真实 `desktile.exe` + `PrintWindow`；DPI 175% 下逻辑宽度 320/360/800 | 课程、截止事项、逾期事项、近期考试、导航和文字换行均正常，无重叠或 `RenderFlex` 溢出；截图：`docs/screenshots/Windows发布-今天页-{320,360,800}宽.png` |
| Windows Release 多课表视觉复核 | 同一 Release 程序；两张课表；逻辑宽度 320/360/800 | 管理弹窗、新建/复制按钮、课表名称、学期日期、课程数和操作菜单均在容器内，长文本按预期换行或省略；截图：`docs/screenshots/Windows发布-多课表管理-{320,360,800}宽.png` |
| Windows Release 待办提醒视觉复核 | 同一 Release 程序；含逾期/今天/接下来/无截止日期临时数据；逻辑宽度 320/360/800 | 列表分组、长标题、课程关联、截止/提醒时间、重要标记、操作菜单和新增事项编辑器均无裁切、遮挡或重叠；截图：`docs/screenshots/Windows发布-待办提醒-{320,360,800}宽.png`、`Windows发布-待办编辑器-{320,360,800}宽.png`；检查后已按 SHA-256 恢复原用户数据 |
| 主窗口渲染 | 灌示例数据后实机运行，`PrintWindow` 抓窗口 | 见 `docs/screenshots/主窗口-周视图.png` |
| 挂件渲染 | 同上 | 见 `docs/screenshots/桌面挂件.png` |
| 单双周（第 1 周） | 实机 + 界面测试 | 周二 1-2 节是线性代数（单周） |
| 单双周（第 2 周） | `--weeks-back 1` 重新灌数据后实机 | 线性代数消失、体育（双周）出现，见 `docs/screenshots/主窗口-第2周双周.png` |
| 提醒排定 | 示例课表启动日志 | 「已排定 2 条」＝周一、周四的 08:00 第一节（其余日子第一节晚于 09:00，符合早八规则） |
| 提醒被系统接收 | `pendingNotificationRequests()` | 「系统里待触发 2 条」 |
| 跨进程同步 | 外部改写 JSON 里的课名，前后各抓一次挂件窗口对比 | ~1 秒内挂件文字跟着变，见 `docs/screenshots/跨进程同步-前后对比.png`（上=改前，下=改后） |
| CSES 导出正确性 | 导出后用官方 `cses.schema.json`（draft-07）+ `jsonschema` 校验 | PASS；`docs/示例课表.cses.yaml` 也 PASS |
| CSES 往返 | `cses_test.dart` | 导出再导入，星期/周次/节次数量一致 |
| Android Debug 构建 | 专用 `GRADLE_USER_HOME` + `flutter build apk --debug` | 成功，APK 约 180 MB，可覆盖安装到 API 36 模拟器 |
| Android Release 签名 | `flutter build apk --release` + `aapt` / `apksigner` | APK 60,110,686 字节（Flutter 显示约 57.3 MB），`1.2.7+12`、target API 36、APK v2 通过；SHA-256 `4032DF79FEA31EA53A7200CEDBFB3B0FE87177E41DABA64A88A6A2B9CEF5AB02` |
| Android AAB | `flutter build appbundle --release` + `jarsigner -verify` | AAB 58,135,384 字节，签名通过；SHA-256 `6F7469F4D36C9A588AB8AC59F462B22235B18B37C758C83FBFE3DD50821E9275` |
| Android 升级签名连续性 | `apksigner verify --print-certs` 对比旧版与本地 `v1.2.7` APK | 证书 SHA-256 仍为 `6cf11122888df80a18ad75851ed12b280275addfad9a06820403a630c78f7b0c`，允许覆盖安装 |
| GitHub Release 远端资产 | 下载 `v1.2.6` Release 后与两份 SHA256 校验文件逐项比对 | APK 59,667,798 字节 / `726e03a5690f9f7f73b7be5cc8e27d3fe23cc47ce076259beaa0725a9b2018dc`；AAB 57,844,563 字节 / `65b8284e70f5171427a971eff0af20e21d357851ae4f8bcc84bc85e8c868f689`；Windows Setup 11,332,118 字节 / `48bb27e7119aa89c076d5cc1faa3821ccf6c5f57b9c5237b1092ea755d6b5b71`；APK v2、AAB 签名验证通过 |
| GitHub Actions | 标签 `v1.2.6` 触发 `.github/workflows/android-release.yml` / `windows-release.yml` | Android Run `33309544980`、Windows Run `33309544972` 均 `completed / success`；Release 为公开正式版（非 draft、非 prerelease） |
| 正式应用图标 | SVG 母版 + Android adaptive/monochrome/legacy + Windows ICO | 已替换 Flutter 默认图标；通知使用独立单色小图标 |
| Android 手机布局 | Pixel 6 API 36 竖屏 + widget tests | 底部导航、安全区、课表双指缩放/平移、窄屏编辑器均无溢出；见 `docs/screenshots/Android-主界面.png` |
| Glance 小组件 | Pixel Launcher 添加组件并修改课程 | Provider/实例正常；`RefreshTest / A101` 保存后约 300ms 即时更新，见 `Android-小组件*.png` |
| Android 测试提醒 | 设置页“10 秒后测试提醒” + 通知中心 | 修复 `invalid_icon` 后通知成功发布；Release 资源表保留 `drawable/ic_notification`，见 `Android-10秒提醒-修复验证.png` |
| 本地时区排定 | 读取插件缓存 | `scheduledDateTime=2026-08-24T07:30:00`，`timeZoneName=Asia/Shanghai` |
| Android 重启恢复 | 有未触发提醒时重启模拟器，不先打开 App | receiver 恢复同一绝对时刻；Glance 实例和 v2 周期任务保留，WorkManager `successful_finish` |
| 后台可靠性入口 | 设置页点击“打开应用详情” | 前台切到 `com.android.settings/.spa.SpaActivity`，标题为“DeskTile 课表岛”；见 `Android-后台可靠性.png` |

**已知缺陷 1 项**：

**Windows Toast 在 Windows 11 26200 上弹窗失效** — 2026-08-22 完整排查结果：
- 应用层正确：`scheduleTest()` 返回 true，`pendingCount` 正确递增，AUMID 已注册（`HKCU\...\AppUserModelId\DeskTile.KeBiaoDao.Desktop` 下 DisplayName / IconUri / CustomActivator 都在）
- 系统层正常：通知主开关已开（`ToastEnabled=1`），应用通知权限已开，焦点助手未启用，`WpnService` / `WpnUserService` 都在运行
- **但通知到时间后不弹出，通知中心（Win+N）也无历史记录**
- 推测原因：flutter_local_notifications_windows 3.1.1 与 Windows 11 Insider 预览版 26200 的兼容性问题，或 COM 激活器（CLSID `{4d1b2f80-...}`）注册不完整
- **其他 Windows 10/11 稳定版用户可能不受影响**；如需修复，考虑降级插件到 17.x 或换用 win_toast

**未能实测的 1 项**（不影响交付）：

**选文件的原生对话框**（`FilePicker.pickFile`）。它后面的解析 → 预览 → 覆盖落盘全链路有测试覆盖（`showImportPreview` 就是为此特意公开出来的），只有弹窗本身没截图。

---

## 9. 已知限制与坑

- **挂件和主窗口不能同时显示同一份"实时"编辑**：主窗口保存后挂件约 1 秒后刷新（300ms 防抖 + 重读）。不是 bug，是双进程方案的固有延迟。
- **两个进程各占约 120MB 内存**，都开着约 240MB。Flutter 桌面的常态。
- **挂件是 `alwaysOnBottom`**，所以任何全屏程序都会盖住它 —— 这是「贴桌面」的设计意图，不是故障。
- **提醒依赖挂件进程常驻**（或主窗口开着）。Windows 计划 Toast 由系统触发，但排定动作需要应用跑一次；所以「开机自启挂件」这个开关对提醒的可靠性很关键。
- **Android 模拟器不能代表国产 ROM 的后台策略**：receiver、WorkManager 和闹钟链路已验证，
  但杀后台、自启动白名单和省电限制仍必须在至少一台真实手机上验证。
- **Android 签名文件只存在本机且被 Git 忽略**：首次发布前必须按
  `android/签名说明.md` 备份 keystore 和 `key.properties`；丢失可能导致无法更新已发布应用。
- **Windows Setup 尚未配置 Authenticode 签名**：线上更新会校验 GitHub 资产 SHA-256，
  但首次运行仍可能触发 SmartScreen；大规模分发前应配置代码签名证书。
- Android 30 分钟刷新由 WorkManager/launcher 调度，只保证最终执行，不保证精确到分钟；
  课程保存时的前台即时刷新不受此限制。
- **CSES 表达能力有限**：周日的课导不出去，非每周/单双周的周次会被跳过。这是格式本身的限制，代码里已经明确报错/警告而不是静默错。
- **ICS 的节次是推算的**，一段可能对应现实里连续两节；导入后建议去设置里核对节次时间表。
- **`docs/` 下的示例文件同时是测试 fixture**，改了要同步改断言。
- **`tool/*.bat` 必须纯 ASCII**（GBK 控制台会把 UTF-8 中文注释解析炸）。
- **`Runner.rc` 里的 CompanyName/ProductName 决定数据目录**，改了等于换存档位置。
- `windows/flutter/ephemeral/.plugin_symlinks` 是构建产物，删了跑一次 `pub get` 会重建（前提是开发者模式开着）。

---

## 10. Phase 2：Android 完成状态

Phase 2 已于 2026-08-22 完成。Android 与 Windows 共用领域层、
数据文件和主界面页面；仅启动序列、系统通知、后台任务与小组件桥按平台分流。

### 10.1 工具链

| 组件 | 版本 / 状态 |
|---|---|
| JDK | Temurin 24.0.1，`D:\ssoftware\JAVA24` |
| Gradle / AGP / Kotlin | 9.3.1 / 9.1.0 / 2.4.0；字节码目标 JVM 17 |
| Android SDK | API 35、36；Build Tools 36.0.0、36.1.0 |
| 原生工具 | NDK 28.2.13676358、CMake 3.22.1、Platform Tools 37.0.1 |
| 模拟器 | `DeskTile_API36`，Pixel 6，Android 16 / API 36，Google APIs x86_64 |

Flutter 3.47.1 的模板要求 compile/target SDK 36、min SDK 24、NDK 28.2.13676358。
新 Android CLI 认为 license 已无需单独接受，但 Flutter doctor 仍显示
`Android license status unknown`；这是工具兼容提示，不是构建阻断。

Android 构建必须使用 §1.3 的四个环境变量，尤其是专用
`GRADLE_USER_HOME=C:\Users\awxds\.gradle-desktile`。全局 Gradle init 脚本会破坏构建。

### 10.2 已落地的依赖与原生层

新增依赖为 `home_widget 0.9.3`、`flutter_timezone 5.0.1`、`workmanager ^0.10.9`；
Android app 显式依赖 `androidx.glance:glance-appwidget:1.1.1`、Compose 插件和
`desugar_jdk_libs 2.1.4`。Manifest 已补齐通知、精准闹钟、开机恢复、小组件 receiver；
应用正式标签为 `DeskTile 课表岛`，应用 ID 固定为 `com.desktile.desktile`。

原生新增：

- `DeskTileGlanceWidget.kt` / `DeskTileWidgetReceiver.kt`：Glance 渲染与 launcher 入口
- `desktile_widget_info.xml` / `desktile_widget_loading.xml`：尺寸、30 分钟周期和初始布局
- `MainActivity.kt` MethodChannel：打开 `ACTION_APPLICATION_DETAILS_SETTINGS`
- `assets/课表岛图标.svg`：正式图标母版；Android 自适应/主题/传统图标和 Windows ICO 均由此生成
- `drawable/ic_notification.xml`：Android 状态栏专用单色通知图标

### 10.3 Dart 与后台链路

- `main.dart` 在任何 Windows 插件初始化前先分流 Android，避免托盘、窗口、单实例代码误调用
- `widget_payload.dart` + `android_widget.dart` 负责 payload 计算、保存、刷新与请求固定到主屏
- `android_background.dart` 注册两个周期任务：小组件每 30 分钟、提醒每天本地 00:05
- 提醒通过 `flutter_timezone` 使用设备 IANA 时区，调度模式为 `exactAllowWhileIdle`
- 权限策略只响应明确的用户动作；普通设置修改不会重复弹通知或精准闹钟权限
- 设置页的“后台可靠性”说明国产 ROM 风险，并可跳到系统应用详情页

### 10.4 已完成的模拟器验收

API 36 的 `DeskTile_API36` 已验证：

1. Glance 小组件可添加到 Pixel Launcher，课程保存后约 300ms 即时刷新
2. 10 秒测试提醒成功发布，精准闹钟 AppOp 为 `allow`；通知图标使用裸资源名
   `ic_notification`，并由 `res/raw/keep.xml` 防止 Release 资源收缩器裁掉
3. 排定缓存明确记录 `Asia/Shanghai` 与本地 `2026-08-24T07:30:00`
4. 模拟器重启后不打开应用，BootReceiver 仍恢复同一个绝对提醒时刻
5. v2 周期任务和 Glance 实例跨重启保留，WorkManager 最终成功完成
6. “打开应用详情”进入 `com.android.settings/.spa.SpaActivity`

设备重启期间系统曾临时回到 GMT，闹钟显示为 `2026-08-23 23:30`，与上海
次日 `07:30` 正好相差 8 小时，说明保存的是正确绝对时刻，没有墙上时间漂移。

### 10.5 发布前仍要完成

- 至少在一台国产 ROM 真机验证通知权限、精准闹钟、锁屏待机、重启、自启动白名单与省电限制
- 按 `android/签名说明.md` 将 keystore 与口令文件备份到至少两个加密位置
- 发布新版本时必须递增 `pubspec.yaml` 的 version/build number、沿用同一 Android 签名密钥；双端用户均可在“设置 → 应用更新”原地升级
- `.github/workflows/android-release.yml` 与 `windows-release.yml` 均以标签为入口，并共用串行发布组；Android 首次需设置 `ANDROID_KEYSTORE_BASE64`、`ANDROID_KEYSTORE_PASSWORD`、`ANDROID_KEY_ALIAS`、`ANDROID_KEY_PASSWORD` 四个 Actions Secrets
- 后续发布只需提交版本变更并推送对应的 `vX.Y.Z` 标签，工作流会上传 APK、AAB、Windows x64 Setup 与各自 SHA-256 文件
- 首次上架时确定是否启用 Play App Signing；当前 RSA 4096 密钥可作为 upload key
- 根据后续发布渠道决定是否拆分 ABI，以及是否缩减约 180 MB 的通用 Debug APK
- 从 1024px 正式母版继续制作 Play 商店展示图、功能横幅和隐私政策页面
- Flutter 构建会提示未来迁移 Built-in Kotlin；当前由 Flutter 模板和插件产生，不影响本次构建

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
| Android 构建报 repositories mode / 仓库策略错误 | 没设置专用 `GRADLE_USER_HOME=C:\Users\awxds\.gradle-desktile`，误用了全局 `.gradle\init.gradle`。见 §1.2 ④ |
| `flutter doctor` 报 `Android license status unknown` | 新 Android CLI 与 Flutter 3.47.1 检测不兼容；本机 APK 已能构建。不要把它误判成 Phase 2 阻断 |
| `adb` 偶发找不到或连错设备 | 本机有两份 adb；固定使用 `D:\dev\android-sdk\platform-tools\adb.exe` |
| 测试挂死 10 分钟后超时、无错误信息 | `testWidgets` 里做了真实 IO 没包 `runAsync`。见 §7.2 ① |
| 测试报 `RenderFlex overflowed` 但真机正常 | 测试字体行高差异。见 §7.2 ② |
| **提醒不弹** | **① 先在设置页点「10 秒后测试提醒」，观察按钮下方有没有闪过 SnackBar 提示** ② 如果没有提示或提示里有错误，看日志里的 `lastError` ③ 系统设置里「通知」总开关和本应用开关是否都开 ④ 焦点助手是否启用（Win+A 快捷中心右下角） ⑤ `Get-Service WpnService` 是否 Running ⑥ 如果上述都正常但仍不弹，已知 Windows 11 26200 上 flutter_local_notifications_windows 3.1.1 有兼容性问题（见 §8 已知缺陷），考虑降级插件或换用 win_toast |
| Android 提醒模拟器正常、真机失效 | 在设置页“后台可靠性”打开应用详情，允许后台运行；再按 ROM 设置自启动白名单、关闭不受控省电。见 §10.5 |
| Android 测试提醒报 `invalid_icon` | 初始化参数必须是裸资源名 `ic_notification`，不能写 `@drawable/ic_notification`；同时确认 `res/raw/keep.xml` 保留该 drawable。 |
| Android 更新提示“打开目标文件夹失败” | `v1.1.2`～`v1.2.2` 的 `ACTION_VIEW` 回退被部分 ROM 文件管理器接管，但文件管理器不能浏览应用私有缓存。手动安装一次 `v1.2.3`；此版本起改用 `PackageInstaller Session`。 |
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
- home_widget：https://pub.dev/packages/home_widget
- workmanager：https://pub.dev/packages/workmanager
- flutter_timezone：https://pub.dev/packages/flutter_timezone
