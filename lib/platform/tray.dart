import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../core/models/settings.dart';
import 'autostart.dart';
import 'single_instance.dart';

/// 托盘图标归挂件进程所有：挂件是常驻的那个，主窗口是随开随关的。
class WidgetTray with TrayListener {
  WidgetTray({
    required this.readSettings,
    required this.onSettingsChanged,
    required this.onQuit,
  });

  final AppSettings Function() readSettings;
  final Future<void> Function(AppSettings) onSettingsChanged;
  final Future<void> Function() onQuit;

  bool _widgetVisible = true;
  bool _autoStart = false;

  Future<void> init() async {
    trayManager.addListener(this);
    await trayManager.setIcon('assets/tray_icon.ico');
    await trayManager.setToolTip('DeskTile 课表岛');
    _autoStart = await AutoStart.isEnabled();
    await _rebuildMenu();
  }

  Future<void> dispose() async {
    trayManager.removeListener(this);
    await trayManager.destroy();
  }

  Future<void> refresh() async {
    _autoStart = await AutoStart.isEnabled();
    await _rebuildMenu();
  }

  Future<void> _rebuildMenu() async {
    final settings = readSettings();
    await trayManager.setContextMenu(Menu(items: [
      MenuItem(
        label: _widgetVisible ? '隐藏桌面挂件' : '显示桌面挂件',
        onClick: (_) => _toggleWidget(),
      ),
      MenuItem.checkbox(
        label: '迷你模式（只显示下一节）',
        checked: settings.widgetForm == WidgetForm.mini,
        onClick: (_) => _toggleMini(),
      ),
      MenuItem.checkbox(
        label: '贴在桌面上（不遮挡其它窗口）',
        checked: settings.widgetAlwaysOnBottom,
        onClick: (_) => _toggleOnBottom(),
      ),
      MenuItem.separator(),
      MenuItem(
        label: '打开主窗口…',
        onClick: (_) => ModeLauncher.openMainWindow(),
      ),
      MenuItem.checkbox(
        label: '开机自动启动',
        checked: _autoStart,
        onClick: (_) => _toggleAutoStart(),
      ),
      MenuItem.separator(),
      MenuItem(label: '退出 DeskTile', onClick: (_) => onQuit()),
    ]));
  }

  Future<void> _toggleWidget() async {
    _widgetVisible = !_widgetVisible;
    if (_widgetVisible) {
      await windowManager.show();
    } else {
      await windowManager.hide();
    }
    await _rebuildMenu();
  }

  Future<void> showWidget() async {
    _widgetVisible = true;
    await windowManager.show();
    await _rebuildMenu();
  }

  Future<void> _toggleMini() async {
    final s = readSettings();
    await onSettingsChanged(s.copyWith(
      widgetForm:
          s.widgetForm == WidgetForm.mini ? WidgetForm.standard : WidgetForm.mini,
    ));
    await _rebuildMenu();
  }

  Future<void> _toggleOnBottom() async {
    final s = readSettings();
    await onSettingsChanged(
        s.copyWith(widgetAlwaysOnBottom: !s.widgetAlwaysOnBottom));
    await _rebuildMenu();
  }

  Future<void> _toggleAutoStart() async {
    _autoStart = !_autoStart;
    await AutoStart.setEnabled(_autoStart);
    _autoStart = await AutoStart.isEnabled();
    await _rebuildMenu();
  }

  @override
  void onTrayIconMouseDown() {
    showWidget();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }
}
