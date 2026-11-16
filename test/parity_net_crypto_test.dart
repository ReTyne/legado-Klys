import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart' as archive;
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legado_md3/help/http/cookie_manager.dart';
import 'package:legado_md3/help/http/http_response_decoder.dart';
import 'package:legado_md3/help/http/proxy_client.dart';
import 'package:legado_md3/help/http/ssl_helper.dart';
import 'package:legado_md3/help/http/str_response.dart';
import 'package:legado_md3/utils/cookie_util.dart' as cu;
import 'package:legado_md3/utils/crypto_utils.dart';

const String _privateKeyPem = '''-----BEGIN RSA PRIVATE KEY-----
MIICXAIBAAKBgQDPsfgafuch16qowqrxTc2OE/JoFaMpNFtmsoj3w2WN30Jpo21w
gHMfFVmubD/2En5QMw2u7wL2Sn+KJUeNd7xRJl2juP9hREsR3bp7qtpn+Lv81kf1
Mo5tW9FcFgz0L2US2Qw7jznbjiiAUmAHialee9N8sAe7s3wIgtx2RsnMIQIDAQAB
AoGBAI9B3jPIXHyHWXtV6rrOQ35AW+9XHVeKeZD4jGj5Kc8Vs6VRyGbU8pL6EwWw
PN3qG54N2N5UleJzuEz9McFuWUEQyNEAk5vDBc/kcpmSy6rctL4Awtvv72F1uAyJ
ZzWnQDTGGFvbIkkN/iqPhq0Ec3bLaRi63LeQkc3sm5YKPbBRAkEA+xfZhb/s7xE8
Cxd4/wO8t+SGDK7UAaBaOi1SHOC0QffKyw9q7BOa7Zffqr6vBYgzWwG6wPW8HYkn
7sH3SWsSJwJBANPBAuR1L2KmcHA9w2qi9zqXehvkIRt7SOcwFr3HSo9zyF69FNkS
4hhhXtx+uqc9IFoQUu9hFqOZxPlDO8p+RHcCQFdjeJBFONgHfoc5tyHCEjdKMKFP
Y3fhcCWZSl/EkNf4vrqndgYN2LjiR7TsQovBWGZPFsk7fSomZyCAn2kM+7cCQHqm
qU46sh+p2CarH618h0bgxlGxaZvJZQjDyehSrtU4cy6sxo6VaXBFtfRxUxvbRAnm
uqL80WghgP3/+3nmeTECQH+O1oPc2LNSaQkccsoungxVymt9s6PBRdkK3VgBzJoH
YXw9n+c0A233m6T3b6OxZlYYJjAHzGu3pqwfkG2bcQw=
-----END RSA PRIVATE KEY-----''';

const String _publicKeyPem = '''-----BEGIN PUBLIC KEY-----
MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDPsfgafuch16qowqrxTc2OE/Jo
FaMpNFtmsoj3w2WN30Jpo21wgHMfFVmubD/2En5QMw2u7wL2Sn+KJUeNd7xRJl2j
uP9hREsR3bp7qtpn+Lv81kf1Mo5tW9FcFgz0L2US2Qw7jznbjiiAUmAHialee9N8
sAe7s3wIgtx2RsnMIQIDAQAB
-----END PUBLIC KEY-----''';

