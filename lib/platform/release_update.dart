import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// 默认更新源。可在构建时通过 `DESKTILE_UPDATE_URL` 指向兼容的更新服务。
const defaultReleaseUpdateUrl = String.fromEnvironment(
  'DESKTILE_UPDATE_URL',
  defaultValue: 'https://api.github.com/repos/GodBook/DeskTile/releases/latest',
);

const _requestTimeout = Duration(seconds: 20);
const _maxMetadataBytes = 2 * 1024 * 1024;

enum ReleasePackageType { androidApk, windowsInstaller }

/// GitHub Release 中可供当前平台安装的包。
class ReleaseUpdateInfo {
  const ReleaseUpdateInfo({
    required this.version,
    required this.packageUrl,
    required this.releaseUrl,
    this.releaseTag,
    this.notes,
    this.sizeBytes,
    this.sha256,
  });

  final String version;
  final Uri packageUrl;
  final Uri releaseUrl;
  final String? releaseTag;
  final String? notes;
  final int? sizeBytes;
  final String? sha256;
}

class ReleaseUpdateCheckResult {
  const ReleaseUpdateCheckResult({
    required this.currentVersion,
    this.latestVersion,
    this.update,
  });

  final String currentVersion;
  final String? latestVersion;
  final ReleaseUpdateInfo? update;

  bool get hasUpdate => update != null;
}

class DownloadedReleasePackage {
  const DownloadedReleasePackage({required this.path, required this.bytes});

  final String path;
  final int bytes;
}

