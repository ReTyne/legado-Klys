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
}
