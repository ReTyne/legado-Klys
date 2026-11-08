import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 网络状态监听（事件驱动，对齐 legado-E `NetworkChangedListener` 的
/// ConnectivityManager.NetworkCallback 事件流）。
///
/// 用途同 `NetworkUtils.isAvailable()`：在搜索、书源校验、上传等网络操作前
/// 快速判断连通性，离线时立即给出提示而不是干等超时。
///
/// * 常态监听：[Connectivity.onConnectivityChanged] 事件流，网络一变化即时
///   更新 [online] 并广播 [onConnectivityChanged]；取代此前每 15s 轮询
///   3 个公共 DNS 的费电、非实时方案。
/// * 一次性探测：[probe] 保留 DNS 查询（1.5s 超时）做真实可达性确认，由
///   事件到达或 [isOnline] 显式触发，不再周期轮询。
class NetworkMonitor {
  NetworkMonitor._();
  static final NetworkMonitor instance = NetworkMonitor._();

  /// 探测主机（多 DNS 公共解析器 IP，任一解析成功即在线）
  static const List<String> _probeHosts = [
    '223.5.5.5',
    '119.29.29.29',
    '8.8.8.8',
  ];

  /// 当前是否在线（初值乐观为 true，避免启动阶段误显离线）
  final ValueNotifier<bool> online = ValueNotifier<bool>(true);

  /// 原生网络类型判断通道（MainActivity 的 legado/network）。
  static const MethodChannel _networkChannel = MethodChannel('legado/network');

  bool? _wifiCache;
  DateTime? _wifiCacheAt;
  static const Duration _wifiCacheTtl = Duration(seconds: 30);

  /// connectivity_plus 事件订阅（取代 Timer.periodic 轮询）。
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  /// 网络类型变化广播（broadcast，支持 WebService 重绑 IP、封面闸门等多订阅者）。
  final StreamController<List<ConnectivityResult>> _connectivityController =
      StreamController<List<ConnectivityResult>>.broadcast();

  /// 网络类型变化事件流。元素为当前生效的链路类型列表，仅无网络时为
  /// `[ConnectivityResult.none]`（connectivity_plus 7.x 契约）。
  /// 主代理可据此在启动期重绑 WebService 监听 IP、刷新「仅 WiFi 加载封面」闸门。
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      _connectivityController.stream;

  bool _probing = false;
  bool _started = false;

  /// 兼容既有引用的公开常量（事件化后不再用于周期轮询）。
  static const Duration interval = Duration(seconds: 15);

  /// 单次探测超时
  static const Duration probeTimeout = Duration(milliseconds: 1500);

  /// 启动常态监听（重复调用安全；一般在应用启动 postFrame 调用一次）。
  void start() {
    if (_started) return;
    _started = true;
    // 事件驱动：链路类型一变化即更新 online、失效 WiFi 缓存并广播。
    _connectivitySub = Connectivity().onConnectivityChanged.listen(
      (results) {
        _publish(results);
        // 事件到达时做一次真实可达性确认（不再 15s 周期轮询）。
        unawaited(probe());
      },
      onError: (Object _) {},
    );
    // 立即取一次当前链路类型 + 真实探测，纠正乐观初值。
    unawaited(_initialCheck());
  }

  void _publish(List<ConnectivityResult> results) {
    if (!_connectivityController.isClosed) {
      _connectivityController.add(results);
    }
    final up = results.any((r) => r != ConnectivityResult.none);
    if (online.value != up) {
      online.value = up;
      // 连通性变化则让 WiFi 判断失效，避免使用过期结论
      _wifiCache = null;
    }
  }

  Future<void> _initialCheck() async {
    try {
      _publish(await Connectivity().checkConnectivity());
    } catch (_) {
      // 平台通道不可用（桌面/测试）：交给下面的 DNS 探测兜底
    }
    await probe();
  }

  /// 停止监听（测试/退出场景）；不关闭广播控制器，start() 可再次订阅。
  void stop() {
    final sub = _connectivitySub;
    _connectivitySub = null;
    _started = false;
    if (sub != null) unawaited(sub.cancel());
  }

  /// 一次性真实可达性探测并返回结果。
  ///
  /// 事件化后 [online] 主要由链路层事件流驱动，本方法仅返回 DNS 可达性
  /// 结论（供 [isOnline] 在未启动监听时兜底），不再覆盖 [online]，避免
  /// captive portal / 受限 DNS 场景把已在线的链路误判为离线。
  Future<bool> probe() async {
    if (_probing) return online.value;
    _probing = true;
    try {
      // 链路层先判：无任何网络直接返回，省掉 3 次无谓 DNS 超时。
      try {
        final link = await Connectivity().checkConnectivity();
        if (link.every((r) => r == ConnectivityResult.none)) return false;
      } catch (_) {}
      for (final host in _probeHosts) {
        try {
          final result =
              await InternetAddress.lookup(host).timeout(probeTimeout);
          if (result.isNotEmpty && result.first.rawAddress.isNotEmpty) {
            return true;
          }
        } catch (_) {
          // 换下一个探测主机
        }
      }
      return false;
    } finally {
      _probing = false;
    }
  }

  /// 网络操作前的快速检查：优先用事件流的结论，未启动监听时实时探测一次。
  Future<bool> get isOnline async {
    if (_started) return online.value;
    return probe();
  }

  /// 当前是否为 WiFi / 以太网（对齐 legado-E NetworkUtils.isWifi）。
  ///
  /// 走原生 ConnectivityManager（Android）；桌面/测试环境通道不可用时回退
  /// `false`。结果缓存 30 秒，避免书架滚动时对每条封面都发起一次平台调用。
  Future<bool> get isWifi async {
    if (!Platform.isAndroid) return false;
    final now = DateTime.now();
    final cached = _wifiCache;
    if (cached != null &&
        _wifiCacheAt != null &&
        now.difference(_wifiCacheAt!) < _wifiCacheTtl) {
      return cached;
    }
    bool value;
    try {
      value = await _networkChannel.invokeMethod<bool>('isWifi') ?? false;
    } catch (_) {
      // 通道未注册（如单元测试/桌面）：保守回退
      value = false;
    }
    _wifiCache = value;
    _wifiCacheAt = now;
    return value;
  }

  /// 网络状态变化后手动清除 WiFi 缓存（例如从设置页返回）。
  void invalidateWifiCache() => _wifiCache = null;
}
