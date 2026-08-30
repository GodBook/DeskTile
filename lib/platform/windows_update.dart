import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import 'release_update.dart';

const defaultWindowsVersion = '1.2.8';

enum WindowsInstallResult { started }

List<String> windowsInstallerArguments(String currentExecutable) {
  return [
    '/SP-',
    '/CLOSEAPPLICATIONS',
    '/NORESTART',
    '/DIR=${File(currentExecutable).parent.path}',
  ];
}

/// Windows 安装包更新服务。
///
/// 安装包由 Inno Setup 生成，启动后由安装器负责关闭当前程序并覆盖文件。
/// 安装器单独进程运行，因此主程序可以在启动后安全退出。
class WindowsUpdateService {
  WindowsUpdateService({
    http.Client? client,
    Uri? updateUri,
    Future<Directory> Function()? temporaryDirectory,
  }) : _releases = ReleaseUpdateService(
         packageType: ReleasePackageType.windowsInstaller,
         client: client,
         updateUri: updateUri,
         temporaryDirectory: temporaryDirectory,
       );

  final ReleaseUpdateService _releases;

  void dispose() => _releases.dispose();

  /// 从 Windows 文件版本读取当前版本，测试环境或旧包中读取失败时回退。
  Future<String> currentVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final version = info.version.trim();
      if (version.isNotEmpty) return version;
    } catch (_) {
      // Flutter 测试环境没有 Windows package_info 通道，使用构建时保底版本。
    }
    return defaultWindowsVersion;
  }

  Future<ReleaseUpdateCheckResult> checkForUpdate({
    String? currentVersion,
  }) async {
    return _releases.checkForUpdate(
      currentVersion: currentVersion ?? await this.currentVersion(),
    );
  }

  Future<DownloadedReleasePackage> download(
    ReleaseUpdateInfo info, {
    void Function(int receivedBytes, int? totalBytes)? onProgress,
  }) {
    return _releases.download(info, onProgress: onProgress);
  }

  Future<WindowsInstallResult> install(DownloadedReleasePackage package) async {
    if (!Platform.isWindows) {
      throw const ReleaseUpdateException('当前平台不支持 Windows 安装');
    }
    final installer = File(package.path);
    if (!await installer.exists()) {
      throw const ReleaseUpdateException('更新文件已失效，请重新下载');
    }
    try {
      final process = await Process.start(
        installer.path,
        windowsInstallerArguments(Platform.resolvedExecutable),
        mode: ProcessStartMode.detached,
      );
      if (process.pid <= 0) {
        throw const ReleaseUpdateException('无法启动 Windows 安装器');
      }
      return WindowsInstallResult.started;
    } on ProcessException {
      throw const ReleaseUpdateException('无法启动 Windows 安装器，请重试');
    } on IOException {
      throw const ReleaseUpdateException('无法启动 Windows 安装器，请重试');
    }
  }
}
