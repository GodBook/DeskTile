# DeskTile 课表岛

跨 Windows 与 Android 的极简课程表。无广告、无账号、纯本地，冷启动即用。

**当前开发版本：v1.2.2**（现行稳定版为 v1.1.2）。Windows 桌面挂件与 Android
手机界面、Glance 主屏小组件、精准课程提醒、双端线上更新及作业待办均已完成；170 个跨平台测试通过。

> 接手开发请先读 **[HANDOVER.md](HANDOVER.md)** —— 环境坑、架构决策、文件职责、
> 验证记录、Phase 2/3 落地步骤和排错手册都在那里。本文件只是使用向导。

截图见 [docs/screenshots/](docs/screenshots/)。

## 下载

当前稳定版前往 [v1.1.2 Release](https://github.com/GodBook/DeskTile/releases/tag/v1.1.2)：

- `DeskTile-v1.1.2-android.apk`：Android 安装包
- `DeskTile-v1.1.2-android.aab`：应用商店上传包，不能直接安装
- `DeskTile-v1.1.2-SHA256SUMS.txt`：安装包 SHA-256 校验值

从 v1.2.1 起，同一 Release 还会提供
`DeskTile-v<版本>-windows-x64-setup.exe` Windows 安装包及独立 SHA-256 文件。

## 已实现（Windows）

- **周视图**：节次时间轴 + 周一~周日，今天所在列高亮，课程块按课名稳定配色；
  支持 `Ctrl + 滚轮` 在 65%～250% 之间缩放课表
- **单双周**：周次是一个集合，「每周 / 单周 / 双周 / 自定义（1-8,10,12-16）」走同一条路径；
  顶栏可以逐周切换并显示当前是单周还是双周
- **临时调课 / 停课 / 补课**：打开某次常规课程可只调整当日安排；调课可改日期、节次和教室，
  停课保留灰色删除线标记；工具栏按钮或空白格右键可添加一次性补课，冲突会即时提示
- **桌面挂件**：无边框圆角卡片，贴在桌面上（不遮挡其它窗口），任意位置拖动、位置记忆，
  托盘常驻。显示「第 N 周 · 周几 · 单/双周 → 下一节（课名 + **教室** + 倒计时）→ 今日课程 →
  最近考试倒计时」，另有只显示下一节的迷你形态
- **早八教室提醒**：每天第一节课前 N 分钟弹 Windows 通知，正文必带教室；
  可切换成「每节课都提醒」；「早八」判定阈值可调（拉到 24:00 就等于每天第一节都提醒）
- **考试倒计时**：科目 / 时间 / 考场 / 座位，按开考时间排序，考完的自动折叠
- **作业与待办**：支持课程关联、重要标记、截止日期与时间、备注、完成/恢复、编辑和删除；
  自动按逾期、今天、接下来、无截止日期和已完成分组
- **导入**：CSV、CSES v2 YAML、ICS、小爱课程表 `courseInfos` JSON，导入前先给解析预览和警告
- **导出**：CSES v2 YAML（可被 ClassIsland 等读取）、完整备份 JSON；备份包含作业与待办
- **开机自启**：写 `HKCU\...\CurrentVersion\Run`，启动的是挂件模式，不需要管理员权限
- **线上更新**：设置 → 应用更新可检查稳定版、显示发布说明、流式下载安装包并启动覆盖安装；
  主窗口和挂件会由安装器关闭，课表数据仍保留在 `%APPDATA%`

Windows 更新要求 Release 中包含 x64 Setup `.exe`，推荐命名为
`DeskTile-v<版本>-windows-x64-setup.exe`。应用内启动时安装器覆盖当前程序目录；从发布页首次运行时，
默认安装到当前用户的 `%LOCALAPPDATA%\Programs\DeskTile`，两种方式都不要求管理员权限。
当前自动构建的安装包没有 Authenticode 代码签名，首次运行可能触发 SmartScreen；正式大规模分发前应配置证书签名。
自建更新服务可通过 `--dart-define=DESKTILE_UPDATE_URL=https://你的更新服务地址` 注入；
Windows 响应至少包含 `version`/`tag_name` 与 `windows_url`/`installer_url`，也可直接返回
GitHub Release 的 `assets` 结构。所有更新元数据和安装包地址都必须使用 HTTPS。
GitHub 返回资产 SHA-256 digest 时，客户端会在启动安装器前自动校验，摘要不一致的文件会被删除。

## 已实现（Android）

- **手机界面**：底部五栏导航、系统安全区适配、课表双指缩放与平移、320px 窄屏编辑器
- **作业与待办**：与 Windows 共用数据和界面，支持课程关联、重要程度、截止时间、分组筛选及完成状态
- **临时调课 / 停课 / 补课**：与 Windows 共用数据和编辑器；长按空白格可直接添加补课，
  临时安排会同步影响提醒和主屏小组件
- **主屏小组件**：Jetpack Glance 展示周次、下一节、教室、今日剩余和最近考试
- **即时刷新**：课程保存后约 300ms 更新小组件，后台每 30 分钟刷新
- **精准提醒**：设备 IANA 时区、精准闹钟、锁屏待机调度，通知正文包含教室
- **系统恢复**：重启后恢复通知计划、WorkManager 周期任务和 Glance 实例
- **后台引导**：设置页可直达应用详情，便于国产 ROM 配置自启动和省电白名单
- **线上更新**：设置 → 应用更新可检查 GitHub Release，下载 Android APK 后调用系统安装器原地升级，课表数据不会丢失

应用内更新要求新 APK 与当前安装包使用相同的 `applicationId`（`com.desktile.desktile`）和
发布签名密钥，并且 Release 中包含 `.apk` 资产（推荐命名为
`DeskTile-v<版本>-android.apk`）。如果更新源不是本仓库，可在构建时传入
`--dart-define=DESKTILE_UPDATE_URL=https://你的更新服务地址`；服务返回 GitHub Release
格式的 JSON，或至少包含 `version`/`tag_name` 与 `apk_url`/`download_url`。首次安装更新时，
Android 可能要求在系统设置中允许 DeskTile 安装未知应用，授权后回到设置页继续安装即可。
当前仓库已公开，默认 GitHub 更新接口可直接对安装用户提供服务；如果改用私有仓库，
请改用无需登录的更新服务或静态镜像。
这条链路面向 GitHub/APK 直装分发；若以后只通过 Google Play 发布，应改用 Play 的应用内更新接口，
不要继续依赖“未知来源安装”权限。
`v1.1.2` 已包含课表双指缩放和应用内更新功能，并兼容未注册
`ACTION_INSTALL_PACKAGE` 的 Android 系统；后续版本沿用同一更新链路。

## 运行与构建

### Windows

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

生成可供线上更新使用的 Inno Setup 安装包（需先安装 Inno Setup 6）：

```powershell
& "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe" /DAppVersion=1.2.2 installer\DeskTile.iss
```

产物：`dist\DeskTile-v1.2.2-windows-x64-setup.exe`

两种运行模式（同一个 exe）：

```bash
desktile.exe            # 主窗口：编辑课表、导入导出、设置
desktile.exe --widget   # 桌面挂件 + 托盘，常驻，负责排提醒
```

Flutter stable 目前不支持多窗口，所以两者是两个进程：主窗口是唯一的写入方，
挂件只读并用 `Directory.watch` 监听数据文件变化，1 秒内自动刷新。
每种模式各自绑定一个回环端口（45677 / 45678）当互斥锁，重复启动会把已有窗口叫到前面。

### Android

Android Release 必须配置 `android/key.properties` 与对应 keystore，模板和说明见
[`android/key.properties.example`](android/key.properties.example) 与
[`android/签名说明.md`](android/签名说明.md)。本机验证命令：

```powershell
$env:JAVA_HOME='D:\ssoftware\JAVA24'
$env:ANDROID_HOME='D:\dev\android-sdk'
$env:ANDROID_SDK_ROOT='D:\dev\android-sdk'
$env:GRADLE_USER_HOME='C:\Users\awxds\.gradle-desktile'
D:\dev\flutter\bin\flutter.bat build apk --release
D:\dev\flutter\bin\flutter.bat build appbundle --release
```

### 跨平台自动发布

仓库中的 `.github/workflows/android-release.yml` 与 `.github/workflows/windows-release.yml`
会在推送匹配 `v*` 的 Git 标签时自动运行：先校验标签与 `pubspec.yaml` 版本一致，再执行测试、
构建并更新同一个 GitHub Release。两个工作流共用串行发布组，不会同时创建 Release。

首次使用前，在仓库 Settings → Secrets and variables → Actions 中配置以下 Secrets：

- `ANDROID_KEYSTORE_BASE64`：`android/keystore/desktile-release.jks` 的 Base64 内容
- `ANDROID_KEYSTORE_PASSWORD`：keystore 口令
- `ANDROID_KEY_ALIAS`：密钥别名（当前为 `desktile`）
- `ANDROID_KEY_PASSWORD`：密钥口令

以后每新增一个独立功能，补丁版本与构建号都各递增 1；修复可按发布需要单独递增。
提交后执行：

```powershell
git tag v1.2.2
git push origin master
git push origin v1.2.2
```

工作流会上传 APK、AAB、Windows x64 Setup 和校验文件；客户端只选择本平台的安装包。
Windows 工作流目前生成未签名安装器，不需要额外 Secret；Android 工作流仍依赖上面的四个签名 Secret。

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
| `.json` | 小爱课程表的 `{"courseInfos":[...]}` 结构（`sections` 支持 `[{section:1}]` 和 `[1]` 两种写法），或本程序导出的完整备份；DeskTile 备份会保留临时调课、停课、补课、作业待办和内部关联 ID |

导入是**整表覆盖**当前课表，确认前会先显示解析到多少门课、多少个时段以及全部警告。
CSES/CSV/ICS 本身无法完整表达单次课程变更；需要跨端迁移临时安排时请使用 JSON 备份。

## 目录结构

```
lib/
├─ core/                 纯 Dart，不依赖 Flutter，测试全覆盖
│  ├─ models/            Timetable / Course / CourseSession / ScheduleChange / TaskItem / Exam / TimeSlot / AppSettings
│  ├─ week_math.dart     学期周次换算（UTC 归一化，不受时区影响）
│  ├─ weeks_parser.dart  周次串解析与格式化（导入与未来教务解析共用）
│  ├─ agenda.dart        应用临时变更后的实际日程、下一节、今日剩余
│  ├─ reminder_plan.dart 提醒计划（决定性 id + 含教室的正文）
│  ├─ exam_countdown.dart
│  ├─ task_query.dart    作业待办分组、排序与最近截止查询
│  └─ import/            course_info_dto / csv / cses / ics / json / exporter
├─ data/                 app_data（纯数据）、store（原子 JSON 读写 + 文件监听）、app_state
├─ platform/             Windows 窗口/托盘与 Android 后台任务/小组件桥
└─ ui/                   主窗口与挂件

tool/
├─ flutter-msvc.bat      带 ucrt 修补的 flutter 包装
└─ seed_demo_data.dart   用真实导入代码灌示例数据，验证界面用
```

没有引入状态管理库和 SQLite：一个 `ChangeNotifier` + `InheritedNotifier` 够用，
课表数据只有几百行，单 JSON 文件更适合备份和跨端搬运（`sqlite3_flutter_libs` 也已 EOL）。

## 验证情况

已实测通过：

- `flutter analyze` 无任何问题；`flutter test` 170 个测试全绿
- Release 构建成功，主窗口与挂件都实际运行并截图确认
- Android 正式签名 APK/AAB 构建成功；API 36 模拟器完成通知、小组件、重启恢复验收
- 单双周：第 1 周显示单周课、第 2 周显示双周课，界面测试与真机截图双向确认
- 早八提醒：示例课表下启动即排定 2 条（周一、周四第一节 08:00），
  `pendingNotificationRequests` 确认系统已接收
- 跨进程同步：外部改写数据文件后挂件 ~1 秒内刷新
- 导出的 CSES YAML 通过官方 `cses.schema.json`（draft-07）校验

已知限制：

- **Windows 11 Insider 26200 上 Toast 不弹出**。应用排定和系统服务状态均正常，但通知中心
  没有记录，推测是通知插件与该预览版的兼容问题；Windows 10/11 稳定版可能不受影响。
- 国产 Android ROM 的杀后台、自启动白名单和省电限制仍需更多真机覆盖。

## 后续路线

- **Phase 3（教务系统直连）**：内嵌 WebView 登录 + 注入小爱课程表兼容的
  `scheduleHtmlProvider` / `scheduleHtmlParser`，产出的 `courseInfos` 直接走
  `core/import/course_info_dto.dart` 这条已经建好的通路，社区 `.js` 解析器可由用户粘贴导入。
