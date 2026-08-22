import 'dart:async';
import 'dart:io';

/// 同一种运行模式只允许一个实例。
///
/// 用绑定回环端口当互斥锁：绑得上就是第一个实例，绑不上说明已经有一个在跑，
/// 这时连过去发一个字节，让它把窗口拉到前面来。顺手就有了一条进程间通道，
/// 不用再引第三方单实例库。
class SingleInstance {
  SingleInstance._(this._server);

  final ServerSocket _server;

  /// 挂件进程用的端口。
  static const widgetPort = 45677;

  /// 主窗口进程用的端口。
  static const mainPort = 45678;

  /// 抢占 [port]。抢到返回实例对象，[onActivate] 会在别的实例来敲门时被调用；
  /// 没抢到返回 null（此时已经把敲门信号发过去了）。
  static Future<SingleInstance?> acquire(
    int port, {
    FutureOr<void> Function()? onActivate,
  }) async {
    try {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
      server.listen((socket) async {
        socket.destroy();
        await onActivate?.call();
      });
      return SingleInstance._(server);
    } on SocketException {
      await _knock(port);
      return null;
    }
  }

  static Future<void> _knock(int port) async {
    try {
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
        timeout: const Duration(milliseconds: 800),
      );
      socket.add([1]);
      await socket.flush();
      socket.destroy();
    } catch (_) {
      // 端口被别的程序占着，或者对方刚退出。忽略即可。
    }
  }

  /// 敲一下某个模式的实例；true 表示对方在跑并且收到了。
  static Future<bool> activateExisting(int port) async {
    try {
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
        timeout: const Duration(milliseconds: 800),
      );
      socket.add([1]);
      await socket.flush();
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> release() => _server.close();
}

/// 启动另一种运行模式的进程（同一个 exe，只是参数不同）。
class ModeLauncher {
  /// 打开主窗口：已经有主窗口就把它叫到前面，否则新起一个进程。
  static Future<void> openMainWindow() async {
    if (await SingleInstance.activateExisting(SingleInstance.mainPort)) return;
    await Process.start(
      Platform.resolvedExecutable,
      const [],
      mode: ProcessStartMode.detached,
    );
  }

  /// 打开桌面挂件。
  static Future<void> openWidget() async {
    if (await SingleInstance.activateExisting(SingleInstance.widgetPort)) return;
    await Process.start(
      Platform.resolvedExecutable,
      const ['--widget'],
      mode: ProcessStartMode.detached,
    );
  }
}
