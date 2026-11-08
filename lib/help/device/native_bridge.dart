import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:legado_md3/data/local/app_database.dart';

/// 第十轮：统一封装所有 Kotlin 原生 MethodChannel。
///
/// 约定：各 UI / 服务只通过本类访问原生能力，不再各自 new MethodChannel。
/// 所有方法在桌面 / iOS / 未实现通道时安全降级（返回合理默认值，不抛异常），
/// 保证 `flutter test` 与桌面调试不崩。
///
/// 通道清单（与 `android/.../MainActivity.kt` 严格一致）：
/// - `legado/network`      isWifi / getState / startWatch / stopWatch → 事件 onNetworkChanged
/// - `legado/shortcut`     setShortcuts / removeShortcuts / getInitialShortcut → 事件 onShortcut
/// - `legado/media_button` activate / deactivate / setPlaybackState / drain / getActive → 事件 onMediaButton
/// - `legado/pip`          enter / isSupported / isInPip → 事件 onPipModeChanged
/// - `legado/pdf_cover`    render
/// - `legado/mobi_huff`    decompress
/// - `legado/launcher_icon`setIcon / getIcon / getAliases
/// - `legado/battery`      getLevel / startWatch / stopWatch → 事件 onBatteryChanged / onTimeTick
/// - `legado/brightness`   getSystem / setSystem / canWrite / openWriteSettings /
///                         getWindow / setWindow / startWatch / stopWatch → 事件 onBrightnessChanged
/// - `legado/process_text` getInitialText → 事件 onProcessText
/// - `legado/saf`          pickDocumentTree / getPersistedUris / releasePermission /
///                         getUriForFile / shareFile / openFile
/// - `legado/reader_provider` cache（把 Dart DB 数据播种给原生 ContentProvider）
class NativeBridge {
  NativeBridge._();
  static final NativeBridge instance = NativeBridge._();

  static const _network = MethodChannel('legado/network');
  static const _shortcut = MethodChannel('legado/shortcut');
  static const _mediaButton = MethodChannel('legado/media_button');
  static const _pip = MethodChannel('legado/pip');
  static const _pdfCover = MethodChannel('legado/pdf_cover');
  static const _mobiHuff = MethodChannel('legado/mobi_huff');
  static const _launcherIcon = MethodChannel('legado/launcher_icon');
  static const _battery = MethodChannel('legado/battery');
  static const _brightness = MethodChannel('legado/brightness');
  static const _processText = MethodChannel('legado/process_text');
  static const _saf = MethodChannel('legado/saf');
  static const _readerProvider = MethodChannel('legado/reader_provider');

  bool get isAndroid => !kIsWeb && Platform.isAndroid;

  // ---------- 事件通知（UI 可监听） ----------
  final ValueNotifier<int?> batteryLevel = ValueNotifier<int?>(null);
  final ValueNotifier<double?> systemBrightness = ValueNotifier<double?>(null);
  final ValueNotifier<bool> inPip = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isWifiNotifier = ValueNotifier<bool>(false);

  /// 媒体按键事件（action: play/pause/next/prev/stop）
  final StreamController<Map<dynamic, dynamic>> mediaButtonEvents =
      StreamController<Map<dynamic, dynamic>>.broadcast();
  /// 网络变化事件
  final StreamController<Map<dynamic, dynamic>> networkEvents =
      StreamController<Map<dynamic, dynamic>>.broadcast();
  /// 外部选中文本（ACTION_PROCESS_TEXT）
  final StreamController<String> processTextEvents =
      StreamController<String>.broadcast();
  /// 快捷方式点击（id）
  final StreamController<String> shortcutEvents =
      StreamController<String>.broadcast();
  /// 系统时间 tick（每分钟）
  final StreamController<void> timeTickEvents =
      StreamController<void>.broadcast();

  bool _initialized = false;

  /// 启动时注册所有事件型 handler 并拉取初值。幂等。
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    void handler(MethodChannel ch, void Function(MethodCall call) fn) {
      ch.setMethodCallHandler((call) async {
        fn(call);
        return null;
      });
    }

    handler(_battery, (call) {
      if (call.method == 'onBatteryChanged') {
        final m = call.arguments is Map ? call.arguments as Map : <dynamic, dynamic>{};
        final pct = m['percent'] ?? m['level'];
        if (pct is num) batteryLevel.value = pct.round();
      } else if (call.method == 'onTimeTick') {
        if (!timeTickEvents.isClosed) timeTickEvents.add(null);
      }
    });
    handler(_brightness, (call) {
      if (call.method == 'onBrightnessChanged') {
        final v = call.arguments is num ? (call.arguments as num).toDouble() : null;
        systemBrightness.value = v;
      }
    });
    handler(_pip, (call) {
      if (call.method == 'onPipModeChanged' && call.arguments is bool) {
        inPip.value = call.arguments as bool;
      }
    });
    handler(_mediaButton, (call) {
      if (call.method == 'onMediaButton' && call.arguments is Map) {
        if (!mediaButtonEvents.isClosed) {
          mediaButtonEvents.add(call.arguments as Map<dynamic, dynamic>);
        }
      }
    });
    handler(_network, (call) {
      if (call.method == 'onNetworkChanged' && call.arguments is Map) {
        final m = call.arguments as Map<dynamic, dynamic>;
        if (m['wifi'] is bool) isWifiNotifier.value = m['wifi'] as bool;
        if (!networkEvents.isClosed) networkEvents.add(m);
      }
    });
    handler(_processText, (call) {
      if (call.method == 'onProcessText' && call.arguments is String) {
        if (!processTextEvents.isClosed) {
          processTextEvents.add(call.arguments as String);
        }
      }
    });
    handler(_shortcut, (call) {
      if (call.method == 'onShortcut' && call.arguments is String) {
        if (!shortcutEvents.isClosed) shortcutEvents.add(call.arguments as String);
      }
    });

