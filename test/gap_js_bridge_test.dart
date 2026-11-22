import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:legado_md3/help/source/js/legado_bridge_js.dart';
import 'package:legado_md3/help/source/js/offline_js_bridge.dart';

const _root = '/workspace/legado-Klys/legado-Klys-main/';
String _src(String rel) => File('$_root$rel').readAsStringSync();

void main() {
  group('缺口1 状态注入', () {
    test('JsSource 提供带默认实现的 loginUi getter', () {
      expect(_src('lib/help/source/js/js_source.dart'),
          contains("String? get loginUi => '';"));
    });

    test('loadSource seed 注入全部书源字段到 __state.meta', () {
      final s = _src('lib/help/source/js/parts/web_view_legado_js.dart');
      for (final k in [
        'src.jsGroup',
        'src.jsComment',
        'src.jsType',
        'src.jsConcurrentRate',
        'src.jsEnabledExplore',
        'src.header',
        'src.loginUrl',
        'src.loginUi',
        'src.jsLib',
        'src.jsBookUrlPattern'
      ]) {
        expect(s, contains(k), reason: 'seed 未注入 $k');
      }
    });

    test('bridge getter 从 __state.meta 读取书源字段', () {
      const code = LegadoBridgeJs.code;
      for (final k in [
        'getBookSourceGroup',
        'getBookSourceComment',
        'getBookSourceType',
        'getConcurrentRate',
        'getEnabledExplore',
        'getHeader',
        'getLoginUrl',
        'getJsLib',
        'getBookUrlPattern'
      ]) {
        expect(code, contains('$k: function'), reason: '缺少 $k');
      }
      expect(code, contains('__state.meta.group'));
      expect(code, contains('__state.meta.concurrentRate'));
      expect(code, contains('__state.meta.bookUrlPattern'));
    });
  });

  group('缺口2 书源级请求头', () {
    test('__doXhr 先合并 source.getHeaderMap() 再让 opt.headers 覆盖', () {
      const code = LegadoBridgeJs.code;
      final iBase = code.indexOf('baseHeaders = source.getHeaderMap()');
      final iOpt = code.indexOf('Object.keys(opt.headers || {}).forEach', iBase);
      expect(iBase, greaterThan(0));
      expect(iOpt, greaterThan(iBase), reason: 'opt.headers 必须后写以覆盖书源头');
    });
  });

  group('缺口3 阅读/主题配置', () {
    test('配置 getter 读注入快照，loadSource 从 prefs 注入真实配置', () {
      const code = LegadoBridgeJs.code;
      expect(code, contains('__state.readConfig'));
      expect(code, contains('__state.theme'));
      expect(code, contains('__state.themeMode'));
      final s = _src('lib/help/source/js/parts/web_view_legado_js.dart');
      expect(s, contains("prefs.getString('read_config_json')"));
      expect(s, contains("prefs.getInt('theme_mode')"));
      expect(s, contains('__state.readConfig = \$readConfig'));
    });
  });

  group('缺口4 AES 模式委托原生', () {
    test('非 ECB/CBC 或非常规填充委托 __nativeCrypto', () {
      const code = LegadoBridgeJs.code;
      expect(code, contains('function __aesFastPath'));
      expect(code, contains('__nativeCrypto("decryptBytes", t'));
      expect(code, contains('__nativeCrypto("encrypt", t'));
      expect(code, contains('var nativeOnly = !__aesFastPath(t);'));
    });
  });

  group('缺口5 base64Decode charset', () {
    test('第二参为字符集时按 bytesToStr 解码', () {
      const code = LegadoBridgeJs.code;
      expect(code, contains('function __b64Charset'));
      expect(code, contains('java.bytesToStr(__b64ToBytes(s), cs)'));
    });
  });

  group('缺口6 非对称签名', () {
    test('encrypt/decrypt 逐次 usePub 且返回字节数组', () {
      const code = LegadoBridgeJs.code;
      expect(code, contains('encrypt: function (data, usePub)'));
      expect(code, contains('decrypt: function (data, usePub)'));
      expect(code, contains('call("encryptBytes"'));
      expect(code, contains('call("decryptBytes"'));
      // transformation 透传到 op=asym 门面
      expect(code, contains('op: "asym", sub: sub, transformation: t'));
      final dartSrc =
          _src('lib/help/source/js/parts/web_view_legado_js.dart');
      expect(dartSrc, contains("case 'encryptBytes':"));
      expect(dartSrc, contains("case 'decryptBytes':"));
      expect(
          dartSrc, contains('crypto.encrypt(data, usePublicKey: usePublicKey)'));
    });
  });

  group('缺口7 Thread.sleep', () {
    test('Packages.java.lang.Thread.sleep 走忙等实现', () {
      const code = LegadoBridgeJs.code;
      expect(code, contains('Thread: { sleep: __pkgSleep }'));
      expect(code, contains('function __pkgSleep(ms)'));
      expect(code, isNot(contains('Thread: { sleep: function () {} }')));
    });
  });

  group('缺口8 jsLibInvalidated 刷新', () {
    test('loadSource 读取并清除标记，绕过同源早退重注入 jsLib', () {
      final s = _src('lib/help/source/js/parts/web_view_legado_js.dart');
      expect(s, contains("final invalidKey = 'jsLibInvalidated_\${src.jsUrl}'"));
      expect(s, contains('prefs.remove(invalidKey)'));
      expect(s,
          contains('if (!forceReload && _loadedSourceUrl == src.jsUrl) return;'));
      // 写入标记的一端仍在
      expect(s, contains("'jsLibInvalidated_\${source.jsUrl}'"));
    });
  });

  group('缺口9 3DES 识别', () {
    test('DESede/3DES 走三次 DES，24 字节密钥 round-trip', () {
      final key = List<int>.generate(24, (i) => i + 1);
      final c =
          JsBridgeCrypto.createSymmetricCrypto('DESede/ECB/PKCS5Padding', key);
      const plain = '三DES明文roundtrip';
      final enc = c.encryptBase64(plain);
      final bytes = JsBridgeCodec.base64DecodeToByteArray(enc);
      expect(bytes, isNotEmpty);
      expect(c.decryptStr(bytes), plain);
      // 单 DES 行为不变
      final d =
          JsBridgeCrypto.createSymmetricCrypto('DES/ECB/PKCS5Padding', '12345678');
      expect(
          d.decryptStr(
              JsBridgeCodec.base64DecodeToByteArray(d.encryptBase64('DES单倍'))),
          'DES单倍');
    });
  });
}
