import 'package:flutter/services.dart';

/// 朗读服务的 CPU 唤醒锁（PARTIAL_WAKE_LOCK）Dart 侧边界。
///
/// 设计要点（与现有 `legado/wakelock` 通道严格区分）：
/// - `legado/wakelock` 的 enable/disable 在原生侧申请的是
///   `SCREEN_BRIGHT_WAKE_LOCK or ON_AFTER_RELEASE`（屏幕常亮），用于阅读页防熄屏。
///   它点亮屏幕、耗电显著，语义是「亮屏阅读」，并非偏好键 `readAloudWakeLock`
///   所描述的「CPU 保持唤醒、锁屏后继续朗读」。两者不可错误复用，故本类
///   故意不调用 `legado/wakelock`。
/// - `legado/web_service` 的 acquireLocks 虽使用 PARTIAL_WAKE_LOCK，但绑定在
///   WebServiceController 单例上并同时申请高性能 WiFi 锁，属于 Web 服务保活域，
///   复用会与 Web 服务互相释放对方的锁，也不适合朗读。
///
/// 因此朗读使用独立通道 `legado/tts_wakelock`（acquire / release），原生侧需
/// 以 `PowerManager.PARTIAL_WAKE_LOCK` + tag `legado:tts_read_aloud` 实现。
/// 原生尚未接线时（桌面 / 单测 / 其它平台）安全降级为空操作，不抛异常；
/// 偏好键 `readAloudWakeLock` 仍由 [TtsService] 真实读取并驱动本类状态切换。
class TtsWakeLock {
  TtsWakeLock._();
  static final TtsWakeLock instance = TtsWakeLock._();

  static const MethodChannel _channel = MethodChannel('legado/tts_wakelock');

  bool _held = false;

  /// 当前 Dart 侧认为是否持有唤醒锁（反映偏好键与朗读状态的组合结果）。
  bool get isHeld => _held;

  /// 按「偏好键是否开启」与「是否正在朗读」同步唤醒锁。
  /// 只在目标状态变化时下发原生调用；原生通道缺失时安全降级。
  Future<void> setHeld({required bool enabled, required bool active}) async {
    final shouldHold = enabled && active;
    if (shouldHold == _held) return;
    _held = shouldHold;
    try {
      if (shouldHold) {
        await _channel.invokeMethod<void>('acquire');
      } else {
        await _channel.invokeMethod<void>('release');
      }
    } on MissingPluginException {
      // 原生通道未注册：降级为空操作，_held 仍跟踪预期状态。
    } on PlatformException {
      // 原生拒绝（如权限/系统限制）：同上，不影响朗读本身。
    } catch (_) {
      // 桌面 / 测试环境：同上。
    }
  }

  /// 测试/诊断用：直接复位状态，不改变原生锁。
  void resetForTest() => _held = false;
}
