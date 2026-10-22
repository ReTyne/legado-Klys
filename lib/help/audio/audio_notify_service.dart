import 'dart:async';

import 'package:flutter/services.dart';

/// 音频通知栏 / 后台播放控制（Android 原生前台服务，见 `AudioNotifyService.kt`）。
///
/// 分工：
///  - Dart 侧用 audioplayers 真正解码播放；
///  - 原生服务负责以「媒体播放」类型前台运行保活进程，并展示媒体通知；
///  - 通知栏按钮的命令通过 `legado/audio_cmd` 频道的 `onAction` 回传到本类。
///
/// 频道划分（原生侧同理）：
///  - `legado/audio_notify`：Dart -> 原生的 start / update / stop，由 MainActivity 处理，
///    由其调用 startService / stopService 拉起原生服务；
///  - `legado/audio_cmd`：原生 -> Dart 的通知栏命令。
///
/// 因为 MainActivity 使用应用级共享 FlutterEngine（不随 Activity 销毁），
/// 播放页关闭后 Dart 播放器仍存活，通知栏控制才真正有效。
///
/// 非 Android 平台（iOS/桌面）没有该服务：所有调用都安全地静默失败，
/// 调用方无需判断平台。
class AudioNotifyService {
  AudioNotifyService._();

  static final AudioNotifyService instance = AudioNotifyService._();

  /// Dart -> 原生：控制服务生命周期
  static const _channel = MethodChannel('legado/audio_notify');

  /// 原生 -> Dart：通知栏控制命令
  static const _cmdChannel = MethodChannel('legado/audio_cmd');

  /// 通知栏产生的控制命令（play / pause / prev / next / stop）
  final StreamController<String> _actions = StreamController<String>.broadcast();

  bool _started = false;

  Stream<String> get actions => _actions.stream;

  /// 注册命令回调（幂等，可重复调用）
  void init() {
    if (_started) return;
    _started = true;
    _cmdChannel.setMethodCallHandler((call) async {
      if (call.method == 'onAction' && call.arguments is String) {
        _actions.add(call.arguments as String);
      }
      return null;
    });
  }

  /// 启动前台服务并显示通知（开始播放时调用）
  Future<void> start({
    required String title,
    required String subtitle,
    required bool playing,
  }) async {
    try {
      await _channel.invokeMethod<void>('start', {
        'title': title,
        'subtitle': subtitle,
        'playing': playing,
      });
    } catch (_) {
      // 非 Android 平台或服务不可用：忽略
    }
  }

  /// 更新通知内容（切歌 / 播放暂停状态变化时调用）
  Future<void> update({
    String? title,
    String? subtitle,
    bool? playing,
  }) async {
    try {
      await _channel.invokeMethod<void>('update', {
        if (title != null) 'title': title,
        if (subtitle != null) 'subtitle': subtitle,
        if (playing != null) 'playing': playing,
      });
    } catch (_) {}
  }

  /// 停止服务并移除通知（停止播放 / 退出后台播放时调用）
  Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (_) {}
  }

  /// 释放（仅在应用退出时调用）
  void dispose() {
    _actions.close();
    _started = false;
  }
}