    // 拉取初值并开启观察
    await refreshBattery();
    await refreshBrightness();
    await refreshWifi();
    if (isAndroid) {
      await _safe(() => _battery.invokeMethod('startWatch'));
      await _safe(() => _brightness.invokeMethod('startWatch'));
      await _safe(() => _network.invokeMethod('startWatch'));
      await _safe(() => _mediaButton.invokeMethod('activate'));
      // 引擎就绪前积压的媒体键补发
      await drainMediaButtons();
      // 把 Dart DB 数据播种给原生 ContentProvider（冷启动兜底）
      await seedReaderProvider();
    }
  }

  Future<T?> _safe<T>(Future<T?> Function() fn) async {
    try {
      return await fn();
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    } catch (_) {
      return null;
    }
  }

  // ---------- 网络 ----------
  Future<bool> get isWifi async {
    final r = await _safe<bool>(() async {
      final v = await _network.invokeMethod<bool>('isWifi');
      return v ?? false;
    });
    final result = r ?? !isAndroid; // 桌面默认放行
    isWifiNotifier.value = result;
    return result;
  }

  Future<Map<String, dynamic>> getNetworkState() async {
    final r = await _safe<Map<dynamic, dynamic>>(
        () => _network.invokeMethod<Map<dynamic, dynamic>>('getState'));
    return r == null ? <String, dynamic>{} : Map<String, dynamic>.from(r);
  }

  Future<void> refreshWifi() async {
    await isWifi;
  }

  // ---------- 电量 ----------
  Future<Map<String, dynamic>> getBatteryInfo() async {
    final r = await _safe<Map<dynamic, dynamic>>(
        () => _battery.invokeMethod<Map<dynamic, dynamic>>('getLevel'));
    return r == null ? <String, dynamic>{} : Map<String, dynamic>.from(r);
  }

  Future<void> refreshBattery() async {
    final info = await getBatteryInfo();
    final pct = info['percent'] ?? info['level'];
    if (pct is num) batteryLevel.value = pct.round();
  }

  // ---------- 亮度 ----------
  Future<double> getSystemBrightness() async {
    final r = await _safe<num>(() => _brightness.invokeMethod<num>('getSystem'));
    final v = (r ?? 128).toDouble();
    systemBrightness.value = v / 255.0;
    return systemBrightness.value!;
  }

  Future<double> getWindowBrightness() async {
    final r = await _safe<num>(() => _brightness.invokeMethod<num>('getWindow'));
    return (r ?? -1).toDouble();
  }

  Future<bool> canWriteSettings() async {
    return await _safe<bool>(() => _brightness.invokeMethod<bool>('canWrite')) ?? false;
  }

  Future<bool> setSystemBrightness(int value0to255) async {
    return await _safe<bool>(() => _brightness.invokeMethod<bool>(
            'setSystem', {'value': value0to255.clamp(0, 255)})) ??
        false;
  }

  Future<bool> setWindowBrightness(double value0to1) async {
    return await _safe<bool>(() => _brightness.invokeMethod<bool>(
            'setWindow', {'value': value0to1.clamp(0.0, 1.0)})) ??
        false;
  }

  Future<bool> openWriteSettings() async {
    return await _safe<bool>(() => _brightness.invokeMethod<bool>('openWriteSettings')) ??
        false;
  }

  Future<void> refreshBrightness() async {
    await getSystemBrightness();
  }

  // ---------- 快捷方式 ----------
  Future<int> setShortcuts() async {
    return await _safe<int>(() => _shortcut.invokeMethod<int>('setShortcuts')) ?? 0;
  }

  Future<bool> removeShortcuts() async {
    return await _safe<bool>(() => _shortcut.invokeMethod<bool>('removeShortcuts')) ??
        false;
  }

  Future<String?> getInitialShortcut() async {
    return await _safe<String>(() => _shortcut.invokeMethod<String>('getInitialShortcut'));
  }

  // ---------- 媒体按键 ----------
  Future<bool> activateMediaSession() async {
    return await _safe<bool>(() => _mediaButton.invokeMethod<bool>('activate')) ?? false;
  }

  Future<bool> setPlaybackState({required bool playing}) async {
    return await _safe<bool>(() => _mediaButton
            .invokeMethod<bool>('setPlaybackState', {'playing': playing})) ??
        false;
  }

  Future<List<Map<String, dynamic>>> drainMediaButtons() async {
    final r = await _safe<List<dynamic>>(
        () => _mediaButton.invokeMethod<List<dynamic>>('drain'));
    if (r == null) return [];
    return r
        .whereType<Map<dynamic, dynamic>>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
  }

  // ---------- PiP ----------
  Future<bool> isPipSupported() async {
    return await _safe<bool>(() => _pip.invokeMethod<bool>('isSupported')) ?? false;
  }

  Future<bool> isInPip() async {
    final r = await _safe<bool>(() => _pip.invokeMethod<bool>('isInPip'));
    inPip.value = r ?? false;
    return inPip.value;
  }

  Future<bool> enterPip({int aspectWidth = 16, int aspectHeight = 9, bool autoEnter = false}) async {
    return await _safe<bool>(() => _pip.invokeMethod<bool>('enter', {
          'aspectWidth': aspectWidth,
          'aspectHeight': aspectHeight,
          'autoEnter': autoEnter,
        })) ??
        false;
  }

  // ---------- PDF 首页封面 ----------
  Future<String?> renderPdfCover(String path, {int width = 480, int height = 720}) async {
    return await _safe<String>(() => _pdfCover.invokeMethod<String>('render', {
          'path': path,
          'width': width,
          'height': height,
        }));
  }

  // ---------- MOBI HUFF/CDIC ----------
  Future<Uint8List?> mobiHuffDecompress(Uint8List huff, List<Uint8List> cdics, Uint8List data) async {
    final r = await _safe<Uint8List>(() => _mobiHuff.invokeMethod<Uint8List>('decompress', {
          'huff': huff,
          'cdics': cdics,
          'data': data,
        }));
    return r;
  }

  // ---------- 动态桌面图标 ----------
  Future<bool> setLauncherIcon(String name) async {
    return await _safe<bool>(
            () => _launcherIcon.invokeMethod<bool>('setIcon', {'name': name})) ??
        false;
  }

  Future<String> getLauncherIcon() async {
    return await _safe<String>(() => _launcherIcon.invokeMethod<String>('getIcon')) ??
        'default';
  }

  Future<List<String>> getLauncherAliases() async {
    final r = await _safe<List<dynamic>>(
        () => _launcherIcon.invokeMethod<List<dynamic>>('getAliases'));
    return r?.whereType<String>().toList() ?? [];
  }

  // ---------- ACTION_PROCESS_TEXT ----------
  Future<String?> getInitialProcessText() async {
    return await _safe<String>(() => _processText.invokeMethod<String>('getInitialText'));
  }

  // ---------- SAF / FileProvider ----------
  Future<String?> pickDocumentTree() async {
    return await _safe<String>(() => _saf.invokeMethod<String>('pickDocumentTree'));
  }

  Future<List<String>> getPersistedUris() async {
    final r = await _safe<List<dynamic>>(
        () => _saf.invokeMethod<List<dynamic>>('getPersistedUris'));
    return r?.whereType<String>().toList() ?? [];
  }

  Future<bool> releasePersistedUri(String uri) async {
    return await _safe<bool>(
            () => _saf.invokeMethod<bool>('releasePermission', {'uri': uri})) ??
        false;
  }

  Future<String?> getUriForFile(String path) async {
    return await _safe<String>(
        () => _saf.invokeMethod<String>('getUriForFile', {'path': path}));
  }

  Future<bool> shareFile(String path, {String? mime, String? title}) async {
    return await _safe<bool>(() => _saf.invokeMethod<bool>('shareFile', {
          'path': path,
          'mime': mime,
          'title': title,
        })) ??
        false;
  }

  Future<bool> openFile(String path, {String? mime}) async {
    return await _safe<bool>(() => _saf.invokeMethod<bool>('openFile', {
          'path': path,
          'mime': mime,
        })) ??
        false;
  }

  // ---------- ReaderProvider 数据播种 ----------
  /// 把 Dart DB 的书源/书架/RSS 源序列化成共享 JSON，交给原生 ContentProvider。
  /// 原生冷启动时（Flutter 引擎未就绪）会读这份缓存兜底。
  Future<bool> seedReaderProvider() async {
    try {
      final db = await DatabaseService().database;
      final books = await db.query('books');
      final bookSources = await db.query('book_sources');
      final rssSources = await db.query('rss_sources');
      final entries = <String, String>{
        'GetBookshelf': jsonEncode(books),
        'GetBookSources': jsonEncode(bookSources),
        'GetRssSources': jsonEncode(rssSources),
      };
      return await _readerProvider.invokeMethod<bool>('cache', entries) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 释放资源（一般无需调用）
  void dispose() {
    mediaButtonEvents.close();
    networkEvents.close();
    processTextEvents.close();
    shortcutEvents.close();
    timeTickEvents.close();
  }
}