List<int> _bytes(String s) => utf8.encode(s);
String _hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  // ------------------------------------------------------------------
  group('代理配置', () {
    test('ProxyConfig.parse 解析 http 与 user:pass 认证', () {
      final c = ProxyConfig.parse('http://user:pass@127.0.0.1:8080')!;
      expect(c.scheme, ProxyScheme.http);
      expect(c.host, '127.0.0.1');
      expect(c.port, 8080);
      expect(c.username, 'user');
      expect(c.password, 'pass');
      expect(c.hasAuth, isTrue);
      expect(c.findProxyValue, 'PROXY 127.0.0.1:8080');
      expect(
          c.proxyAuthorization, 'Basic ${base64.encode(_bytes('user:pass'))}');
    });

    test('ProxyConfig.parse 支持 socks4/socks5 与默认端口', () {
      final s5 = ProxyConfig.parse('socks5://10.0.0.1:1080')!;
      expect(s5.scheme, ProxyScheme.socks5);
      expect(s5.hasAuth, isFalse);
      expect(s5.proxyAuthorization, isNull);
      final s4 = ProxyConfig.parse('socks4://proxy.local')!;
      expect(s4.scheme, ProxyScheme.socks4);
      expect(s4.port, 1080);
      expect(ProxyConfig.parse('ftp://x'), isNull);
    });

    test('ProxyClient.fromHeaders 提取 proxy 头并剥离', () {
      final headers = <String, String>{
        'User-Agent': 'ua',
        'proxy': 'http://u:p@h:9',
      };
      final cfg = ProxyClient.fromHeaders(headers)!;
      expect(cfg.host, 'h');
      expect(cfg.port, 9);
      expect(headers.containsKey('proxy'), isFalse);
      expect(headers['User-Agent'], 'ua');
      expect(ProxyClient.fromHeaders(<String, String>{'a': 'b'}), isNull);
    });

    test('ProxyClient.apply 配置适配器与 Proxy-Authorization 头', () {
      final dio = Dio();
      final cfg = ProxyConfig.parse('http://user:pass@127.0.0.1:8080')!;
      ProxyClient.apply(dio, cfg);
      expect(dio.httpClientAdapter, isA<IOHttpClientAdapter>());
      expect(dio.options.headers['Proxy-Authorization'],
          'Basic ${base64.encode(_bytes('user:pass'))}');
    });

    test('SslHelper.attach 全信任开关安全生效', () {
      final dio = Dio();
      SslHelper.attach(dio, trustAll: true);
      expect(dio.httpClientAdapter, isA<IOHttpClientAdapter>());
      SslHelper.allowAll = false;
      SslHelper.attach(dio, trustAll: true);
      SslHelper.allowAll = true;
      expect(dio.httpClientAdapter, isA<IOHttpClientAdapter>());
    });
  });

  // ------------------------------------------------------------------
  group('摘要与 HMAC', () {
    test('7 种摘要算法匹配已知向量', () {
      expect(digestHex('abc', 'MD5'), '900150983cd24fb0d6963f7d28e17f72');
      expect(
          digestHex('abc', 'SHA1'), 'a9993e364706816aba3e25717850c26c9cd0d89d');
      expect(digestHex('abc', 'SHA224'),
          '23097d223405d8228642a477bda255b32aadbce4bda0b3f7e36c9da7');
      expect(digestHex('abc', 'SHA256'),
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
      expect(digestHex('abc', 'SHA384'),
          'cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed8086072ba1e7cc2358baeca134c825a7');
      expect(digestHex('abc', 'SHA512'),
          'ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f');
      expect(digestHex('abc', 'SM3'),
          '66c7f0f462eeedd9d1f2d46bdc10e4e24167c4875cf2f7a2297da02b8f4ba8e0');
    });

    test('MD2 摘要匹配 RFC 1319 已知向量（含多块输入）', () {
      expect(digestHex('', 'MD2'), '8350e5a3e24c153df2275c9f80692773');
      expect(digestHex('abc', 'MD2'), 'da853b0d3f88d99b30283a69e6ded6bb');
      expect(digestHex('abcdefghijklmnopqrstuvwxyz', 'MD2'),
          '4e8ddff3650292ab5a4108c3aa47940b');
      expect(
          digestHex(
              'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789',
              'MD2'),
          'da33def2a42df13975352846c30338cd');
      final h = digestHex('abc', 'MD2');
      expect(h.length, 32);
      expect(_hex(digestBytes(_bytes('abc'), 'MD2')), h);
    });

    test('摘要算法名大小写与连字符归一化', () {
      expect(digestHex('abc', 'sha-256'), digestHex('abc', 'SHA256'));
      expect(digestHex('abc', 'SHA_384'), digestHex('abc', 'SHA384'));
      expect(digestHex('abc', 'sm3'), digestHex('abc', 'SM3'));
      expect(
          CryptoUtils.digestHex('abc', 'SHA256'), digestHex('abc', 'SHA256'));
    });

    test('未知摘要算法抛明确异常', () {
      expect(() => digestHex('x', 'NOPE'), throwsArgumentError);
      expect(() => CryptoUtils.digestHex('x', 'NOPE2'), throwsArgumentError);
    });

    test('digestBase64 与 digestBytes 编码一致', () {
      final b = digestBytes(_bytes('abc'), 'SHA256');
      expect(b.length, 32);
      expect(base64.decode(digestBase64('abc', 'SHA256')), b);
      expect(CryptoUtils.digestBase64('abc', 'SHA256'),
          digestBase64('abc', 'SHA256'));
    });

    test('HMAC 6 种算法匹配已知向量', () {
      const d = 'what do ya want for nothing?';
      const k = 'Jefe';
      expect(hmacHex(d, k, 'HmacMD5'), '750c783e6ab0b503eaa86e310a5db738');
      expect(hmacHex(d, k, 'HmacSHA1'),
          'effcdf6ae5eb2fa2d27416d5f184df9c259a7c79');
      expect(hmacHex(d, k, 'HmacSHA224'),
          'a30e01098bc6dbbf45690f3a7e9e6d0f8bbea2a39e6148008fd05e44');
      expect(hmacHex(d, k, 'HmacSHA256'),
          '5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843');
      expect(hmacHex(d, k, 'HmacSHA384'),
          'af45d2e376484031617f78d2b58a6b1b9c7ef464f5a01b47e42ec3736322445e8e2240ca5e69e2c78b3239ecfab21649');
      expect(hmacHex(d, k, 'HmacSHA512'),
          '164b7a7bfcf819e2e395fbe73b56e0a387bd64222e831fd610270cd7ea2505549758bf75c05a994a6d034f65f8f0e6fdcaeab1a34d4a6b4b636e070a38bce737');
    });

    test('HMAC 前缀与大小写归一化 + hmacBase64 一致', () {
      const d = 'what do ya want for nothing?';
      const k = 'Jefe';
      expect(hmacHex(d, k, 'hmac-sha256'), hmacHex(d, k, 'HmacSHA256'));
      expect(hmacHex(d, k, 'SHA256'), hmacHex(d, k, 'HmacSHA256'));
      expect(base64.decode(hmacBase64(d, k, 'HmacSHA256')),
          listFromHex(hmacHex(d, k, 'HmacSHA256')));
      expect(() => hmacHex(d, k, 'HmacSM9'), throwsArgumentError);
    });
  });

  // ------------------------------------------------------------------
  group('对称加密', () {
    const key = '0123456789abcdef';
    const iv = '12345678';
    const plain = 'hello 世界 12345';

    test('ISO10126 填充 round-trip 且尾块随机', () {
      final c = SymmetricCrypto('AES/CBC/ISO10126Padding', key, iv: iv);
      final e1 = c.encrypt(_bytes(plain));
      final e2 = c.encrypt(_bytes(plain));
      expect(e1, isNot(e2));
      expect(utf8.decode(c.decryptBytes(e1)), plain);
      expect(utf8.decode(c.decryptBytes(e2)), plain);
    });

    test('CTR round-trip（非对齐长度）', () {
      final data =
          Uint8List.fromList(List<int>.generate(37, (i) => (i * 3 + 1) & 0xff));
      final c = SymmetricCrypto('AES/CTR/NoPadding', key, iv: iv);
      expect(c.decryptBytes(c.encrypt(data)), data);
    });

    test('CFB round-trip（非对齐长度）', () {
      final data =
          Uint8List.fromList(List<int>.generate(37, (i) => (i * 5 + 2) & 0xff));
      final c = SymmetricCrypto('AES/CFB/NoPadding', key, iv: iv);
      expect(c.decryptBytes(c.encrypt(data)), data);
    });

    test('OFB / PCBC round-trip', () {
      final data = _bytes('PCBC 与 OFB 内容');
      final ofb = SymmetricCrypto('AES/OFB/NoPadding', key, iv: iv);
      expect(utf8.decode(ofb.decryptBytes(ofb.encrypt(data))), 'PCBC 与 OFB 内容');
      final pcbc = SymmetricCrypto('AES/PCBC/PKCS5Padding', key, iv: iv);
      expect(
          utf8.decode(pcbc.decryptBytes(pcbc.encrypt(data))), 'PCBC 与 OFB 内容');
    });

    test('NoPadding 非对齐数据抛明确异常', () {
      final c = SymmetricCrypto('AES/ECB/NoPadding', key);
      expect(() => c.encrypt(Uint8List(5)), throwsArgumentError);
    });

    test('GCM 明确抛不支持', () {
      expect(
          () => SymmetricCrypto('AES/GCM/NoPadding', key), throwsArgumentError);
    });

    test('算法名归一化 3DES / SMS4 / ARCFOUR round-trip', () {
      for (final t in [
        '3DES/ECB/PKCS5Padding',
        'SMS4/ECB/PKCS5Padding',
        'ARCFOUR'
      ]) {
        final c = SymmetricCrypto(t, '1234567890abcdef12345678');
        expect(c.decryptStr(c.encrypt(_bytes('归一化'))), '归一化', reason: t);
      }
    });

    test('key=null 生成随机密钥并可 getKey 取回', () {
      final c1 = SymmetricCrypto('AES/ECB/PKCS5Padding', null);
      final c2 = SymmetricCrypto('AES/ECB/PKCS5Padding', null);
      expect(c1.getKey().length, 16);
      expect(c1.getKeyBase64(), isNotEmpty);
      expect(c1.getKeyHex(), _hex(c1.getKey()));
      expect(_hex(c1.getKey()), isNot(_hex(c2.getKey())));
      final reused = SymmetricCrypto('AES/ECB/PKCS5Padding', c1.getKey());
      expect(reused.decryptStr(c1.encrypt(_bytes('随机密钥'))), '随机密钥');
    });

    test('encryptHex / decryptHex / decryptBase64 round-trip', () {
      final c = SymmetricCrypto('AES/CBC/PKCS5Padding', key, iv: iv);
      expect(c.decryptHex(c.encryptHex(_bytes(plain))), plain);
      expect(c.decryptBase64(c.encryptBase64(_bytes(plain))), plain);
    });
  });

  // ------------------------------------------------------------------
  group('非对称与签名', () {
    test('公钥加密 / 私钥解密 round-trip', () {
      final ac = AsymmetricCrypto('RSA/ECB/PKCS1Padding',
          publicKey: _publicKeyPem, privateKey: _privateKeyPem);
      expect(ac.decryptStr(ac.encrypt(_bytes('公钥加密内容'))), '公钥加密内容');
      expect(ac.decryptStr(ac.encryptHex(_bytes('hex 形式'))), 'hex 形式');
    });

    test('usePublicKey=false 私钥加密 round-trip', () {
      final ac = AsymmetricCrypto('RSA/ECB/PKCS1Padding',
          publicKey: _publicKeyPem, privateKey: _privateKeyPem);
      final cipher = ac.encrypt(_bytes('私钥加密内容'), usePublicKey: false);
      expect(utf8.decode(ac.decrypt(cipher, usePublicKey: true)), '私钥加密内容');
    });

    test('CryptoUtils.asymEncryptHex 门面 round-trip', () {
      final hexCipher = CryptoUtils.asymEncryptHex(
          'RSA/ECB/PKCS1Padding', _publicKeyPem, '门面内容');
      final ac =
          AsymmetricCrypto('RSA/ECB/PKCS1Padding', privateKey: _privateKeyPem);
      expect(ac.decryptStr(hexCipher), '门面内容');
      final privHex = CryptoUtils.asymEncryptHex(
          'RSA/ECB/PKCS1Padding', _privateKeyPem, '反向',
          usePublicKey: false);
      final ac2 =
          AsymmetricCrypto('RSA/ECB/PKCS1Padding', publicKey: _publicKeyPem);
      expect(utf8.decode(ac2.decrypt(privHex, usePublicKey: true)), '反向');
    });

    test('RsaSign 按 algorithm 选 hash 并 sign/verify round-trip', () {
      final s256 = RsaSign('SHA256withRSA',
          privateKey: _privateKeyPem, publicKey: _publicKeyPem);
      expect(s256.hashAlgorithm, 'SHA256');
      expect(s256.verify(_bytes('签名数据'), s256.signHex(_bytes('签名数据'))), isTrue);
      expect(
          s256.verify(_bytes('签名数据'), s256.signBase64(_bytes('签名数据'))), isTrue);
      final s1 = RsaSign('SHA1withRSA',
          privateKey: _privateKeyPem, publicKey: _publicKeyPem);
      expect(s1.hashAlgorithm, 'SHA1');
      expect(s1.verify(_bytes('x'), s1.signHex(_bytes('x'))), isTrue);
    });

    test('CryptoUtils.signHex / signBase64 / verify 门面', () {
      const data = '门面签名数据';
      final h = CryptoUtils.signHex('SHA256withRSA', _privateKeyPem, data);
      expect(
          CryptoUtils.verify('SHA256withRSA', _publicKeyPem, data, h), isTrue);
      final b = CryptoUtils.signBase64('SHA256withRSA', _privateKeyPem, data);
      expect(
          CryptoUtils.verify('SHA256withRSA', _publicKeyPem, data, b), isTrue);
      expect(CryptoUtils.verify('SHA256withRSA', _publicKeyPem, '${data}x', h),
          isFalse);
    });
  });

  // ------------------------------------------------------------------
  group('Cookie 语义', () {
    final cm = CookieManager();

    setUp(() => cm.clear());

    test('Set-Cookie 属性解析与 path 匹配', () {
      final sc = cu.parseSetCookie(
        'sid=abc; Domain=.biquge.com.cn; Path=/foo; '
        'Expires=Wed, 09 Jun 2027 10:18:14 GMT; Max-Age=3600; '
        'Secure; HttpOnly',
        defaultPath: '/',
      )!;
      expect(sc.name, 'sid');
      expect(sc.value, 'abc');
      expect(sc.domain, 'biquge.com.cn');
      expect(sc.path, '/foo');
      expect(sc.expires, isNotNull);
      expect(sc.maxAge, 3600);
      expect(sc.secure, isTrue);
      expect(sc.httpOnly, isTrue);
      expect(sc.isSession, isFalse);
      expect(cu.parseSetCookie('k=v; Path=/')!.isSession, isTrue);
      expect(cu.cookiePathMatch('/foo/bar', '/foo'), isTrue);
      expect(cu.cookiePathMatch('/foobar', '/foo'), isFalse);
    });

    test('会话与持久 cookie 分层', () {
      cm.saveFromResponse('https://www.biquge.com.cn/foo/page', [
        'sessionA=1; Path=/foo',
        'persistA=2; Max-Age=3600; Path=/',
        'secureA=3; Secure; Path=/',
      ]);
      expect(cm.sessionCount, 2);
      expect(cm.persistentCount, 1);
      final https = cm.cookieHeader('https://www.biquge.com.cn/foo/page')!;
      expect(https, contains('sessionA=1'));
      expect(https, contains('secureA=3'));
      final http = cm.cookieHeader('http://www.biquge.com.cn/foo/page')!;
      expect(http, isNot(contains('secureA=3')));
      cm.clearSession();
      expect(cm.sessionCount, 0);
      expect(cm.persistentCount, 1);
    });

    test('eTLD+1 域键跨子域共享、跨站隔离', () {
      expect(cu.getSubDomain('http://www.biquge.com.cn/x'), 'biquge.com.cn');
      expect(cu.getSubDomain('https://www.content.example.com'), 'example.com');
      expect(cu.getSubDomain('http://1.2.3.4:8080/x'), '1.2.3.4');
      cm.saveFromResponse('https://www.biquge.com.cn/', ['k=v; Path=/']);
      expect(cm.cookieHeader('https://api.biquge.com.cn/'), 'k=v');
      expect(cm.cookieHeader('https://www.example.com/'), isNull);
    });

    test('4096 字节上限淘汰最旧键', () {
      for (var i = 0; i < 40; i++) {
        cm.saveFromResponse(
            'https://limit.example.com/', ['k$i=${'V' * 200}; Path=/']);
      }
      final size = cm.cookieByteSize('https://limit.example.com/');
      expect(size, lessThanOrEqualTo(CookieManager.maxCookieBytes));
      final header = cm.cookieHeader('https://limit.example.com/')!;
      expect(header, isNot(contains('k0=')));
      expect(header, contains('k39='));
    });

    test('replaceCookie 合并旧值 + map 互转 + clear/removeHost', () {
      cm.saveFromResponse(
          'https://www.example.com/a/page', ['a=1; Path=/a', 'b=2; Path=/']);
      cm.replaceCookie('https://www.example.com/a/page', 'a=NEW; c=3');
      final header = cm.cookieHeader('https://www.example.com/a/page')!;
      expect(header, contains('a=NEW'));
      expect(header, contains('b=2'));
      expect(header, contains('c=3'));
      expect(cm.cookieToMap('x=1; y=2'), {'x': '1', 'y': '2'});
      expect(cm.mapToCookie({'x': '1', 'y': '2'}), 'x=1; y=2');
      cm.removeHost('www.example.com');
      expect(cm.cookieHeader('https://www.example.com/'), isNull);
      cm.clear();
      expect(cm.sessionCount, 0);
      expect(cm.persistentCount, 0);
    });
  });

  // ------------------------------------------------------------------
  group('响应解码与 StrResponse', () {
    test('application/zip 响应体解压取首个条目', () {
      final arc = archive.Archive();
      final data = _bytes('zip 首个条目内容');
      arc.addFile(archive.ArchiveFile('a.txt', data.length, data));
      final zipped = archive.ZipEncoder().encode(arc)!;
      final out = HttpResponseDecoder.decompress(zipped,
          contentType: 'application/zip');
      expect(utf8.decode(out), 'zip 首个条目内容');
    });

    test('brotli 无解码库安全降级返回原字节', () {
      final raw = _bytes('brotli-original');
      final out = HttpResponseDecoder.decompress(raw, contentEncoding: 'br');
      expect(out, raw);
    });

    test('gzip 解压逻辑保持', () {
      final plain = _bytes('gzip body');
      final zipped = archive.GZipEncoder().encode(plain)!;
      expect(HttpResponseDecoder.decompress(zipped, contentEncoding: 'gzip'),
          plain);
    });

    test('StrResponse getter 方法与 toString / putCallTime', () {
      final r = StrResponse(
          body: '正文', url: 'https://a/x', code: 201, headers: const {'k': 'v'});
      expect(r.body(), '正文');
      expect(r.raw(), '正文');
      expect(r.url(), 'https://a/x');
      expect(r.code(), 201);
      expect(r.message(), 'OK');
      expect(r.headers(), {'k': 'v'});
      expect(r.isSuccessful(), isTrue);
      expect(r.errorBody(), '');
      expect(r.toString(), '正文');
      expect(r.toMap()['body'], '正文');
      r.putCallTime(42);
      expect(r.callTime(), 42);
      expect(StrResponse(code: 404).isSuccessful(), isFalse);
    });

    test('StrResponse.fromRedirect 构造 302/200 双层', () {
      final r = StrResponse.fromRedirect(302, 'https://b/y', 'https://final/z');
      expect(r.code(), 200);
      expect(r.url(), 'https://final/z');
      expect(r.isSuccessful(), isTrue);
      final layer = r.redirectResponse()!;
      expect(layer.code(), 302);
      expect(layer.headers()['Location'], 'https://b/y');
      expect(layer.isSuccessful(), isTrue);
    });
  });
}

/// 十六进制字符串转字节列表，便于比对 base64 解码结果。
List<int> listFromHex(String hex) {
  final out = <int>[];
  for (var i = 0; i < hex.length; i += 2) {
    out.add(int.parse(hex.substring(i, i + 2), radix: 16));
  }
  return out;
}
