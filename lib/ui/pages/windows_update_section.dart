import 'package:flutter/material.dart';

import '../../platform/release_update.dart';
import '../../platform/windows_update.dart';

/// Windows 更新面板。单独成文件，避免设置页同时承载两个平台的安装细节。
class WindowsUpdateSection extends StatefulWidget {
  const WindowsUpdateSection({super.key});

  @override
  State<WindowsUpdateSection> createState() => _WindowsUpdateSectionState();
}

class _WindowsUpdateSectionState extends State<WindowsUpdateSection> {
  late final WindowsUpdateService _updates;
  ReleaseUpdateCheckResult? _checkResult;
  DownloadedReleasePackage? _downloaded;
  String? _error;
  bool _checking = false;
  bool _downloading = false;
  bool _installing = false;
  int _receivedBytes = 0;
  int? _totalBytes;

  @override
  void initState() {
    super.initState();
    _updates = WindowsUpdateService();
  }

  @override
  void dispose() {
    _updates.dispose();
    super.dispose();
  }

  Future<void> _checkForUpdate() async {
    if (_checking || _downloading || _installing) return;
    setState(() {
      _checking = true;
      _error = null;
      _checkResult = null;
      _downloaded = null;
    });
    try {
      final result = await _updates.checkForUpdate();
      if (!mounted) return;
      setState(() => _checkResult = result);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.hasUpdate ? '发现新版本 v${result.update!.version}' : '当前已经是最新版本',
          ),
        ),
      );
    } on ReleaseUpdateException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = '检查更新失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _downloadAndInstall() async {
    final info = _checkResult?.update;
    if (info == null || _downloading || _installing) return;
    setState(() {
      _downloading = true;
      _error = null;
      _receivedBytes = 0;
      _totalBytes = info.sizeBytes;
    });
    try {
      final package = await _updates.download(
        info,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _receivedBytes = received;
            _totalBytes = total ?? info.sizeBytes;
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _downloaded = package;
        _downloading = false;
        _receivedBytes = package.bytes;
        _totalBytes = package.bytes;
      });
      await _installDownloaded(package);
    } on ReleaseUpdateException catch (error) {
      if (mounted) {
        setState(() {
          _downloading = false;
          _error = error.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _downloading = false;
          _error = '下载更新失败，请稍后重试';
        });
      }
    }
  }

  Future<void> _installDownloaded(DownloadedReleasePackage package) async {
    if (_installing) return;
    setState(() => _installing = true);
    try {
      await _updates.install(package);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('安装器已打开；开始安装时应用会自动关闭')));
    } on ReleaseUpdateException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = '无法启动 Windows 安装器');
    } finally {
      if (mounted) setState(() => _installing = false);
    }
  }

  String _versionLabel() {
    final current = _checkResult?.currentVersion ?? defaultWindowsVersion;
    return '当前版本 v$current';
  }

  String? _subtitle() {
    if (_checking) return '正在检查最新稳定版…';
    if (_installing) return '正在启动 Windows 安装器…';
    if (_downloading) {
      final total = _totalBytes;
      if (total != null && total > 0) {
        return '正在下载 ${(100 * _receivedBytes / total).clamp(0, 100).round()}%';
      }
      return '正在下载…';
    }
    if (_error != null) return _error;
    final info = _checkResult?.update;
    if (info != null) return '发现 v${info.version}，下载后自动覆盖安装';
    if (_checkResult != null) return '已是最新版本';
    return '从发布页获取最新 Windows 安装包';
  }

  @override
  Widget build(BuildContext context) {
    final info = _checkResult?.update;
    final downloaded = _downloaded;
    final subtitle = _subtitle();
    final progress = _totalBytes != null && _totalBytes! > 0
        ? (_receivedBytes / _totalBytes!).clamp(0.0, 1.0)
        : null;
    return _UpdateSection(
      title: '应用更新',
      children: [
        ListTile(
          leading: const Icon(Icons.system_update_outlined),
          title: Text(_versionLabel()),
          subtitle: subtitle == null
              ? null
              : Text(
                  subtitle,
                  style: _error == null
                      ? null
                      : TextStyle(color: Theme.of(context).colorScheme.error),
                ),
          trailing: _checking || _downloading || _installing
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
        ),
        if (info != null) ...[
          ListTile(
            leading: const Icon(Icons.new_releases_outlined),
            title: Text('新版本 v${info.version}'),
            subtitle: info.notes == null || info.notes!.trim().isEmpty
                ? const Text('下载安装包后由 Windows 安装器完成升级')
                : Text(
                    info.notes!.trim(),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
          ),
          if (progress != null && _downloading)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: LinearProgressIndicator(value: progress),
            ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: _checking || _downloading || _installing
                    ? null
                    : _checkForUpdate,
                icon: const Icon(Icons.refresh_outlined, size: 18),
                label: const Text('检查更新'),
              ),
              if (info != null)
                FilledButton.icon(
                  onPressed: _downloading || _installing
                      ? null
                      : () => downloaded == null
                            ? _downloadAndInstall()
                            : _installDownloaded(downloaded),
                  icon: Icon(
                    downloaded == null
                        ? Icons.download_outlined
                        : Icons.install_desktop_outlined,
                    size: 18,
                  ),
                  label: Text(downloaded == null ? '下载并安装' : '继续安装'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _UpdateSection extends StatelessWidget {
  const _UpdateSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          ...children,
        ],
      ),
    );
  }
}
