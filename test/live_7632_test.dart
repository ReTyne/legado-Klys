import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/help/source/source_engine.dart';
import 'package:legado_md3/help/source/js/legado_js_runtime.dart';

/// flutter_test 默认把 HTTP 全拦成 400；真实链路测试需要放行网络。
class _RealHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..userAgent =
          'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/120 Mobile Safari/537.36';
  }
}

/// 对真实「大灰狼聚合」书源（yckceo 社区 id/7632）跑完整阅读链路：
/// 搜索 -> 详情 -> 目录 -> 正文。任何一环断裂即失败并打印 debugLog 供定位。
/// 强制迷你求值器（MiniLegadoJs），保证链路可在单测中确定性复现。
///
/// 数据源改用仓库内真实书源 fixture `test/fixtures/source_7632.json`（自包含，
/// 不再依赖 /tmp 临时文件）。本测试直连外网，沙箱/CI 网络不可靠，故默认跳过；
/// 需真实链路验证时显式开启：
///   flutter test --no-pub --dart-define=LEGADO_LIVE_NETWORK=true test/live_7632_test.dart
/// 离线、可复现的高级功能回归由 test/real_source_compat_test.dart 承担。
const bool _liveNetwork = bool.fromEnvironment('LEGADO_LIVE_NETWORK');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('7632 真实网络全链路（opt-in）', () async {
    HttpOverrides.global = _RealHttpOverrides();
    SharedPreferences.setMockInitialValues({});
    JsRuntimeManager.instance.factoryOverride = (_) => MiniLegadoJs();
    final raw = File('test/fixtures/source_7632.json').readAsStringSync();
    final m = jsonDecode(raw) as Map<String, dynamic>;
    final source = BookSource.fromJson(m.cast<String, dynamic>());

    final engine = BookSourceEngine();

    void dumpLog(String tag) {
      print('--- debugLog ($tag) ---');
      for (final l in engine.debugLog) {
        print(l);
      }
      engine.clearDebugLog();
    }

    // 1) 搜索
    print('===== SEARCH =====');
    List<dynamic> books = [];
    try {
      books = await engine
          .search(source, '十日终焉')
          .timeout(const Duration(seconds: 120));
      print('搜索结果: ${books.length}');
      for (final b in books.take(3)) {
        print('  - $b');
      }
    } catch (e, st) {
      print('搜索异常: $e\n$st');
    }
    dumpLog('search');
    expect(books, isNotEmpty, reason: '搜索无结果');

    final first = books.first;
    final bookUrl = (first as dynamic).bookUrl as String;

    // 2) 详情
    print('===== BOOK INFO ($bookUrl) =====');
    Book? info;
    try {
      info = await engine
          .getBookInfo(source, bookUrl)
          .timeout(const Duration(seconds: 120));
      print('详情: name=${info?.name} author=${info?.author} '
          'noteUrl=${info?.noteUrl} intro=${(info?.intro ?? '').length}字');
    } catch (e, st) {
      print('详情异常: $e\n$st');
    }
    dumpLog('bookInfo');
    expect(info, isNotNull, reason: '详情获取失败');

    // 3) 目录
    print('===== TOC =====');
    List<dynamic> chapters = [];
    try {
      final tocUrl = info!.noteUrl ?? bookUrl;
      chapters = await engine
          .getToc(source, tocUrl)
          .timeout(const Duration(seconds: 150));
      print('目录: ${chapters.length} 章');
      for (final c in chapters.take(3)) {
        final m = c as dynamic;
        print('  - title=${m.title} url=${m.url}');
      }
    } catch (e, st) {
      print('目录异常: $e\n$st');
    }
    dumpLog('toc');
    expect(chapters, isNotEmpty, reason: '目录获取失败');

    // 4) 正文
    print('===== CONTENT =====');
    String? content;
    try {
      final ch = chapters.first as dynamic;
      content = await engine
          .getContent(source, ch.url as String)
          .timeout(const Duration(seconds: 120));
      print('正文长度: ${content?.length ?? 0}');
      print('正文预览: ${(content ?? '').substring(0, content!.length.clamp(0, 200))}');
    } catch (e, st) {
      print('正文异常: $e\n$st');
    }
    dumpLog('content');
    expect(content, isNotNull, reason: '正文获取失败');
    expect(content!.length, greaterThan(50), reason: '正文过短');
  },
      skip: _liveNetwork
          ? null
          : '真实外网探针，默认跳过；用 --dart-define=LEGADO_LIVE_NETWORK=true 开启',
      timeout: const Timeout(Duration(minutes: 8)));
}
