import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// 默认的更新源。发布到其它仓库或自建服务时，可在构建时通过
/// `--dart-define=DESKTILE_UPDATE_URL=https://...` 覆盖。
const defaultAndroidUpdateUrl = String.fromEnvironment(
  'DESKTILE_UPDATE_URL',
  defaultValue: 'https://api.github.com/repos/GodBook/DeskTile/releases/latest',
);

// 与 pubspec.yaml 保持同步，供测试环境或旧原生插件缺少版本通道时回退。
const defaultAndroidVersion = '1.1.1';

const _updateChannel = MethodChannel('com.desktile.desktile/app_update');
const _requestTimeout = Duration(seconds: 20);
const _maxApkBytes = 300 * 1024 * 1024;

/// Android 包版本信息。
class AndroidAppVersion {
  const AndroidAppVersion({required this.name, this.code});

  final String name;
  final int? code;
}

/// 可供安装的 Android 更新。
class AndroidUpdateInfo {
  const AndroidUpdateInfo({
    required this.version,
    required this.apkUrl,
    required this.releaseUrl,
    this.releaseTag,
    this.notes,
    this.sizeBytes,
  });

  /// 规范化后的版本号，例如 `1.2.0`。
  final String version;
  final Uri apkUrl;
  final Uri releaseUrl;
  final String? releaseTag;
  final String? notes;
  final int? sizeBytes;
}

/// 更新检查结果。没有更新时 [update] 为 null。
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

class AndroidDownloadedApk {
  const AndroidDownloadedApk({required this.path, required this.bytes});

  final String path;
  final int bytes;
}

enum AndroidInstallResult { started, permissionRequired }

/// 更新相关的可读错误，避免把底层 HTML/堆栈直接显示给用户。
class AndroidUpdateException implements Exception {
  const AndroidUpdateException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 检查、下载并启动 Android APK 原地升级。
///
/// HTTP 客户端和临时目录均可注入，因而版本解析和网络错误可以在无设备的
/// 单元测试中覆盖。真正的安装动作仍交给 Android 系统包安装器。
class AndroidUpdateService {
  AndroidUpdateService({
    http.Client? client,
    Uri? updateUri,
    Future<Directory> Function()? temporaryDirectory,
    MethodChannel? channel,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _updateUri = updateUri ?? Uri.parse(defaultAndroidUpdateUrl),
       _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory,
       _channel = channel ?? _updateChannel;

  final http.Client _client;
  final bool _ownsClient;
  final Uri _updateUri;
  final Future<Directory> Function() _temporaryDirectory;
  final MethodChannel _channel;

  void dispose() {
    if (_ownsClient) _client.close();
  }

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
      // 测试环境或旧版本原生代码可能没有该方法，使用构建时的保底版本。
    } on MissingPluginException {
      // 同上，不能因为版本展示失败而阻塞应用使用。
    }
    return const AndroidAppVersion(name: defaultAndroidVersion);
  }

  /// 查询最新稳定 Release。服务端返回旧版本时视为“已是最新”。
  Future<AndroidUpdateCheckResult> checkForUpdate({
    String? currentVersion,
  }) async {
    final current = (currentVersion?.trim().isNotEmpty ?? false)
        ? currentVersion!.trim()
        : (await currentAppVersion()).name;
    final currentParsed = AppVersion.tryParse(current);
    if (currentParsed == null) {
      throw const AndroidUpdateException('当前版本号格式无法识别');
    }
    _ensureHttps(_updateUri, '更新源');

    final request = http.Request('GET', _updateUri)
      ..headers.addAll(const {
        'Accept': 'application/vnd.github+json, application/json',
        'User-Agent': 'DeskTile-Android-Updater',
      });
    final response = await _send(request);
    final responseUrl = response.request?.url;
    if (responseUrl != null) _ensureHttps(responseUrl, '更新源');
    if (response.statusCode != HttpStatus.ok) {
      throw AndroidUpdateException('更新源暂时不可用（HTTP ${response.statusCode}）');
    }
    final body = await _readText(response);

    final decoded = _decodeJson(body);
    final parsed = _parseRelease(decoded);
    if (parsed == null) {
      throw const AndroidUpdateException('更新源没有可用的 Android APK');
    }

    final latestParsed = AppVersion.tryParse(parsed.version);
    if (latestParsed == null) {
      throw const AndroidUpdateException('更新版本号格式无法识别');
    }
    final isNewer = latestParsed.compareTo(currentParsed) > 0;
    return AndroidUpdateCheckResult(
      currentVersion: current,
      latestVersion: latestParsed.toString(),
      update: isNewer ? parsed : null,
    );
  }

