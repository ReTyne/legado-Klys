import 'dart:async';
import 'dart:io' show InternetAddressType, NetworkInterface;

import 'package:flutter/services.dart';

import 'package:legado_md3/help/web/web_params.dart'
    show isStrictIPv4Address;
import 'native_bridge.dart';
import 'web_service_contract.dart';

export 'web_service_contract.dart';

/// 批次 6 · Web 服务「原生侧」能力边界（ `service/WebService.kt`
/// 与 `App.kt` / `constant/NotificationId.kt` / `constant/AppConst.kt`）。
///
/// ==================================================================
/// 【Flutter 无等价能力 / 本轮未落地原生代码 —— 显式标注】
/// ==================================================================
/// 下列能力在 Android 上只能由原生（Kotlin）实现，Dart / Flutter 无等价 API：
///  * #1 三条通知渠道 `channel_download`/`channel_read_aloud`/`channel_web`
///    统一 `IMPORTANCE_DEFAULT` + 禁灯/禁振/无声/锁屏公开（App.kt:180-211）；
///    现状仅 `AudioNotifyService.kt:236-250` 有 1 条 `IMPORTANCE_LOW` 音频渠道；
///  * #7 WebService **前台服务** `startForeground(...)`，通知点按复制
///    hostAddress、stop action、ongoing/公开（WebService.kt:196-212）；
///  * #5 非引用计数 `PARTIAL_WAKE_LOCK` + `WIFI_MODE_FULL_HIGH_PERF` WifiLock，
///    每次 HTTP 请求 `serve` 续期（WebService.kt:62-75,119-122）；现状仅
///    `MainActivity.kt:461-467` 有阅读常亮的 `SCREEN_BRIGHT_WAKE_LOCK`；
///  * #8 BaseService 生命周期：仅首次前台 / onTaskRemoved / onTimeout /
///    POST_NOTIFICATIONS 权限检查（Android 14 FGS 强约束）；
///  * #9 `FOREGROUND_SERVICE_IMMEDIATE` 与 Manifest `dataSync` 前台服务类型
///    （现状 Manifest 仅注册 AudioNotifyService / WebTileService）。
///
/// 降级方案（本轮采用）：
///  1. Web HTTP 服务本身是纯 Dart `shelf`（在应用进程内），**不依赖**上述
///     前台服务即可正常工作；前台服务/通知/唤醒锁只是「后台保活 + 可见入口」。
///  2. 本文件把「多 IP 地址看板、渠道/通知 ID、复制/停止意图、唤醒锁类型」
///     做成 Dart 侧数据契约，经 MethodChannel `legado/web_service` 下发给原生；
///     原生未接线时（桌面/测试/未实现通道）由 [_invoke] 静默降级为空操作，
///     Web 服务与单元测试不受影响。
///  3. 真正落地需在 `android/` 增加 WebService 前台服务、在 MainActivity
///     注册该 MethodChannel、在 Manifest 增加 `dataSync` FGS 与权限。
///     本轮不改 `android/`：本环境无 Android 编译验证手段，且改 Manifest /
///     Service 属系统级配置，贸然改动会破坏并行代理的全量构建。故按用户要求
///     「不能等价实现的显式标注」处理，绝不伪造原生能力。
///
/// 能等价实现并已落地的部分：#6「多 IP 通知」的 Dart 侧——
/// `WebService` 现在枚举**全部**网卡 IPv4（见 web_service.dart
/// `_getLocalIPs()`），本类把地址列表格式化成多行通知文本，并在网络变化
/// （NativeBridge.networkEvents）时重新枚举刷新，对齐 WebService.kt:93-111。

/// Web 服务与原生通知/唤醒锁之间的契约桥（Dart 侧能力边界）。
/// 渠道/通知 ID 与多 IP 文本契约见 `web_service_contract.dart`（已 export）。
class WebServiceBoundary {
  WebServiceBoundary._();
  static final WebServiceBoundary instance = WebServiceBoundary._();

  static const MethodChannel _channel = MethodChannel('legado/web_service');

