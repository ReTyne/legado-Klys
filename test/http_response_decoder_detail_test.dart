import 'dart:convert';
import 'dart:io' show gzip, zlib;
import 'dart:typed_data';

import 'package:enough_convert/enough_convert.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legado_md3/help/http/http_response_decoder.dart';

/// 对照 legado-E `DecompressInterceptor` / `Utf8BomUtils` /
/// `ResponseBody.text()` / `EncodingDetect.getHtmlEncode()` 的响应解码细节。
void main() {
  Map<String, List<String>> h(Map<String, String> src) =>
      src.map((k, v) => MapEntry(k, [v]));

  List<int> gbk(String s) => const GbkCodec().encode(s);

  group('透明解压（DecompressInterceptor）', () {
    test('Content-Encoding: gzip 解压', () {
      final plain = utf8.encode('<html>你好 hello</html>');
      final zipped = gzip.encode(plain);
      expect(HttpResponseDecoder.decompress(zipped, contentEncoding: 'gzip'),
          plain);
    });

    test('gzip 魔数兜底（无响应头也解压）', () {
      final plain = utf8.encode('gzip body');
      expect(HttpResponseDecoder.decompress(gzip.encode(plain)), plain);
    });

    test('Content-Encoding: deflate（zlib 包裹）解压', () {
      final plain = utf8.encode('deflate zlib body');
      expect(
        HttpResponseDecoder.decompress(zlib.encode(plain),
            contentEncoding: 'deflate'),
        plain,
      );
    });

    test('Content-Encoding: deflate 的 raw deflate（Inflater(true)）解压', () {
      final plain = utf8.encode('raw deflate body');
      final wrapped = zlib.encode(plain);
      // 去掉 2 字节 zlib 头与 4 字节 adler32 尾 → raw deflate 流
      final raw = wrapped.sublist(2, wrapped.length - 4);
      expect(
        HttpResponseDecoder.decompress(raw, contentEncoding: 'deflate'),
        plain,
      );
    });

    test('Range 请求跳过解压（206 分片不可解压）', () {
      final zipped = gzip.encode(utf8.encode('part'));
      expect(
        HttpResponseDecoder.decompress(zipped,
            contentEncoding: 'gzip', rangeRequested: true),
        zipped,
      );
    });

    test('非压缩数据原样返回', () {
      final plain = utf8.encode('plain text');
      expect(HttpResponseDecoder.decompress(plain), plain);
    });

    test('端到端：gzip + UTF-8 BOM 一起处理', () {
      final body = [0xEF, 0xBB, 0xBF, ...utf8.encode('中文内容')];
      expect(
        HttpResponseDecoder.decode(gzip.encode(body),
            headers: h({'Content-Encoding': 'gzip'})),
        '中文内容',
      );
    });
  });

  group('去 BOM（Utf8BomUtils）', () {
    test('UTF-8 BOM 被剥离并标记 utf-8', () {
      final r = HttpResponseDecoder.removeBom(
          [0xEF, 0xBB, 0xBF, ...utf8.encode('abc')]);
      expect(r.bytes, utf8.encode('abc'));
      expect(r.charset, 'utf-8');
    });

    test('UTF-16 LE/BE BOM 被剥离并标记字节序', () {
      final le = HttpResponseDecoder.removeBom([0xFF, 0xFE, 0x61, 0x00]);
      expect(le.charset, 'utf-16le');
      expect(le.bytes, [0x61, 0x00]);
      final be = HttpResponseDecoder.removeBom([0xFE, 0xFF, 0x00, 0x61]);
      expect(be.charset, 'utf-16be');
      expect(be.bytes, [0x00, 0x61]);
    });

    test('无 BOM 原样返回', () {
      final bytes = utf8.encode('abc');
      final r = HttpResponseDecoder.removeBom(bytes);
      expect(r.bytes, bytes);
      expect(r.charset, isNull);
    });

    test('decode 输出不含 BOM 字符', () {
      expect(
        HttpResponseDecoder.decode(
            [0xEF, 0xBB, 0xBF, ...utf8.encode('标题')]),
        '标题',
      );
    });

    test('UTF-16 LE 带 BOM 端到端解码', () {
      // 「中文」的 UTF-16 LE 码元
      expect(
        HttpResponseDecoder.decode([0xFF, 0xFE, 0x2D, 0x4E, 0x87, 0x65]),
        '中文',
      );
    });
  });

  group('编码优先级（ResponseBody.text + EncodingDetect）', () {
    test('forcedCharset 优先级最高', () {
      expect(
        HttpResponseDecoder.decode(gbk('中文'),
            headers: h({'Content-Type': 'text/html; charset=utf-8'}),
            forcedCharset: 'gbk'),
        '中文',
      );
    });

    test('Content-Type charset 生效（gb2312 别名）', () {
      expect(
        HttpResponseDecoder.decode(gbk('章节内容'),
            headers: h({'Content-Type': 'text/html; charset=gb2312'})),
        '章节内容',
      );
    });

    test('响应头大小写不敏感', () {
      expect(
        HttpResponseDecoder.decode(gbk('大小写'),
            headers: h({'content-type': 'text/html; charset=GBK'})),
        '大小写',
      );
    });

    test('无响应头时从 HTML meta charset 探测', () {
      final out = HttpResponseDecoder.decode(gbk(
          '<html><head><meta charset="gbk"><title>测试</title></head><body>正文</body></html>'));
      expect(out, contains('<meta charset="gbk">'));
      expect(out, contains('正文'));
    });

    test('HTML meta http-equiv content-type 形式', () {
      final out = HttpResponseDecoder.decode(gbk(
          '<head><meta http-equiv="Content-Type" content="text/html; charset=gbk"></head><p>繁体内容</p>'));
      expect(out, contains('繁体内容'));
    });

    test('Big5 声明解码', () {
      final out = HttpResponseDecoder.decode(<int>[0xA4, 0x40, 0xA4, 0xE5],
          headers: h({'Content-Type': 'text/html; charset=big5'}));
      expect(out.trim().isNotEmpty, isTrue);
    });

    test('纯 UTF-8 无声明时统计探测为 utf-8', () {
      expect(
        HttpResponseDecoder.decode(utf8.encode('<html><body>简体中文</body></html>')),
        '<html><body>简体中文</body></html>',
      );
    });

    test('声明 charset 严格优先（对齐上游 ResponseBody.text，不启发式回退）', () {
      // 上游对已声明的 charset 直接 Charset.forName 解码，不回退到探测；
      // 因此站点错标时按声明解码，这与统计探测结果不同。
      final out = HttpResponseDecoder.decode(utf8.encode('中文'),
          headers: h({'Content-Type': 'text/html; charset=gbk'}));
      expect(out, isNot('中文'));
    });

    test('声明编码不可解时回退统计探测（GBK 内容错标 utf-8）', () {
      // utf8 严格校验抛 FormatException → 回退 EncodingDetector 判定 gbk
      final bytes = gbk('中文正文');
      expect(
        HttpResponseDecoder.decode(bytes,
            headers: h({'Content-Type': 'text/html; charset=utf-8'})),
        '中文正文',
      );
    });

    test('空字节返回空串', () {
      expect(HttpResponseDecoder.decode([]), '');
    });
  });

  group('编码名归一化', () {
    test('别名归一', () {
      final plain = utf8.encode('ok');
      for (final alias in [
        'UTF8', 'utf-8', 'us-ascii', 'gb2312', 'gb18030',
        'big-5', 'iso-8859-1',
      ]) {
        expect(
            HttpResponseDecoder.resolveCharset(plain, forcedCharset: alias),
            isNotEmpty,
            reason: alias);
      }
      expect(
          HttpResponseDecoder.resolveCharset(plain, forcedCharset: 'gb2312'),
          'gbk');
      expect(HttpResponseDecoder.resolveCharset(plain, forcedCharset: 'big-5'),
          'big5');
      expect(
          HttpResponseDecoder.resolveCharset(plain,
              forcedCharset: 'iso-8859-1'),
          'latin1');
    });

    test('UTF-16 BOM 优先于 Content-Type', () {
      final r = HttpResponseDecoder.removeBom([0xFF, 0xFE, 0x61, 0x00]);
      expect(
        HttpResponseDecoder.resolveCharset(r.bytes,
            bomCharset: r.charset,
            headers: h({'Content-Type': 'text/html; charset=utf-8'})),
        'utf-16le',
      );
    });
  });

  group('Uint8List 与 List<int> 兼容', () {
    test('Uint8List 输入可解码', () {
      expect(
        HttpResponseDecoder.decode(
            Uint8List.fromList(utf8.encode('字节数组'))),
        '字节数组',
      );
    });
  });
}
