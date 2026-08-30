import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'release_update.dart';

const defaultAndroidUpdateUrl = defaultReleaseUpdateUrl;

// 与 pubspec.yaml 保持同步，供测试环境或旧版本原生通道缺失时回退。
const defaultAndroidVersion = '1.2.7';

const _updateChannel = MethodChannel('com.desktile.desktile/app_update');

typedef AndroidUpdateException = ReleaseUpdateException;

class AndroidUpdateInfo extends ReleaseUpdateInfo {
  const AndroidUpdateInfo({
    required super.version,
    required Uri apkUrl,
    required super.releaseUrl,
    super.releaseTag,
    super.notes,
    super.sizeBytes,
    super.sha256,
  }) : super(packageUrl: apkUrl);

  Uri get apkUrl => packageUrl;
}

class AndroidUpdateCheckResult {
  const AndroidUpdateCheckResult({
    required this.currentVersion,
    this.latestVersion,
    this.update,
  });

  final String currentVersion;
  final String? latestVersion;
  final AndroidUpdateInfo? update;

  bool get hasUpdate => update != null;
}

class AndroidDownloadedApk extends DownloadedReleasePackage {
  const AndroidDownloadedApk({required super.path, required super.bytes});
}

class AndroidAppVersion {
  const AndroidAppVersion({required this.name, this.code});

  final String name;
  final int? code;
}

enum AndroidInstallResult { started, permissionRequired }

/// 检查、下载并启动 Android APK 原地升级。
class AndroidUpdateService {
  AndroidUpdateService({
    http.Client? client,
    Uri? updateUri,
    Future<Directory> Function()? temporaryDirectory,
    MethodChannel? channel,
  }) : _releases = ReleaseUpdateService(
         packageType: ReleasePackageType.androidApk,
         client: client,
         updateUri: updateUri,
         temporaryDirectory: temporaryDirectory,
       ),
       _channel = channel ?? _updateChannel;

  final ReleaseUpdateService _releases;
  final MethodChannel _channel;

  void dispose() => _releases.dispose();

  /// 读取 Android Manifest 中由 Flutter 构建注入的 versionName。
  Future<AndroidAppVersion> currentAppVersion() async {
    try {
      final raw = await _channel.invokeMethod<Object?>('getAppVersion');
      if (raw is Map) {
        final name = raw['name']?.toString().trim();
        final code = _asInt(raw['code']);
        if (name != null && name.isNotEmpty) {
          return AndroidAppVersion(name: name, code: code);
        }
      } else if (raw is String && raw.trim().isNotEmpty) {
        return AndroidAppVersion(name: raw.trim());
      }
    } on PlatformException {
      // 旧版本原生代码或测试环境可能没有该方法，使用构建时保底版本。
    } on MissingPluginException {
      // 同上，版本展示失败不能阻塞应用使用。
    }
    return const AndroidAppVersion(name: defaultAndroidVersion);
  }

  Future<AndroidUpdateCheckResult> checkForUpdate({
    String? currentVersion,
  }) async {
    final current = (currentVersion?.trim().isNotEmpty ?? false)
        ? currentVersion!.trim()
        : (await currentAppVersion()).name;
    final result = await _releases.checkForUpdate(currentVersion: current);
    final update = result.update;
    return AndroidUpdateCheckResult(
      currentVersion: result.currentVersion,
      latestVersion: result.latestVersion,
      update: update == null
          ? null
          : AndroidUpdateInfo(
              version: update.version,
              apkUrl: update.packageUrl,
              releaseUrl: update.releaseUrl,
              releaseTag: update.releaseTag,
              notes: update.notes,
              sizeBytes: update.sizeBytes,
              sha256: update.sha256,
            ),
    );
  }

  Future<AndroidDownloadedApk> download(
    AndroidUpdateInfo info, {
    void Function(int receivedBytes, int? totalBytes)? onProgress,
  }) async {
    final downloaded = await _releases.download(info, onProgress: onProgress);
    return AndroidDownloadedApk(path: downloaded.path, bytes: downloaded.bytes);
  }

  /// 调起系统安装器。首次旁加载时会先打开“允许安装未知应用”设置。
  Future<AndroidInstallResult> install(AndroidDownloadedApk apk) async {
    if (!Platform.isAndroid) {
      throw const AndroidUpdateException('当前平台不支持 Android 安装');
    }
    try {
      final raw = await _channel.invokeMethod<Object?>('installApk', {
        'path': apk.path,
      });
      return switch (raw?.toString()) {
        'started' => AndroidInstallResult.started,
        'permission_required' => AndroidInstallResult.permissionRequired,
        _ => throw const AndroidUpdateException('系统没有启动安装器'),
      };
    } on PlatformException catch (error) {
      final message = switch (error.code) {
        'INSTALLER_START_FAILED' => '无法创建系统安装会话，请重新尝试更新',
        'APK_NOT_FOUND' => '更新文件已失效，请重新下载',
        'UNKNOWN_SOURCE_SETTINGS_FAILED' => '无法打开“安装未知应用”设置，请到系统设置中授权',
        _ => error.message ?? '系统安装器启动失败',
      };
      throw AndroidUpdateException(message);
    } on MissingPluginException {
      throw const AndroidUpdateException('当前 Android 版本不支持应用内更新');
    }
  }
}

int? _asInt(Object? value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '');
}

int compareAndroidVersions(String left, String right) =>
    compareAppVersions(left, right);