  StreamSubscription<Map<dynamic, dynamic>>? _networkSub;
  List<String> _lastAddresses = const <String>[];
  int _lastPort = 0;
  bool _started = false;

  /// Web 服务启动后下发前台通知契约 + 申请唤醒锁（原生侧接线后生效）。
  Future<void> onStarted({
    required List<String> addresses,
    required int port,
  }) async {
    _lastAddresses = List<String>.unmodifiable(addresses);
    _lastPort = port;
    _started = true;
    // 对齐 WebService.kt:93-111：网络变化时重算全部网卡地址并刷新通知。
    _networkSub ??= NativeBridge.instance.networkEvents.stream.listen((_) {
      unawaited(refreshFromNetwork());
    });
    await _invoke('startForeground', <String, dynamic>{
      'channelId': WebChannelIds.web,
      'notificationId': WebNotificationIds.webService,
      'lines': formatHostAddresses(_lastAddresses, _lastPort),
      'hostAddress': formatHostAddresses(_lastAddresses, _lastPort).first,
      'copyAction': WebServiceActions.copyHostAddress,
      'stopAction': WebServiceActions.stop,
    });
    // 对齐 WebService.kt:86-89：Web 专用非引用计数唤醒锁（原生接线后生效）。
    await _invoke('acquireLocks', <String, dynamic>{
      'wakeLock': 'PARTIAL_WAKE_LOCK',
      'wifiLock': 'WIFI_MODE_FULL_HIGH_PERF',
      'referenceCounted': false,
    });
  }

  /// 网络变化回调：Dart 侧重新枚举全部网卡 IPv4 并刷新前台通知契约。
  /// 见顶部「Flutter 无等价能力」注释——真正的通知刷新由原生完成。
  Future<void> refreshFromNetwork() async {
    if (!_started) return;
    _lastAddresses = List<String>.unmodifiable(await _enumerateLocalIPv4());
    final lines = formatHostAddresses(_lastAddresses, _lastPort);
    await _invoke('updateNotification', <String, dynamic>{
      'lines': lines,
      'hostAddress': lines.first,
    });
  }

  /// 每次 HTTP 请求到达时续期唤醒锁（对齐 WebService.kt:119-122 的 `serve`）。
  Future<void> onRequestServed() async {
    if (!_started) return;
    await _invoke(WebServiceActions.serve, <String, dynamic>{});
  }

  /// 把当前 hostAddress 复制到剪贴板（原生 PendingIntent 点击回调入口）。
  Future<void> copyHostAddress() async {
    if (!_started) return;
    await _invoke(WebServiceActions.copyHostAddress, <String, dynamic>{
      'hostAddress': formatHostAddresses(_lastAddresses, _lastPort).first,
    });
  }

  /// Web 服务停止：释放锁、移除通知、取消网络监听。
  Future<void> onStopped() async {
    _started = false;
    await _networkSub?.cancel();
    _networkSub = null;
    await _invoke('stopForeground', <String, dynamic>{});
    await _invoke('releaseLocks', <String, dynamic>{});
  }

  /// 原生未接线（桌面/测试/MissingPluginException）时静默降级为空操作。
  Future<void> _invoke(String method, [Map<String, dynamic>? args]) async {
    try {
      await _channel.invokeMethod<void>(method, args);
    } on MissingPluginException {
      // 降级：Web 服务本身不依赖前台服务/通知。
    } on PlatformException {
      // 降级：同上。
    } catch (_) {
      // 降级：同上。
    }
  }

  /// 枚举全部网卡 IPv4（对齐 NetworkUtils.getLocalIPAddress :248-270）。
  Future<List<String>> _enumerateLocalIPv4() async {
    final result = <String>[];
    try {
      for (final interface in await NetworkInterface.list()) {
        for (final addr in interface.addresses) {
          if (addr.type != InternetAddressType.IPv4 || addr.isLoopback) {
            continue;
          }
          final ip = addr.address;
          if (isStrictIPv4Address(ip)) result.add(ip);
        }
      }
    } catch (_) {}
    return result.isEmpty ? const <String>['127.0.0.1'] : result;
  }
}
