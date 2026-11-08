import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:legado_md3/common/app_navigator.dart';
import 'package:legado_md3/common/deep_link_service.dart';
import 'package:legado_md3/help/device/native_bridge.dart';
import 'package:legado_md3/help/net/network_monitor.dart';
import 'package:legado_md3/help/readaloud/tts_service.dart';
import 'package:legado_md3/help/source/archive_native.dart';
import 'package:legado_md3/help/storage/book_progress_sync.dart';
import 'package:legado_md3/help/web/web_service.dart';
import 'package:legado_md3/ui/book/epub/local_book_import_helper.dart';
import 'package:legado_md3/ui/book/search/search_screen.dart';
import 'package:legado_md3/ui/main/main_screen.dart';

/// 第十轮：启动期统一接线（把各域能力串成完整调用链）。
///
/// - 原生桥初始化（电量/亮度/媒体键/网络事件/ReaderProvider 播种）；
/// - RAR/7z 归档解码器注册（F 组 helper ↔ 已有 `legado/archive` 原生通道）；
/// - 动态快捷方式、ACTION_PROCESS_TEXT、剪贴板口令 `#L:`；
/// - 媒体键 → 朗读控制；网络变化 → Web 服务重绑；
/// - 启动期云进度拉取。
class BootstrapService {
  BootstrapService._();
  static final BootstrapService instance = BootstrapService._();

  bool _done = false;

  /// 兜底朗读实例：阅读页未打开时，媒体键也可启动/停止朗读。
  /// 阅读页打开后 [TtsService.active] 会指向其持有的真实实例，优先使用它。
  static final TtsService sharedTts = TtsService();

  Future<void> run(SharedPreferences prefs) async {
    if (_done) return;
    _done = true;

    final nb = NativeBridge.instance;
    await nb.init();

    _registerArchiveDecoders();
    await _registerShortcuts(nb);
    _bindMediaButtons(nb);
    _bindNetworkEvents();
    _bindExternalText(nb);
    await _readClipboardShibboleth();
    await _syncProgressOnLaunch(prefs);
  }

  /// RAR/7z 解码器：ArchiveImportHelper 的抽象回调接到已有原生归档通道，
  /// 真实解压落盘后读回条目（不做假降级）。
  void _registerArchiveDecoders() {
    Future<List<ArchiveEntry>> decode(String path, ArchiveKind kind) async {
      final bytes = await File(path).readAsBytes();
      final label = kind == ArchiveKind.rar ? 'rar' : '7z';
      final dirName = await ArchiveNative.extractAll(bytes, label);
      if (dirName == null) {
        throw ArchiveImportException(
            '${kind == ArchiveKind.rar ? 'RAR' : '7z'} 解压失败（当前平台可能未启用原生归档插件）');
      }
      final dir = await getApplicationDocumentsDirectory();
      final base = Directory('${dir.path}/legado_files/$dirName');
      final out = <ArchiveEntry>[];
      if (!base.existsSync()) return out;
      await for (final f in base.list(recursive: true, followLinks: false)) {
        if (f is File) {
          final name = f.path.replaceFirst('${base.path}/', '');
          out.add(ArchiveEntry(name, Uint8List.fromList(await f.readAsBytes())));
        }
      }
      return out;
    }

    ArchiveImportHelper.registerExternalDecoder(ArchiveKind.rar, decode);
    ArchiveImportHelper.registerExternalDecoder(ArchiveKind.sevenZip, decode);
  }

  Future<void> _registerShortcuts(NativeBridge nb) async {
    await nb.setShortcuts();
    final initial = await nb.getInitialShortcut();
    if (initial != null) _handleShortcut(initial);
    nb.shortcutEvents.stream.listen(_handleShortcut);
  }

  void _handleShortcut(String id) {
    switch (id) {
      case 'bookshelf':
      case 'lastRead':
        MainScreenSwitch.requestTab?.call(0);
        break;
      case 'search':
        final ctx = appNavigatorKey.currentContext;
        if (ctx != null) {
          Navigator.of(ctx).push(
              MaterialPageRoute(builder: (_) => const SearchScreen()));
        }
        break;
      case 'discover':
        MainScreenSwitch.requestTab?.call(1);
        break;
    }
  }

  /// 耳机/媒体按键 → 朗读控制（对齐 Sigma MediaButton + ReadAloudService）。
  void _bindMediaButtons(NativeBridge nb) {
    nb.mediaButtonEvents.stream.listen((event) async {
      final tts = TtsService.active ?? sharedTts;
      switch (event['action']?.toString()) {
        case 'play':
          await tts.play();
        case 'pause':
          await tts.pause();
        case 'playPause':
          if (tts.isPlaying) {
            await tts.pause();
          } else {
            await tts.play();
          }
        case 'next':
          await tts.next();
        case 'prev':
          await tts.previous();
        case 'stop':
        case 'rewind':
        case 'fastForward':
          await tts.stop();
      }
      await nb.setPlaybackState(playing: tts.isPlaying);
    });
  }

  /// 网络状态变化 → 重绑 Web 服务 + 触发一次真实探测。
  void _bindNetworkEvents() {
    NetworkMonitor.instance.onConnectivityChanged.listen((_) async {
      await NetworkMonitor.instance.probe();
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('oc_webAutoStart') ?? false) {
        // start 幂等：端口不变时复用已有 server；网络切换后重新可访问。
        final port = prefs.getInt('oc_webPort') ?? 1122;
        await WebService().start(port: port).catchError((_) {});
      }
    });
    NativeBridge.instance.networkEvents.stream.listen((_) {
      NetworkMonitor.instance.probe();
    });
  }

  /// ACTION_PROCESS_TEXT：系统选中文字直接带入搜索页。
  void _bindExternalText(NativeBridge nb) {
    void route(String? text, [int retry = 0]) {
      if (text == null || text.trim().isEmpty) return;
      final ctx = appNavigatorKey.currentContext;
      if (ctx == null) {
        // navigatorKey 尚未 attach（极早期冷启动）：有限重试，不丢事件。
        if (retry < 5) {
          Future.delayed(const Duration(milliseconds: 400),
              () => route(text, retry + 1));
        }
        return;
      }
      Navigator.of(ctx).push(MaterialPageRoute(
          builder: (_) => SearchScreen(initialKeyword: text.trim())));
    }

    nb.processTextEvents.stream.listen((t) => route(t));
    nb.getInitialProcessText().then((t) => route(t));
  }

  /// 剪贴板口令导入（对齐 Sigma `readShibboleth`：#L: 前缀 → 分类型导入 → 清剪贴板）。
  Future<void> _readClipboardShibboleth() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim() ?? '';
      if (!text.startsWith('#L:')) return;
      final body = text.substring(3).trim();
      if (body.isEmpty) return;
      await DeepLinkService.instance.importRaw(body);
      await Clipboard.setData(const ClipboardData(text: ''));
    } catch (_) {
      // 桌面/测试无剪贴板：忽略
    }
  }

  /// 启动期云进度拉取（WebDAV 单书进度由阅读页按需拉取，避免启动期遍历全书）。
  Future<void> _syncProgressOnLaunch(SharedPreferences prefs) async {
    try {
      if (prefs.getBool('oc_autoSyncProgress') ?? true) {
        await BookProgressSync.instance.pull();
      }
    } catch (_) {
      // 云端不可用不影响启动
    }
  }
}