  /// 将 APK 流式写入应用缓存目录。下载完成且文件看起来是 ZIP/APK 后才返回。
  Future<AndroidDownloadedApk> download(
    AndroidUpdateInfo info, {
    void Function(int receivedBytes, int? totalBytes)? onProgress,
  }) async {
    _ensureHttps(info.apkUrl, 'APK 下载地址');
    final base = await _temporaryDirectory();
    final updateDirectory = Directory(
      '${base.path}${Platform.pathSeparator}desktile_updates',
    );
    await updateDirectory.create(recursive: true);

    final target = File(
      '${updateDirectory.path}${Platform.pathSeparator}desktile-update.apk',
    );
    final partial = File('${target.path}.part');
    if (await partial.exists()) await partial.delete();

    final request = http.Request('GET', info.apkUrl)
      ..headers.addAll(const {
        'Accept':
            'application/octet-stream, application/vnd.android.package-archive',
        'User-Agent': 'DeskTile-Android-Updater',
      });
    final response = await _send(request);
    final responseUrl = response.request?.url;
    if (responseUrl != null) _ensureHttps(responseUrl, 'APK 下载地址');
    if (response.statusCode != HttpStatus.ok) {
      throw AndroidUpdateException('APK 下载失败（HTTP ${response.statusCode}）');
    }
    final contentLength = response.contentLength;
    final total = contentLength != null && contentLength > 0
        ? contentLength
        : null;
    if (total != null && total > _maxApkBytes) {
      throw const AndroidUpdateException('APK 文件过大，已停止下载');
    }

    var received = 0;
    IOSink? sink;
    try {
      sink = partial.openWrite();
      // 每个数据块都必须在限定时间内到达，避免弱网下永久占用更新界面。
      await for (final chunk in response.stream.timeout(_requestTimeout)) {
        received += chunk.length;
        if (received > _maxApkBytes) {
          throw const AndroidUpdateException('APK 文件过大，已停止下载');
        }
        sink.add(chunk);
        onProgress?.call(received, total);
      }
      await sink.flush();
      await sink.close();
      sink = null;

      if (received == 0 || (total != null && received != total)) {
        throw const AndroidUpdateException('APK 下载不完整，请重试');
      }
      if (!await _looksLikeApk(partial)) {
        throw const AndroidUpdateException('下载内容不是有效的 APK');
      }
      if (await target.exists()) await target.delete();
      final complete = await partial.rename(target.path);
      return AndroidDownloadedApk(path: complete.path, bytes: received);
    } catch (error) {
      if (sink != null) await sink.close();
      if (await partial.exists()) await partial.delete();
      if (error is TimeoutException) {
        throw const AndroidUpdateException('APK 下载超时，请检查网络后重试');
      }
      if (error is FileSystemException) {
        throw const AndroidUpdateException('无法保存 APK，请检查存储空间后重试');
      }
      if (error is IOException) {
        throw const AndroidUpdateException('APK 传输失败，请检查网络后重试');
      }
      if (error is http.ClientException) {
        throw AndroidUpdateException('APK 传输失败：${error.message}');
      }
      if (error is AndroidUpdateException) rethrow;
      throw AndroidUpdateException('APK 下载失败：$error');
    }
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
      throw AndroidUpdateException(error.message ?? '系统安装器启动失败');
    } on MissingPluginException {
      throw const AndroidUpdateException('当前 Android 版本不支持应用内更新');
    }
  }

