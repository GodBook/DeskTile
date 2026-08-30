import 'dart:convert';
import 'dart:io';

import 'package:desktile/platform/android_update.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('Android 回退版本与当前发布版本一致', () {
    expect(defaultAndroidVersion, '1.2.7');
  });

  test('Android 版本比较遵循数字和预发布版本规则', () {
    expect(compareAndroidVersions('v1.2.0', '1.1.9'), greaterThan(0));
    expect(compareAndroidVersions('1.2', '1.2.0'), 0);
    expect(compareAndroidVersions('1.2.0-rc.2', '1.2.0-rc.10'), lessThan(0));
    expect(compareAndroidVersions('1.2.0', '1.2.0-rc.10'), greaterThan(0));
  });

  test('更新检查从 GitHub Release 选择通用 Android APK', () async {
    final client = MockClient((request) async {
      expect(request.url.toString(), 'https://updates.example.test/latest');
      return http.Response.bytes(
        utf8.encode('''
      {
        "tag_name": "v1.2.0",
        "html_url": "https://updates.example.test/release/v1.2.0",
        "body": "修复提醒问题",
        "assets": [
          {"name": "DeskTile-v1.2.0-arm64.apk", "browser_download_url": "https://updates.example.test/arm64.apk"},
          {"name": "DeskTile-v1.2.0-android.apk", "browser_download_url": "https://updates.example.test/android.apk", "size": 1234},
          {"name": "DeskTile-v1.2.0-windows.zip", "browser_download_url": "https://updates.example.test/windows.zip"}
        ]
      }
      '''),
        HttpStatus.ok,
      );
    });
    final service = AndroidUpdateService(
      client: client,
      updateUri: Uri.parse('https://updates.example.test/latest'),
    );

    final result = await service.checkForUpdate(currentVersion: '1.1.0');

    expect(result.hasUpdate, isTrue);
    expect(result.latestVersion, '1.2.0');
    expect(result.update?.version, '1.2.0');
    expect(
      result.update?.apkUrl.toString(),
      'https://updates.example.test/android.apk',
    );
    expect(
      result.update?.releaseUrl.toString(),
      'https://updates.example.test/release/v1.2.0',
    );
    expect(result.update?.sizeBytes, 1234);
  });

  test('低于或等于当前版本时不提供降级安装', () async {
    final client = MockClient(
      (_) async => http.Response('''
      {"tag_name":"v1.1.0","apk_url":"https://updates.example.test/app.apk"}
      ''', HttpStatus.ok),
    );
    final service = AndroidUpdateService(
      client: client,
      updateUri: Uri.parse('https://updates.example.test/latest'),
    );

    final result = await service.checkForUpdate(currentVersion: '1.1.0');

    expect(result.hasUpdate, isFalse);
    expect(result.latestVersion, '1.1.0');
  });

  test('下载完成后才改名为 APK', () async {
    final temp = await Directory.systemTemp.createTemp('desktile_update_test');
    addTearDown(() => temp.delete(recursive: true));
    final info = AndroidUpdateInfo(
      version: '1.2.0',
      apkUrl: Uri.parse('https://updates.example.test/app.apk'),
      releaseUrl: Uri.parse('https://updates.example.test/release'),
    );
    final client = MockClient((_) async {
      return http.Response.bytes(<int>[
        0x50,
        0x4b,
        0x03,
        0x04,
        1,
        2,
        3,
      ], HttpStatus.ok);
    });
    final service = AndroidUpdateService(
      client: client,
      temporaryDirectory: () async => temp,
    );

    final downloaded = await service.download(info);

    expect(File(downloaded.path).existsSync(), isTrue);
    expect(downloaded.bytes, 7);
    expect(downloaded.path, endsWith('desktile-update.apk'));
    expect(File('${downloaded.path}.part').existsSync(), isFalse);
  });

  test('下载内容不是 APK 时会清理残留临时文件', () async {
    final temp = await Directory.systemTemp.createTemp('desktile_update_test');
    addTearDown(() => temp.delete(recursive: true));
    final info = AndroidUpdateInfo(
      version: '1.2.0',
      apkUrl: Uri.parse('https://updates.example.test/app.apk'),
      releaseUrl: Uri.parse('https://updates.example.test/release'),
    );
    final service = AndroidUpdateService(
      client: MockClient(
        (_) async => http.Response.bytes(<int>[1, 2, 3, 4], HttpStatus.ok),
      ),
      temporaryDirectory: () async => temp,
    );

    await expectLater(
      service.download(info),
      throwsA(isA<AndroidUpdateException>()),
    );
    expect(
      File(
        '${temp.path}${Platform.pathSeparator}desktile_updates${Platform.pathSeparator}desktile-update.apk.part',
      ).existsSync(),
      isFalse,
    );
  });

  test('更新源和 APK 地址必须使用 HTTPS', () async {
    final service = AndroidUpdateService(
      client: MockClient((_) async => http.Response('{}', HttpStatus.ok)),
      updateUri: Uri.parse('http://updates.example.test/latest'),
    );

    expect(
      () => service.checkForUpdate(currentVersion: '1.1.0'),
      throwsA(isA<AndroidUpdateException>()),
    );
  });
}
