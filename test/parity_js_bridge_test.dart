import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:legado_md3/help/source/js/legado_bridge_js.dart';

/// 书源脚本桥与原生协议层的能力回归。
///
/// 断言直接面向注入脚本（LegadoBridgeJs.code）与各 Dart 实现文件的源码文本，
/// 覆盖新增方法、参数重载、场景注入、协议分派与响应头回灌等落地能力。
final _root = Directory.current.path;

String _src(String rel) => File('$_root/$rel').readAsStringSync();

void main() {
  const code = LegadoBridgeJs.code;
  final wv = _src('lib/help/source/js/parts/web_view_legado_js.dart');
  final runtime = _src('lib/help/source/js/legado_js_runtime.dart');
  final netLog = _src('lib/help/source/source_network_log.dart');
  final headless = _src('lib/help/source/js/headless_webview.dart');

  group('java 对象新增方法', () {
    test('补齐的 19 个方法全部在注入脚本中暴露', () {
      const apis = <String>[
        'setContent',
        'setBaseUrl',
        'setRedirectUrl',
        'getString',
        'getStringList',
        'getElement',
        'getElements',
        'addBook',
        'showPhoto',
        'copyText',
        'clearTtsCache',
        'upLoginData',
        'upUiData',
        'reUiView',
        'refreshBookInfo',
        'refreshContent',
        'upConfig',
        'getRandomLetter',
        'request',
      ];
      expect(apis.length, 19);
      for (final api in apis) {
        expect(code, contains('$api: function'), reason: '桥缺少方法 $api');
      }
    });

    test('规则上下文方法链式返回并走规则协议', () {
      expect(code, contains('__ruleCall("setContent"'));
      expect(code, contains('__makeElement(__ruleCall("getElement"'));
      expect(code, contains('return java;'));
    });

    test('Promise 桥把结果写入内存缓存并回调', () {
      expect(code, contains('cache.putMemory(id, data)'));
      expect(code, contains('window.__legadoBridgeResult(id, success)'));
      expect(code, contains('return Promise.resolve(data)'));
    });

    test('UI 数据与配置方法写入运行时状态', () {
      expect(code, contains('__state.clipboard = t'));
      expect(code, contains('__uiEvent("addBook"'));
      expect(code, contains('__state.config = Object.assign'));
      expect(code, contains('String.fromCharCode(97'));
    });

    test('AnalyzeUrl 场景接口返回 UA 与合并请求头', () {
      expect(
          code, contains('getUserAgent: function () { return __state.ua; }'));
      expect(code, contains('getHeaderMap: function (hasLoginHeader)'));
    });
  });

  group('签名重载与参数生效', () {
    test('网络重载把超时与重定向透传到请求头', () {
      expect(code, contains('typeof options === "number"'));
      expect(code, contains('X-Legado-Timeout'));
      expect(code, contains('X-Legado-FollowRedirects'));
      expect(code, contains('followRedirects: false'));
    });

    test('摘要与 HMAC 走全算法原生通道', () {
      expect(code, contains('digestHex: function (data, algorithm)'));
      expect(code, contains('__nativeDigest("digest"'));
      expect(code, contains('HMacHex: function (data, algorithm, key)'));
      expect(code, contains('__nativeDigest("hmac"'));
      expect(code, contains('legado://crypto'));
    });

    test('base64 flags 与响应对象能力可用', () {
      expect(code, contains('URL_SAFE'));
      expect(code, contains('NO_WRAP'));
      expect(code, contains('callTime: function ()'));
      expect(code, contains('errorBody: function ()'));
      expect(code, contains('putCallTime: function (t)'));
      expect(code, contains('function __jsoupFromXhr(url, text)'));
    });

    test('批量请求携带 isTest 与限流旁路并归一错误码', () {
      expect(code, contains('isTest: true'));
      expect(code, contains('isTest: false'));
      expect(code, contains('skipRateLimit: !!skipRateLimit'));
      expect(code, contains('__testErrorCode(r)'));
      expect(code, contains('legado://ajaxall'));
    });

    test('WebView 渲染把完整参数封装进协议请求', () {
      expect(
          code,
          contains(
              'webViewGetSource: function (html, url, js, sourceRegex, cacheFirst, delayTime)'));
      expect(code, contains('sourceRegex:'));
      expect(code, contains('delayMs:'));
      expect(code, contains('legado://webview'));
      expect(wv, contains('Future<iw.WebResourceResponse> _handleWebView('));
      expect(wv, contains('HeadlessWebViewFetcher.fetch('));
      expect(wv, contains('sourceRegex: sourceRegex'));
    });

    test('文件与压缩包接口尊重 charset 与 saveTime', () {
      expect(code, contains('legado://file?op=cache&url='));
      expect(code, contains('&saveTime='));
      expect(code, contains('legado://file?op=read&path='));
      expect(code, contains('&cs='));
      expect(wv, contains("queryParameters['saveTime']"));
      expect(wv, contains('if (age < saveTime)'));
    });

    test('时间、编码与字体工具方法的重载签名齐全', () {
      expect(code, contains('timeFormatUTC: function (time, pattern, sh)'));
      expect(code, contains('encodeURI: function (str, enc)'));
      expect(code,
          contains('replaceFont: function (text, errorQ, correctQ, filter)'));
      expect(code, contains('queryTTF: function (data, useCache)'));
      expect(code, contains('startBrowser: function (url, title, html)'));
      expect(code, contains('openVideoPlayer: function (url, title, isFloat)'));
      expect(code,
          contains('showBrowser: function (url, html, preloadJs, config)'));
      expect(code, contains('setIv: function (v)'));
      expect(code, contains('verify: function (data, signature)'));
    });

    test('open 补齐 sort/rss/search/explore 分支', () {
      expect(code, contains('__uiEvent("openSort"'));
      expect(code, contains('n === "rss"'));
      expect(code, contains('globalThis.rssArticle'));
      expect(code, contains('n === "explore"'));
      expect(code, contains('legado://refreshexplore'));
    });
  });

  group('场景与全局注入', () {
    test('按场景切换 java 可见方法子集', () {
      expect(code, contains('function __javaForScene(scene)'));
      expect(code, contains('var __javaScenes = {'));
      expect(code, contains('rule: __sceneCore.concat(["getString"'));
      expect(
          code, contains('web: __sceneCore.concat(["request", "upConfig"])'));
      expect(code, contains('globalThis.__javaForScene = __javaForScene'));
    });

    test('求值入口注入场景全局变量并切换 java', () {
      expect(wv, contains("'srcArg': req.src"));
      expect(wv, contains("'sceneArg': req.scene"));
      expect(wv, contains('globalThis.src = srcArg;'));
      expect(wv, contains('globalThis.content = contentArg;'));
      expect(wv, contains('globalThis.java = __javaForScene(sceneArg'));
    });

    test('JsEvalRequest 增加场景入参字段且保持可选', () {
      expect(runtime, contains('this.src,'));
      expect(runtime, contains('this.nextChapterUrl,'));
      expect(runtime, contains('this.speakSpeed,'));
      expect(runtime, contains('this.event,'));
      expect(runtime, contains('this.scene,'));
      expect(runtime, contains('final String? scene;'));
      expect(runtime, contains('final dynamic event;'));
    });
  });

  group('原生协议层', () {
    test('Dart 侧分派新增协议 handler', () {
      expect(wv, contains("startsWith('legado://webview')"));
      expect(wv, contains("startsWith('legado://rule')"));
      expect(wv, contains("startsWith('legado://loginui')"));
      expect(wv, contains("startsWith('legado://sign')"));
      expect(wv, contains('Future<iw.WebResourceResponse> _handleRule('));
      expect(wv, contains('Future<iw.WebResourceResponse> _handleLoginUi('));
      expect(wv, contains('Future<iw.WebResourceResponse> _handleSign('));
    });

    test('crypto 协议分派摘要/HMAC/非对称/签名到门面', () {
      expect(wv, contains("if (op == 'digest' || op == 'hmac')"));
      expect(wv, contains('CryptoUtils.hmacBase64'));
      expect(wv, contains('CryptoUtils.simpleHash('));
      expect(wv, contains("if (op == 'asym') return _cryptoAsym(m);"));
      expect(wv, contains("if (op == 'sign') return _cryptoSign(m);"));
      expect(wv, contains('AsymmetricCrypto(transformation'));
      expect(wv, contains('RsaSign(algorithm'));
    });

    test('真实响应头以 X-Legado-* 回灌', () {
      expect(wv, contains('SourceNetworkLog.instance.toLegadoHeaders(last)'));
      expect(
          netLog,
          contains(
              'Map<String, String> toLegadoHeaders(SourceNetworkEntry entry)'));
      expect(netLog, contains("out['X-Legado-RespHeaders'] = b64Json(resp);"));
      expect(netLog, contains("out['X-Legado-ReqHeaders'] = b64Json(req);"));
      expect(
          netLog,
          contains(
              "out['X-Legado-Final-Url'] = Uri.encodeComponent(finalUrl);"));
      expect(netLog,
          contains("out['X-Legado-Redirects'] = b64Json(entry.redirects);"));
      expect(code, contains('X-Legado-RespHeaders'));
      expect(code, contains('X-Legado-Final-Url'));
    });

    test('登录头合并到原生请求头', () {
      expect(wv, contains('Future<Map<String, String>> _sourceHeaders()'));
      expect(wv, contains('loginHeader_'));
      expect(wv, contains('SharedPreferences.getInstance()'));
    });

    test('批量协议解析 isTest、限流旁路并桥接超时', () {
      expect(wv, contains("decoded['isTest'] == true"));
      expect(wv, contains("decoded['skipRateLimit'] == true"));
      expect(wv, contains('Future<Map<String, dynamic>> _fetchOneAjax('));
    });

    test('WebView 抓取具备轮询、编码与 Cookie 回收', () {
      expect(
          headless, contains('const pollDelays = [200, 400, 600, 800, 1000]'));
      expect(headless, contains("encoding: encode.isEmpty ? 'utf-8' : encode"));
      expect(headless, contains('static Future<void> _collectCookies('));
      expect(headless, contains('legadoTagCookie_'));
      expect(headless, contains('useShouldInterceptRequest: regex != null'));
    });
  });
}