  Future<http.StreamedResponse> _send(http.BaseRequest request) async {
    try {
      return await _client.send(request).timeout(_requestTimeout);
    } on TimeoutException {
      throw const AndroidUpdateException('网络请求超时，请检查网络后重试');
    } on SocketException {
      throw const AndroidUpdateException('无法连接更新服务器，请检查网络');
    } on IOException {
      throw const AndroidUpdateException('网络连接失败，请检查网络后重试');
    } on http.ClientException catch (error) {
      throw AndroidUpdateException('网络请求失败：${error.message}');
    }
  }

  Future<String> _readText(http.StreamedResponse response) async {
    try {
      return await response.stream.bytesToString().timeout(_requestTimeout);
    } on TimeoutException {
      throw const AndroidUpdateException('更新信息读取超时，请重试');
    } on SocketException {
      throw const AndroidUpdateException('更新信息读取失败，请检查网络');
    } on IOException {
      throw const AndroidUpdateException('更新信息读取失败，请检查网络');
    } on http.ClientException catch (error) {
      throw AndroidUpdateException('更新信息读取失败：${error.message}');
    } on FormatException {
      throw const AndroidUpdateException('更新信息编码无效，请稍后重试');
    }
  }
}

AndroidUpdateInfo? _parseRelease(Object? decoded) {
  if (decoded is List) {
    final releases = decoded
        .map(_parseRelease)
        .whereType<AndroidUpdateInfo>()
        .toList();
    releases.sort((a, b) {
      final left = AppVersion.tryParse(a.version);
      final right = AppVersion.tryParse(b.version);
      if (left == null || right == null) return 0;
      return right.compareTo(left);
    });
    return releases.isEmpty ? null : releases.first;
  }
  if (decoded is! Map) return null;
  final release = Map<Object?, Object?>.from(decoded);
  if (release['draft'] == true || release['prerelease'] == true) return null;
  final rawVersion = _firstString(release, const [
    'tag_name',
    'tagName',
    'version',
    'name',
  ]);
  final parsedVersion = rawVersion == null
      ? null
      : AppVersion.tryParse(rawVersion);
  if (parsedVersion == null) return null;

  final assets = release['assets'] ?? release['files'];
  final asset = _selectApkAsset(assets);
  final rawUrl =
      asset?['browser_download_url'] ??
      asset?['browserDownloadUrl'] ??
      asset?['download_url'] ??
      asset?['downloadUrl'] ??
      asset?['url'] ??
      release['apk_url'] ??
      release['apkUrl'] ??
      release['download_url'] ??
      release['downloadUrl'];
  final apkUrl = _parseHttpsUri(rawUrl);
  if (apkUrl == null) return null;

  final releaseUrl =
      _parseHttpsUri(
        release['html_url'] ??
            release['htmlUrl'] ??
            release['release_url'] ??
            release['releaseUrl'],
      ) ??
      apkUrl;
  final notes = _firstString(release, const [
    'body',
    'notes',
    'releaseNotes',
    'changelog',
    'description',
  ]);
  final size = _asInt(
    asset?['size'] ?? release['size'] ?? release['sizeBytes'],
  );
  return AndroidUpdateInfo(
    version: parsedVersion.toString(),
    apkUrl: apkUrl,
    releaseUrl: releaseUrl,
    releaseTag: rawVersion,
    notes: notes,
    sizeBytes: size,
  );
}

Map<Object?, Object?>? _selectApkAsset(Object? rawAssets) {
  if (rawAssets is! List) return null;
  final candidates = rawAssets
      .whereType<Map>()
      .map((asset) => Map<Object?, Object?>.from(asset))
      .where((asset) {
        final name = asset['name']?.toString().toLowerCase() ?? '';
        final url =
            asset['browser_download_url'] ??
            asset['browserDownloadUrl'] ??
            asset['download_url'] ??
            asset['downloadUrl'] ??
            asset['url'];
        return name.endsWith('.apk') && _parseHttpsUri(url) != null;
      })
      .toList();
  if (candidates.isEmpty) return null;

  int score(Map<Object?, Object?> asset) {
    final name = asset['name']?.toString().toLowerCase() ?? '';
    var value = 0;
    if (name.contains('android')) value += 30;
    if (name.contains('universal') || name.contains('all')) value += 20;
    if (name.contains('arm64')) value -= 5;
    if (name.contains('armeabi')) value -= 10;
    if (name.contains('x86')) value -= 10;
    return value;
  }

  candidates.sort((a, b) => score(b).compareTo(score(a)));
  return candidates.first;
}

