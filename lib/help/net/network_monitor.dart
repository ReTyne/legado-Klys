import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// 轻量网络状态监听（零第三方依赖）。
///
/// 对齐 legado-E `NetworkUtils.isAvailable()` 的用途：在发起搜索、书源校验、
/// 上传等网络操作前快速判断连通性，离线时立即给出提示而不是干等超时。
/// 实现上不用 connectivity_plus（避免引入平台通道依赖），采用：
/// * 一次性探测：[probe] 对固定主机做 DNS 查询（1.5s 超时）；
/// * 常态监听：应用运行期间每 [interval] 轮询一次，状态变化时通知
///   [online]（ValueNotifier，可直接被 UI 的 ValueListenableBuilder 订阅）。
///
/// 注意：DNS 可解析即认为在线（与 E 的 transports 判断同为链路层口径，
/// 不保证目标站点可达； captive portal 场景可能误报，仅作快速提示用）。
class NetworkMonitor {
  NetworkMonitor._();
  static final NetworkMonitor instance = NetworkMonitor._();

  /// 探测主机（多 DNS 公共解析器 IP，任一解析成功即在线）
  static const List<String> _probeHosts = ['223.5.5.5', '119.29.29.29', '8.8.8.8'];

  /// 当前是否在线（初值乐观为 true，避免启动阶段误显离线）
  final ValueNotifier<bool> online = ValueNotifier<bool>(true);

  Timer? _timer;
  bool _probing = false;
  bool _started = false;

  /// 轮询间隔
  static const Duration interval = Duration(seconds: 15);
  /// 单次探测超时
  static const Duration probeTimeout = Duration(milliseconds: 1500);

  /// 启动常态监听（重复调用安全；一般在应用启动 postFrame 调用一次）
  void start() {
    if (_started) return;
    _started = true;
    // 立即探测一次，纠正乐观初值
    probe();
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => probe());
  }

  /// 停止监听（测试/退出场景）
  void stop() {
    _timer?.cancel();
    _timer = null;
    _started = false;
  }

  /// 一次性探测并刷新 [online]，返回探测结果。
  Future<bool> probe() async {
    if (_probing) return online.value;
    _probing = true;
    try {
      var ok = false;
      for (final host in _probeHosts) {
        try {
          final result = await InternetAddress.lookup(host).timeout(probeTimeout);
          if (result.isNotEmpty && result.first.rawAddress.isNotEmpty) {
            ok = true;
            break;
          }
        } catch (_) {
          // 换下一个探测主机
        }
      }
      if (online.value != ok) online.value = ok;
      return ok;
    } finally {
      _probing = false;
    }
  }

  /// 网络操作前的快速检查：优先用缓存的轮询结果，未启动监听时实时探测一次。
  Future<bool> get isOnline async {
    if (_started) return online.value;
    return probe();
  }
}
