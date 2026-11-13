import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:legado_md3/help/source/source_network_log.dart';
import 'package:legado_md3/help/source/ttf_parser.dart';
import 'package:legado_md3/utils/crypto_utils.dart';

/// 引擎能力真实行为验证：对称加密、字体查询数据、网络日志头信息字段。
/// 与源码契约测试互补——这里直接调用可执行的 Dart 实现。
void main() {
  group('SymmetricCrypto 原生对称加解密', () {
    const cases = <String, String>{
      'AES/ECB/PKCS5Padding': '0123456789abcdef',
      'AES/CBC/PKCS5Padding': '0123456789abcdef',
      'DES/ECB/PKCS5Padding': '8bytekey',
      'DESede/CBC/PKCS5Padding': '123456789012345678901234',
      '3DES/ECB/PKCS5Padding': '123456789012345678901234',
      'SM4/ECB/PKCS5Padding': '1234567890abcdef',
      'RC4': 'rc4secret',
    };

    for (final entry in cases.entries) {
      test('${entry.key} round-trip', () {
        final plain = utf8.encode('hello世界 123');
        final cipher = SymmetricCrypto(
          entry.key,
          utf8.encode(entry.value),
          iv: Uint8List.fromList(utf8.encode('12345678')),
        );
        final enc = cipher.encrypt(plain);
        final dec = cipher.decryptBytes(enc);
        expect(utf8.decode(dec), 'hello世界 123');
      });
    }

    test('base64 编码的 key/iv 解码路径（legado://crypto 载荷）', () {
      final kb = base64Decode(base64.encode(utf8.encode('123456789012345678901234')));
      final ivb = base64Decode(base64.encode(utf8.encode('12345678')));
      final cipher = SymmetricCrypto(
        'DESede/CBC/PKCS5Padding',
        Uint8List.fromList(kb),
        iv: Uint8List.fromList(ivb),
      );
      final enc = cipher.encrypt(Uint8List.fromList(utf8.encode('payload')));
      expect(cipher.decryptStr(enc), 'payload');
    });
  });

  group('TtfParser 字体查询结构化数据', () {
    test('空/非法数据不抛异常，返回空结构', () {
      final parser = TtfParser.fromBytes(const [0, 1, 2, 3]);
      // 无有效表目录时 parseCmap/parsePost 均安全降级
      final data = parser.buildQueryData();
      expect(data['replacement'], isA<Map>());
      expect(data['unicodeToGlyphId'], isA<Map>());
      expect(data['unicodeToGlyph'], isA<Map>());
      expect(data['glyphToUnicode'], isA<Map>());
    });
  });

  group('SourceNetworkEntry 头信息与重定向字段', () {
    test('toJson 含请求头/响应头/最终地址/重定向链', () {
      final entry = SourceNetworkEntry(
        time: DateTime(2026, 1, 1, 12, 0, 0),
        url: 'https://a.example/x',
        method: 'GET',
        origin: 'js-ajax',
        statusCode: 200,
        requestHeaders: const {'Cookie': 'k=v', 'User-Agent': 'test'},
        responseHeaders: const {'content-type': 'text/html', 'set-cookie': 'a=b'},
        finalUrl: 'https://b.example/y',
        redirects: const ['https://a.example/x', 'https://b.example/y'],
      );
      final json = entry.toJson();
      expect(json['requestHeaders'], isA<Map>());
      expect((json['requestHeaders'] as Map)['Cookie'], 'k=v');
      expect((json['responseHeaders'] as Map)['content-type'], 'text/html');
      expect(json['finalUrl'], 'https://b.example/y');
      expect(json['redirects'], ['https://a.example/x', 'https://b.example/y']);
    });

    test('hasRedirect 在无跳转时为 false，最终地址不同时为 true', () {
      final noRedirect = SourceNetworkEntry(
        time: DateTime(2026),
        url: 'https://a.example/x',
        method: 'GET',
        origin: 'engine',
        finalUrl: 'https://a.example/x',
      );
      expect(noRedirect.hasRedirect, isFalse);

      final redirected = SourceNetworkEntry(
        time: DateTime(2026),
        url: 'https://a.example/x',
        method: 'GET',
        origin: 'engine',
        finalUrl: 'https://b.example/y',
        redirects: const ['https://a.example/x', 'https://b.example/y'],
      );
      expect(redirected.hasRedirect, isTrue);
    });
  });
}