/// 更新相关的可读错误，避免把底层 HTML 或堆栈直接显示给用户。
class ReleaseUpdateException implements Exception {
  const ReleaseUpdateException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// GitHub Release 检查与安装包下载的跨平台实现。
///
/// 平台层只负责取得当前版本和启动系统安装器；网络约束、版本比较、资产选择、
/// 流式下载及临时文件清理由这里统一处理。
class ReleaseUpdateService {
  ReleaseUpdateService({
    required this.packageType,
    http.Client? client,
    Uri? updateUri,
    Future<Directory> Function()? temporaryDirectory,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _updateUri = updateUri ?? Uri.parse(defaultReleaseUpdateUrl),
       _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory;

  final ReleasePackageType packageType;
  final http.Client _client;
  final bool _ownsClient;
  final Uri _updateUri;
  final Future<Directory> Function() _temporaryDirectory;

  _PackageSpec get _spec => _PackageSpec.forType(packageType);

  void dispose() {
    if (_ownsClient) _client.close();
  }

  Future<ReleaseUpdateCheckResult> checkForUpdate({
    required String currentVersion,
  }) async {
    final current = currentVersion.trim();
    final currentParsed = AppVersion.tryParse(current);
    if (currentParsed == null) {
      throw const ReleaseUpdateException('当前版本号格式无法识别');
    }
    _ensureHttps(_updateUri, '更新源');

    final request = http.Request('GET', _updateUri)
      ..headers.addAll({
        'Accept': 'application/vnd.github+json, application/json',
        'User-Agent': _spec.userAgent,
      });
    final response = await _send(request);
    final responseUrl = response.request?.url;
    if (responseUrl != null) _ensureHttps(responseUrl, '更新源');
    if (response.statusCode != HttpStatus.ok) {
      throw ReleaseUpdateException('更新源暂时不可用（HTTP ${response.statusCode}）');
    }

    final body = await _readText(response);
    final parsed = _parseRelease(_decodeJson(body), _spec);
    if (parsed == null) {
      throw ReleaseUpdateException('更新源没有可用的${_spec.packageLabel}');
    }

    final latestParsed = AppVersion.tryParse(parsed.version);
    if (latestParsed == null) {
      throw const ReleaseUpdateException('更新版本号格式无法识别');
    }
    return ReleaseUpdateCheckResult(
      currentVersion: current,
      latestVersion: latestParsed.toString(),
      update: latestParsed.compareTo(currentParsed) > 0 ? parsed : null,
    );
  }

  /// 将安装包流式写入缓存目录，完整性检查通过后才去掉 `.part` 后缀。
  Future<DownloadedReleasePackage> download(
    ReleaseUpdateInfo info, {
    void Function(int receivedBytes, int? totalBytes)? onProgress,
  }) async {
    final spec = _spec;
    _ensureHttps(info.packageUrl, '${spec.packageLabel}下载地址');
    if (info.sizeBytes != null && info.sizeBytes! > spec.maxBytes) {
      throw ReleaseUpdateException('${spec.packageLabel}文件过大，已停止下载');
    }

    final base = await _temporaryDirectory();
    final updateDirectory = Directory(
      '${base.path}${Platform.pathSeparator}desktile_updates',
    );
    await updateDirectory.create(recursive: true);

    final target = File(
      '${updateDirectory.path}${Platform.pathSeparator}${spec.targetFileName}',
    );
    final partial = File('${target.path}.part');
    if (await partial.exists()) await partial.delete();

    final request = http.Request('GET', info.packageUrl)
      ..headers.addAll({
        'Accept': spec.acceptHeader,
        'User-Agent': spec.userAgent,
      });
    final response = await _send(request);
    final responseUrl = response.request?.url;
    if (responseUrl != null) {
      _ensureHttps(responseUrl, '${spec.packageLabel}下载地址');
    }
    if (response.statusCode != HttpStatus.ok) {
      throw ReleaseUpdateException(
        '${spec.packageLabel}下载失败（HTTP ${response.statusCode}）',
      );
    }

    final contentLength = response.contentLength;
    final total = contentLength != null && contentLength > 0
        ? contentLength
        : info.sizeBytes;
    if (total != null && total > spec.maxBytes) {
      throw ReleaseUpdateException('${spec.packageLabel}文件过大，已停止下载');
    }

    var received = 0;
    IOSink? sink;
    try {
      sink = partial.openWrite();
      await for (final chunk in response.stream.timeout(_requestTimeout)) {
        received += chunk.length;
        if (received > spec.maxBytes) {
          throw ReleaseUpdateException('${spec.packageLabel}文件过大，已停止下载');
        }
        sink.add(chunk);
        onProgress?.call(received, total);
      }
      await sink.flush();
      await sink.close();
      sink = null;

      if (received == 0 ||
          (contentLength != null && contentLength > 0 && received != total)) {
        throw ReleaseUpdateException('${spec.packageLabel}下载不完整，请重试');
      }
      if (!await spec.looksValid(partial)) {
        throw ReleaseUpdateException('下载内容不是有效的${spec.packageLabel}');
      }
      final expectedSha256 = info.sha256;
      if (expectedSha256 != null) {
        final actualSha256 = (await sha256.bind(partial.openRead()).first)
            .toString();
        if (actualSha256.toLowerCase() != expectedSha256.toLowerCase()) {
          throw ReleaseUpdateException('${spec.packageLabel}校验失败，请重新下载');
        }
      }
      if (await target.exists()) await target.delete();
      final complete = await partial.rename(target.path);
      return DownloadedReleasePackage(path: complete.path, bytes: received);
    } catch (error) {
      if (sink != null) await sink.close();
      if (await partial.exists()) await partial.delete();
      if (error is TimeoutException) {
        throw ReleaseUpdateException('${spec.packageLabel}下载超时，请检查网络后重试');
      }
      if (error is FileSystemException) {
        throw ReleaseUpdateException('无法保存${spec.packageLabel}，请检查存储空间后重试');
      }
      if (error is IOException) {
        throw ReleaseUpdateException('${spec.packageLabel}传输失败，请检查网络后重试');
      }
      if (error is http.ClientException) {
        throw ReleaseUpdateException(
          '${spec.packageLabel}传输失败：${error.message}',
        );
      }
      if (error is ReleaseUpdateException) rethrow;
      throw ReleaseUpdateException('${spec.packageLabel}下载失败：$error');
    }
  }

  Future<http.StreamedResponse> _send(http.BaseRequest request) async {
    try {
      return await _client.send(request).timeout(_requestTimeout);
    } on TimeoutException {
      throw const ReleaseUpdateException('网络请求超时，请检查网络后重试');
    } on SocketException {
      throw const ReleaseUpdateException('无法连接更新服务器，请检查网络');
    } on IOException {
      throw const ReleaseUpdateException('网络连接失败，请检查网络后重试');
    } on http.ClientException catch (error) {
      throw ReleaseUpdateException('网络请求失败：${error.message}');
    }
  }

  Future<String> _readText(http.StreamedResponse response) async {
    final declaredLength = response.contentLength;
    if (declaredLength != null && declaredLength > _maxMetadataBytes) {
      throw const ReleaseUpdateException('更新服务器返回的数据过大');
    }
    try {
      final bytes = <int>[];
      await for (final chunk in response.stream.timeout(_requestTimeout)) {
        bytes.addAll(chunk);
        if (bytes.length > _maxMetadataBytes) {
          throw const ReleaseUpdateException('更新服务器返回的数据过大');
        }
      }
      return utf8.decode(bytes);
    } on TimeoutException {
      throw const ReleaseUpdateException('更新信息读取超时，请重试');
    } on SocketException {
      throw const ReleaseUpdateException('更新信息读取失败，请检查网络');
    } on IOException {
      throw const ReleaseUpdateException('更新信息读取失败，请检查网络');
    } on http.ClientException catch (error) {
      throw ReleaseUpdateException('更新信息读取失败：${error.message}');
    } on FormatException {
      throw const ReleaseUpdateException('更新信息编码无效，请稍后重试');
    }
  }
}

class _PackageSpec {
  const _PackageSpec({
    required this.packageLabel,
    required this.targetFileName,
    required this.maxBytes,
    required this.acceptHeader,
    required this.userAgent,
    required this.directUrlKeys,
    required this.assetMatches,
    required this.assetScore,
    required this.looksValid,
  });

  final String packageLabel;
  final String targetFileName;
  final int maxBytes;
  final String acceptHeader;
  final String userAgent;
  final List<Object?> directUrlKeys;
  final bool Function(String name) assetMatches;
  final int Function(String name) assetScore;
  final Future<bool> Function(File file) looksValid;

  factory _PackageSpec.forType(ReleasePackageType type) {
    return switch (type) {
      ReleasePackageType.androidApk => _PackageSpec(
        packageLabel: 'Android APK',
        targetFileName: 'desktile-update.apk',
        maxBytes: 300 * 1024 * 1024,
        acceptHeader:
            'application/octet-stream, application/vnd.android.package-archive',
        userAgent: 'DeskTile-Android-Updater',
        directUrlKeys: const [
          'apk_url',
          'apkUrl',
          'download_url',
          'downloadUrl',
        ],
        assetMatches: (name) => name.endsWith('.apk'),
        assetScore: (name) {
          var value = 0;
          if (name.contains('android')) value += 30;
          if (name.contains('universal') || name.contains('all')) value += 20;
          if (name.contains('arm64')) value -= 5;
          if (name.contains('armeabi')) value -= 10;
          if (name.contains('x86')) value -= 10;
          return value;
        },
        looksValid: _looksLikeZip,
      ),
      ReleasePackageType.windowsInstaller => _PackageSpec(
        packageLabel: 'Windows 安装包',
        targetFileName: 'DeskTile-update-setup.exe',
        maxBytes: 500 * 1024 * 1024,
        acceptHeader: 'application/octet-stream, application/x-msdownload',
        userAgent: 'DeskTile-Windows-Updater',
        directUrlKeys: const [
          'windows_url',
          'windowsUrl',
          'installer_url',
          'installerUrl',
          'download_url',
          'downloadUrl',
        ],
        assetMatches: (name) {
          if (!name.endsWith('.exe')) return false;
          if (!name.contains('setup') && !name.contains('installer')) {
            return false;
          }
          if (name.contains('arm64')) return false;
          return !RegExp(r'(^|[-_.])x86($|[-_.])').hasMatch(name);
        },
        assetScore: (name) {
          var value = 0;
          if (name.contains('windows')) value += 30;
          if (name.contains('setup') || name.contains('installer')) value += 25;
          if (name.contains('x64') || name.contains('amd64')) value += 20;
          return value;
        },
        looksValid: _looksLikeWindowsExecutable,
      ),
    };
  }
}

ReleaseUpdateInfo? _parseRelease(Object? decoded, _PackageSpec spec) {
  if (decoded is List) {
    final releases = decoded
        .map((release) => _parseRelease(release, spec))
        .whereType<ReleaseUpdateInfo>()
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

  final asset = _selectAsset(release['assets'] ?? release['files'], spec);
  final rawUrl = asset == null
      ? _firstValue(release, spec.directUrlKeys)
      : _firstValue(asset, const [
          'browser_download_url',
          'browserDownloadUrl',
          'download_url',
          'downloadUrl',
          'url',
        ]);
  final packageUrl = _parseHttpsUri(rawUrl);
  if (packageUrl == null) return null;

  final releaseUrl =
      _parseHttpsUri(
        _firstValue(release, const [
          'html_url',
          'htmlUrl',
          'release_url',
          'releaseUrl',
        ]),
      ) ??
      packageUrl;
  return ReleaseUpdateInfo(
    version: parsedVersion.toString(),
    packageUrl: packageUrl,
    releaseUrl: releaseUrl,
    releaseTag: rawVersion,
    notes: _firstString(release, const [
      'body',
      'notes',
      'releaseNotes',
      'changelog',
      'description',
    ]),
    sizeBytes: _asInt(
      asset?['size'] ?? release['size'] ?? release['sizeBytes'],
    ),
    sha256: _parseSha256(
      asset?['digest'] ??
          asset?['sha256'] ??
          release['digest'] ??
          release['sha256'],
    ),
  );
}

Map<Object?, Object?>? _selectAsset(Object? rawAssets, _PackageSpec spec) {
  if (rawAssets is! List) return null;
  final candidates = rawAssets
      .whereType<Map>()
      .map((asset) => Map<Object?, Object?>.from(asset))
      .where((asset) {
        final name = asset['name']?.toString().toLowerCase() ?? '';
        final url = _firstValue(asset, const [
          'browser_download_url',
          'browserDownloadUrl',
          'download_url',
          'downloadUrl',
          'url',
        ]);
        return spec.assetMatches(name) && _parseHttpsUri(url) != null;
      })
      .toList();
  if (candidates.isEmpty) return null;
  candidates.sort((a, b) {
    final left = a['name']?.toString().toLowerCase() ?? '';
    final right = b['name']?.toString().toLowerCase() ?? '';
    return spec.assetScore(right).compareTo(spec.assetScore(left));
  });
  return candidates.first;
}

Object? _decodeJson(String body) {
  try {
    return jsonDecode(body);
  } on FormatException {
    throw const ReleaseUpdateException('更新服务器返回了无效数据');
  }
}

Object? _firstValue(Map<Object?, Object?> map, List<Object?> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value != null && value.toString().trim().isNotEmpty) return value;
  }
  return null;
}

String? _firstString(Map<Object?, Object?> map, List<Object?> keys) {
  return _firstValue(map, keys)?.toString().trim();
}

int? _asInt(Object? value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '');
}

String? _parseSha256(Object? value) {
  var digest = value?.toString().trim().toLowerCase();
  if (digest == null || digest.isEmpty) return null;
  if (digest.startsWith('sha256:')) digest = digest.substring(7);
  return RegExp(r'^[0-9a-f]{64}$').hasMatch(digest) ? digest : null;
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
    throw ReleaseUpdateException('$label必须使用 HTTPS 地址');
  }
}

Future<bool> _looksLikeZip(File file) async {
  final bytes = await _readHeader(file, 4);
  return bytes.length >= 4 &&
      bytes[0] == 0x50 &&
      bytes[1] == 0x4b &&
      (bytes[2] == 0x03 || bytes[2] == 0x05 || bytes[2] == 0x07) &&
      (bytes[3] == 0x04 || bytes[3] == 0x06 || bytes[3] == 0x08);
}

Future<bool> _looksLikeWindowsExecutable(File file) async {
  final bytes = await _readHeader(file, 2);
  return bytes.length >= 2 && bytes[0] == 0x4d && bytes[1] == 0x5a;
}

Future<List<int>> _readHeader(File file, int length) async {
  try {
    return await file
        .openRead(0, length)
        .fold<List<int>>(<int>[], (all, chunk) => all..addAll(chunk));
  } on FileSystemException {
    return const [];
  }
}

/// 比较 `v1.2.3[-rc.1][+build]` 形式的版本号。
int compareAppVersions(String left, String right) {
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
