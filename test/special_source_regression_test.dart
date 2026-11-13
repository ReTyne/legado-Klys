import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:legado_md3/help/source/js/legado_bridge_js.dart';

/// 特殊书源链路回归：登录态持久化、设置结果回传、发现分类刷新。
/// 这些能力跨 JS 桥 / 引擎 / 页面三层，用源码契约锁住关键实现点。
String _src(String rel) =>
    File('/workspace/legado-Klys/legado-Klys-main/$rel').readAsStringSync();

void main() {
  const bridge = LegadoBridgeJs.code;

  group('登录信息与登录态持久化', () {
    test('登录信息为空时按表单默认值生成并回填', () {
      expect(bridge, contains('getLoginInfoMap: function'));
      expect(bridge, contains('__state.meta.loginUi'));
      expect(bridge, contains('it.type === "button"'));
      expect(bridge, contains('__state.loginInfo = JSON.stringify(map)'));
    });

    test('写入登录头的 Cookie 字段同步进 cookie jar', () {
      expect(bridge, contains('m.Cookie || m.cookie'));
      expect(bridge, contains('cookie.replaceCookie(__state.meta.url, c)'));
    });

    test('移除登录头时清理由登录头写入的凭据', () {
      expect(bridge, contains('cookie.removeCookie(__state.meta.url)'));
    });

    test('cookie.getKey 支持按书源主键与同注册域兜底查找', () {
      expect(bridge, contains('__registrableDomain'));
      expect(bridge, contains('__hostOf(__state.meta.url)'));
      expect(bridge, contains('if (__registrableDomain(k) !== base) continue;'));
    });

    test('原生按书源维度持久化完整 cookie jar', () {
      final js = _src('lib/help/source/js/parts/web_view_legado_js.dart');
      expect(js, contains("jsCookieJar_"));
      expect(js, contains('_persistBridgeCookies(env[\'cookies\'], srcUrl)'));
    });
  });

  group('交互页面结果回传', () {
    test('验证码识别同步返回字符串，不再返回 Promise', () {
      expect(bridge, contains('legado://verificationcode'));
      expect(bridge, contains('getVerificationCode: function (imageUrl)'));
      expect(bridge, contains('return r == null ? "" : String(r);'));
      final body = RegExp(
              r'getVerificationCode: function \(imageUrl\) \{([\s\S]*?)\n    \},')
          .firstMatch(bridge);
      expect(body, isNotNull);
      expect(body!.group(1)!.contains('new Promise'), isFalse,
          reason: '验证码结果被书源当作字符串直接使用');
    });

    test('浏览器结果包含渲染后 DOM、最终地址与 Cookie', () {
      final screen = _src('lib/ui/browser/browser_screen.dart');
      expect(screen, contains('class BrowserCaptureResult'));
      expect(screen, contains('final String finalUrl'));
      expect(screen, contains('final String cookies'));
      expect(screen, contains('this.initialHtml'));

      final state = _src('lib/ui/browser/parts/browser_screen_state.dart');
      expect(state, contains('document.documentElement.outerHTML'));
      expect(state, contains('_pageOrigin'));

      final js = _src('lib/help/source/js/parts/web_view_legado_js.dart');
      expect(js, contains("headers['X-Final-Url']"));
      expect(js, contains("headers['X-Set-Cookie']"));
    });

    test('startBrowserAwait 支持自定义页面内容参数', () {
      expect(bridge, contains('startBrowserAwait: function (url, title, refetchAfterSuccess, html)'));
      expect(bridge, contains('__openBrowserAwaitHtml(url, title, refetchAfterSuccess, html)'));
    });
  });

  group('发现分类与控件联动', () {
    test('分页占位符不再被误判为整块 JS 动作', () {
      final discover = _src('lib/ui/main/discover/discover_screen.dart');
      expect(discover, contains('static bool _isWholeAction'));
      expect(discover, contains('_isWholeAction(url)'));
      expect(discover, contains('RegExp(r\'^\\{\\{?page\\b\''));
    });

    test('refreshExplore 通知原生失效分类缓存', () {
      expect(bridge, contains('legado://refreshexplore'));
      final js = _src('lib/help/source/js/parts/web_view_legado_js.dart');
      expect(js, contains('_handleRefreshExplore'));
      expect(js, contains('exploreKinds_'));
      expect(js, contains('notifyExploreRefresh()'));
    });

    test('发现页监听刷新信号且动作执行期间不并发求值', () {
      final discover = _src('lib/ui/main/discover/discover_screen.dart');
      expect(discover, contains('exploreRefreshSignal.addListener'));
      expect(discover, contains('_kindActionRunning'));
      final signal = _src('lib/help/source/explore_refresh.dart');
      expect(signal, contains('ValueNotifier<int> exploreRefreshSignal'));
    });
  });

  group('日志与登录表单', () {
    test('toast 不再重复写入引擎日志', () {
      expect(bridge, contains('__state.toasts.push(s)'));
      expect(bridge, contains('__state.logs.push(s)'));
    });

    test('登录页保存表单、返回确认、刷新保留输入', () {
      final login = _src('lib/ui/book/source/parts/source_login_screen_state.dart');
      expect(login, contains('_draftForm'));
      expect(login, contains('loginForm_'));
      expect(login, contains('_confirmExit'));
      expect(login, contains('_saveAll'));
      expect(login, contains('已刷新，输入内容已保留'));
    });
  });

  group('引擎能力：对称加密 / 字体对象 / 规则内嵌 WebView', () {
    test('非 AES 对称加密走原生通道并覆盖 DES/3DES/SM4/RC4', () {
      expect(bridge, contains('__nativeCrypto('));
      expect(bridge, contains('legado://crypto'));
      expect(bridge, contains('alg === "DESEDE"'));
      expect(bridge, contains('alg === "SM4"'));
      expect(bridge, contains('alg === "RC4"'));
      // AES 仍走纯 JS 路径，不误入原生通道
      expect(bridge, contains('isAes = (alg === "AES"'));
    });

    test('补齐 DES/3DES 便捷加解密方法', () {
      for (final name in [
        'tripleDESDecodeStr',
        'tripleDESEncodeBase64Str',
        'tripleDESEncodeArgsBase64Str',
        'desDecodeToString',
        'desEncodeToBase64String',
        'aesEncodeToBase64String',
      ]) {
        expect(bridge, contains('$name: function'), reason: '缺少 $name');
      }
    });

    test('原生加密协议 handler 使用完整算法实现', () {
      final js = _src('lib/help/source/js/parts/web_view_legado_js.dart');
      expect(js, contains("url.startsWith('legado://crypto')"));
      expect(js, contains('_handleCrypto'));
      expect(js, contains('SymmetricCrypto(transformation, keyBytes'));
      expect(js, contains('cipher.decryptBytes(dataBytes)'));
    });

    test('queryTTF 返回带映射与方法的字体对象', () {
      expect(bridge, contains('__makeQueryTTF('));
      expect(bridge, contains('getGlyfByUnicode'));
      expect(bridge, contains('getUnicodeByGlyf'));
      expect(bridge, contains('isBlankUnicode'));
      expect(bridge, contains('unicodeToGlyphId'));
      // 兼容把返回值当替换表遍历的书源
      expect(bridge, contains('getReplacementMap: function'));
      final parser = _src('lib/help/source/ttf_parser.dart');
      expect(parser, contains('buildQueryData()'));
      expect(parser, contains("'replacement': replacement"));
    });

    test('@webjs: 规则由无头 WebView 加载内容并注入 window.result', () {
      final engine = _src('lib/help/source/source_engine.dart');
      expect(engine, contains('_webJsRule'));
      expect(engine, contains('_evalWebJs('));
      expect(engine, contains('HeadlessWebViewFetcher.fetchWebJs'));
      final fetcher = _src('lib/help/source/js/headless_webview.dart');
      expect(fetcher, contains('static Future<String> fetchWebJs'));
      expect(fetcher, contains('window.result = '));
      expect(fetcher, contains('AT_DOCUMENT_START'));
      final legadoJs = _src('lib/help/source/js/parts/legado_js.dart');
      expect(legadoJs, contains("rule.contains('@webjs:')"));
    });

    test('网络选项透传并把请求/响应头与重定向链写入日志', () {
      expect(bridge, contains('X-Legado-Timeout'));
      expect(bridge, contains('X-Legado-FollowRedirects'));
      expect(bridge, contains('X-Legado-WebView'));
      final js = _src('lib/help/source/js/parts/web_view_legado_js.dart');
      expect(js, contains("headers.remove('X-Legado-Timeout')"));
      expect(js, contains('followRedirects: optFollowRedirects'));
      expect(js, contains('requestHeaders: reqHeaders'));
      expect(js, contains('responseHeaders: respHeaders'));
      expect(js, contains('redirects: redirects'));
      final log = _src('lib/help/source/source_network_log.dart');
      expect(log, contains('bool get hasRedirect'));
    });

    test('refetchAfterSuccess 用原生重取原地址并记录重定向链', () {
      final js = _src('lib/help/source/js/parts/web_view_legado_js.dart');
      expect(js, contains("_refetchAfterBrowser"));
      expect(js, contains("uri.queryParameters['refetch']"));
      expect(js, contains('resp.realUri.toString()'));
    });
  });
}
