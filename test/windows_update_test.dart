import 'dart:convert';
import 'dart:io';

import 'package:desktile/platform/release_update.dart';
import 'package:desktile/platform/windows_update.dart';
import 'package:desktile/ui/pages/windows_update_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('Windows 安装器覆盖当前程序目录并允许关闭占用进程', () {
    final executable = Platform.resolvedExecutable;
    final arguments = windowsInstallerArguments(executable);

    expect(arguments, contains('/CLOSEAPPLICATIONS'));
    expect(arguments, contains('/NORESTART'));
    expect(arguments, contains('/DIR=${File(executable).parent.path}'));
  });

  testWidgets('Windows 设置页显示版本和检查更新入口', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: WindowsUpdateSection()),
        ),
      ),
    );

    expect(find.text('应用更新'), findsOneWidget);
    expect(find.text('当前版本 v1.2.6'), findsOneWidget);
    expect(find.text('检查更新'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('Windows 更新检查优先选择 x64 Setup 安装包', () async {
    final client = MockClient((request) async {
      expect(request.url.toString(), 'https://updates.example.test/latest');
      return http.Response.bytes(
        utf8.encode('''
      {
        "tag_name": "v1.3.0",
        "html_url": "https://updates.example.test/release/v1.3.0",
        "assets": [
          {"name": "DeskTile-v1.3.0-arm64-setup.exe", "browser_download_url": "https://updates.example.test/arm64.exe"},
          {"name": "DeskTile-v1.3.0-x64.zip", "browser_download_url": "https://updates.example.test/x64.zip"},
          {"name": "DeskTile-v1.3.0-windows-x64-setup.exe", "browser_download_url": "https://updates.example.test/x64.exe", "size": 2048, "digest": "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"}
        ]
      }
      '''),
        HttpStatus.ok,
      );
    });
    final service = ReleaseUpdateService(
      packageType: ReleasePackageType.windowsInstaller,
      client: client,
      updateUri: Uri.parse('https://updates.example.test/latest'),
    );

    final result = await service.checkForUpdate(currentVersion: '1.2.0');

    expect(result.hasUpdate, isTrue);
    expect(result.latestVersion, '1.3.0');
    expect(
      result.update?.packageUrl.toString(),
      'https://updates.example.test/x64.exe',
    );
    expect(result.update?.sizeBytes, 2048);
    expect(
      result.update?.sha256,
      '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
    );
  });

  test('Windows 下载完成后才改名为安装包，并校验 MZ 文件头', () async {
    final temp = await Directory.systemTemp.createTemp(
      'desktile_windows_update_test',
    );
    addTearDown(() => temp.delete(recursive: true));
    final info = ReleaseUpdateInfo(
      version: '1.3.0',
      packageUrl: Uri.parse('https://updates.example.test/x64.exe'),
      releaseUrl: Uri.parse('https://updates.example.test/release'),
    );
    final service = ReleaseUpdateService(
      packageType: ReleasePackageType.windowsInstaller,
      client: MockClient(
        (_) async =>
            http.Response.bytes(<int>[0x4d, 0x5a, 1, 2, 3], HttpStatus.ok),
      ),
      temporaryDirectory: () async => temp,
    );

    final downloaded = await service.download(info);

    expect(File(downloaded.path).existsSync(), isTrue);
    expect(downloaded.path, endsWith('DeskTile-update-setup.exe'));
    expect(downloaded.bytes, 5);
    expect(File('${downloaded.path}.part').existsSync(), isFalse);
  });

  test('Windows 下载不是 PE 文件时清理残留临时文件', () async {
    final temp = await Directory.systemTemp.createTemp(
      'desktile_windows_update_test',
    );
    addTearDown(() => temp.delete(recursive: true));
    final info = ReleaseUpdateInfo(
      version: '1.3.0',
      packageUrl: Uri.parse('https://updates.example.test/x64.exe'),
      releaseUrl: Uri.parse('https://updates.example.test/release'),
    );
    final service = ReleaseUpdateService(
      packageType: ReleasePackageType.windowsInstaller,
      client: MockClient(
        (_) async => http.Response.bytes(<int>[0, 1, 2, 3], HttpStatus.ok),
      ),
      temporaryDirectory: () async => temp,
    );

    await expectLater(
      service.download(info),
      throwsA(isA<ReleaseUpdateException>()),
    );
    expect(
      File(
        '${temp.path}${Platform.pathSeparator}desktile_updates${Platform.pathSeparator}DeskTile-update-setup.exe.part',
      ).existsSync(),
      isFalse,
    );
  });

  test('Windows 安装包 SHA-256 不匹配时拒绝安装并清理文件', () async {
    final temp = await Directory.systemTemp.createTemp(
      'desktile_windows_update_test',
    );
    addTearDown(() => temp.delete(recursive: true));
    final info = ReleaseUpdateInfo(
      version: '1.3.0',
      packageUrl: Uri.parse('https://updates.example.test/x64.exe'),
      releaseUrl: Uri.parse('https://updates.example.test/release'),
      sha256:
          '0000000000000000000000000000000000000000000000000000000000000000',
    );
    final service = ReleaseUpdateService(
      packageType: ReleasePackageType.windowsInstaller,
      client: MockClient(
        (_) async =>
            http.Response.bytes(<int>[0x4d, 0x5a, 1, 2, 3], HttpStatus.ok),
      ),
      temporaryDirectory: () async => temp,
    );

    await expectLater(
      service.download(info),
      throwsA(
        isA<ReleaseUpdateException>().having(
          (error) => error.message,
          'message',
          contains('校验失败'),
        ),
      ),
    );
    expect(
      File(
        '${temp.path}${Platform.pathSeparator}desktile_updates${Platform.pathSeparator}DeskTile-update-setup.exe.part',
      ).existsSync(),
      isFalse,
    );
  });
}
