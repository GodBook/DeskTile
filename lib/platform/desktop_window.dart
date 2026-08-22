import 'dart:io';
import 'dart:ui';

import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import '../core/models/settings.dart';

/// 挂件的两种尺寸。
const Size kWidgetStandardSize = Size(300, 400);
const Size kWidgetMiniSize = Size(300, 132);

Size widgetSizeFor(WidgetForm form) =>
    form == WidgetForm.mini ? kWidgetMiniSize : kWidgetStandardSize;

/// 主窗口：普通带边框窗口。
Future<void> setupMainWindow() async {
  await windowManager.ensureInitialized();
  const options = WindowOptions(
    size: Size(1080, 720),
    minimumSize: Size(860, 560),
    center: true,
    title: 'DeskTile 课表岛',
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });
}

/// 桌面挂件窗口：无边框、贴在桌面上、不占任务栏。
///
/// 没有用「真透明背景」——Flutter Windows 的透明窗口有已知的发黑问题。
/// 这里用不透明圆角卡片 + [WindowManager.setOpacity] 调整整体透明度，
/// 效果稳定得多。
Future<void> setupWidgetWindow(AppSettings settings, Offset? savedPosition) async {
  await windowManager.ensureInitialized();
  final size = widgetSizeFor(settings.widgetForm);
  final options = WindowOptions(
    size: size,
    skipTaskbar: true,
    titleBarStyle: TitleBarStyle.hidden,
    title: 'DeskTile 桌面挂件',
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.setAsFrameless();
    await windowManager.setResizable(false);
    await windowManager.setMinimizable(false);
    await windowManager.setSkipTaskbar(true);
    await windowManager.setPosition(
        savedPosition ?? await defaultWidgetPosition(size));
    await applyWidgetAppearance(settings);
    await windowManager.show();
  });
}

/// 设置变化后即时生效的那部分（透明度、层级、尺寸）。
Future<void> applyWidgetAppearance(AppSettings settings) async {
  await windowManager.setSize(widgetSizeFor(settings.widgetForm));
  await windowManager.setAlwaysOnBottom(settings.widgetAlwaysOnBottom);
  if (!settings.widgetAlwaysOnBottom) {
    await windowManager.setAlwaysOnTop(true);
  } else {
    await windowManager.setAlwaysOnTop(false);
  }
  await windowManager.setOpacity(settings.widgetOpacity.clamp(0.3, 1.0));
}

/// 没有记住过位置时，贴到主屏右下角。
Future<Offset> defaultWidgetPosition(Size size) async {
  try {
    final display = await screenRetriever.getPrimaryDisplay();
    final visible = display.visibleSize ?? display.size;
    return Offset(
      (visible.width - size.width - 24).clamp(0, double.infinity),
      (visible.height - size.height - 24).clamp(0, double.infinity),
    );
  } catch (_) {
    return const Offset(80, 80);
  }
}

/// 命令行里是否带了 --widget。
bool isWidgetMode(List<String> args) => args.contains('--widget');

/// 只有 Windows 才有桌面挂件这一套（Android 用原生小组件）。
bool get supportsDesktopWidget => Platform.isWindows;