Object? _decodeJson(String body) {
  try {
    return jsonDecode(body);
  } on FormatException {
    throw const AndroidUpdateException('更新服务器返回了无效数据');
  }
}

String? _firstString(Map<Object?, Object?> map, List<Object?> keys) {
  for (final key in keys) {
    final value = map[key]?.toString().trim();
    if (value != null && value.isNotEmpty) return value;
  }
  return null;
}

int? _asInt(Object? value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '');
}

Uri? _parseHttpsUri(Object? value) {
  if (value == null) return null;
  final uri = Uri.tryParse(value.toString());
  return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty
      ? uri
      : null;
}

void _ensureHttps(Uri uri, String label) {
  if (uri.scheme != 'https' || uri.host.isEmpty) {
    throw AndroidUpdateException('$label必须使用 HTTPS 地址');
  }
}

Future<bool> _looksLikeApk(File file) async {
  try {
    final bytes = await file
        .openRead(0, 4)
        .fold<List<int>>(<int>[], (all, chunk) => all..addAll(chunk));
    return bytes.length >= 4 &&
        bytes[0] == 0x50 &&
        bytes[1] == 0x4b &&
        (bytes[2] == 0x03 || bytes[2] == 0x05 || bytes[2] == 0x07) &&
        (bytes[3] == 0x04 || bytes[3] == 0x06 || bytes[3] == 0x08);
  } on FileSystemException {
    return false;
  }
}

/// 比较两个形如 `v1.2.3[-rc.1][+build]` 的版本号。
/// 返回值与 [Comparable.compareTo] 相同。
int compareAndroidVersions(String left, String right) {
  final a = AppVersion.tryParse(left);
  final b = AppVersion.tryParse(right);
  if (a == null || b == null) {
    throw const FormatException('版本号格式无法识别');
  }
  return a.compareTo(b);
}

class AppVersion implements Comparable<AppVersion> {
  const AppVersion(this.parts, this.preRelease);

  final List<int> parts;
  final List<String> preRelease;

  static AppVersion? tryParse(String raw) {
    var value = raw.trim();
    if (value.startsWith('v') || value.startsWith('V')) {
      value = value.substring(1);
    }
    value = value.split('+').first;
    final match = RegExp(
      r'^(\d+)(?:\.(\d+))?(?:\.(\d+))?(?:-([0-9A-Za-z.-]+))?$',
    ).firstMatch(value);
    if (match == null) return null;
    final parts = <int>[];
    for (var i = 1; i <= 3; i++) {
      final parsed = int.tryParse(match.group(i) ?? '0');
      if (parsed == null) return null;
      parts.add(parsed);
    }
    final pre = match.group(4);
    return AppVersion(parts, pre == null ? const [] : pre.split('.'));
  }

  @override
  int compareTo(AppVersion other) {
    for (var i = 0; i < parts.length; i++) {
      final result = parts[i].compareTo(other.parts[i]);
      if (result != 0) return result;
    }
    if (preRelease.isEmpty && other.preRelease.isNotEmpty) return 1;
    if (preRelease.isNotEmpty && other.preRelease.isEmpty) return -1;
    for (var i = 0; i < preRelease.length && i < other.preRelease.length; i++) {
      final left = preRelease[i];
      final right = other.preRelease[i];
      if (left == right) continue;
      final leftNumber = int.tryParse(left);
      final rightNumber = int.tryParse(right);
      if (leftNumber != null && rightNumber != null) {
        return leftNumber.compareTo(rightNumber);
      }
      if (leftNumber != null) return -1;
      if (rightNumber != null) return 1;
      return left.compareTo(right);
    }
    return preRelease.length.compareTo(other.preRelease.length);
  }

  @override
  String toString() {
    final base = parts.join('.');
    return preRelease.isEmpty ? base : '$base-${preRelease.join('.')}';
  }
}
