import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:legado_md3/help/web/web_service.dart';

/// Web 服务快捷磁贴（Quick Settings Tile，D3，对齐 E service/WebTileService.kt）。
///
/// 链路：磁贴点击（原生）→ `legado/web_tile` 的 `toggle` → Dart 切换
/// [WebService] 并回传 `updateState` → 原生刷新磁贴激活态。
/// 原生仅在 Android N+ 提供磁贴，其他平台 no-op。
class WebTileChannel {
  WebTileChannel._();

  static const _channel = MethodChannel('legado/web_tile');
  static bool _registered = false;

  /// 注册磁贴控制通道（main.dart 启动时调用一次）。
  static void register() {
    if (_registered) return;
    _registered = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'toggle') {
        await _toggle();
      }
      return null;
    });
  }

  /// 切换 Web 服务运行态并同步磁贴。
  static Future<void> _toggle() async {
    final service = WebService.instance;
    final p = await SharedPreferences.getInstance();
    if (service.isRunning) {
      await service.stop();
      await p.setBool('oc_webAutoStart', false);
    } else {
      final port = p.getInt('oc_webPort') ?? 1122;
      await service.start(port: port);
      await p.setBool('oc_webAutoStart', true);
    }
    await _syncState();
  }

  /// 把当前运行态推给原生磁贴。
  static Future<void> _syncState() async {
    try {
      await _channel.invokeMethod('updateState', {
        'running': WebService.instance.isRunning,
      });
    } catch (_) {
      // 非 Android / 磁贴未注册：忽略
    }
  }

  /// UI 层启停 Web 服务后调用，保持磁贴状态一致。
  static Future<void> syncFromUi() => _syncState();
}
