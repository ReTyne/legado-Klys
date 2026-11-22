import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart' as archive;
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legado_md3/help/http/cookie_manager.dart';
import 'package:legado_md3/help/http/ssl_helper.dart';
import 'package:legado_md3/help/storage/epub_parser.dart';
import 'package:legado_md3/help/storage/webdav_service.dart';
import 'package:legado_md3/utils/crypto_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _testCertPem = '''-----BEGIN CERTIFICATE-----
MIIDBzCCAe+gAwIBAgIUYKLgJtU3QKyAhmtfhRa4SgW+ztMwDQYJKoZIhvcNAQEL
BQAwEzERMA8GA1UEAwwIZ2FwLXRlc3QwHhcNMjYxMTE5MTUxNTU0WhcNMzYxMTE2
MTUxNTU0WjATMREwDwYDVQQDDAhnYXAtdGVzdDCCASIwDQYJKoZIhvcNAQEBBQAD
ggEPADCCAQoCggEBANKhAaLym4q8wRINWCZ5e8EOtnPTOoLO1tEO8fAvCmubYuD6
7S0YnaHyKkD+0E7PwaOBGK9V+BugWe2Srk4vRkpxmj4cTyh23qwvRO06d2Hj7A3+
57w3xtaKrc+0y9LhYBGb1TfnpfOCMJDemG4C2w4+vhEkYAhEBJgV995Jny2IR9Ur
MNnLmkbegvyjMnrb3YsYOLhgdBqPl5bv67y74ZhkfzWaNTE8WkzApQwWpEzpEmuN
5dYQHVbqdtPUa8hZjfSWhthczkcjV7i2S+aOD726kc8I9XAHHfmFJalVBYr6hHYI
DXrbl227gjJPfFCDoXSU5VOZ9r6bxH1LaRaLiukCAwEAAaNTMFEwHQYDVR0OBBYE
FEAgr7E5nSfnkEPObqYHU1Qc6gucMB8GA1UdIwQYMBaAFEAgr7E5nSfnkEPObqYH
U1Qc6gucMA8GA1UdEwEB/wQFMAMBAf8wDQYJKoZIhvcNAQELBQADggEBAFywwPqs
dBSg2oclLAqIDKz1nd0HGHLZz/YYjyp9qUwwWrdF2gDcoOj/Q2Wm8NrLKZpwajjq
LXjBQcoGDOrlHUKylrML/1Wl0pWPJLsM0FURagYH9EWvYjYmq5Zch1+MOztf65bg
75g3dfULHasy6NWIzEULAZWeD+i3Xc1lcw4jSSRXU46+qg3fzWPqn4qC/QWd5HNE
j3135Z0bUveNfRbF9bmHaoyoeV20mi9SwUiTDULMnPYZ6wcjYyT8piz9PsfMWnHS
WN7ANFWBMXTkfSz0lNe0+7KVkEdhnqnmjxvniVFtII7BVGyoEqlUIpp7jOnVaf8J
9NK1D9h5Bu2daQ8=
-----END CERTIFICATE-----''';

const String _testKeyPem = '''-----BEGIN PRIVATE KEY-----
MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQDSoQGi8puKvMES
DVgmeXvBDrZz0zqCztbRDvHwLwprm2Lg+u0tGJ2h8ipA/tBOz8GjgRivVfgboFnt
kq5OL0ZKcZo+HE8odt6sL0TtOndh4+wN/ue8N8bWiq3PtMvS4WARm9U356XzgjCQ
3phuAtsOPr4RJGAIRASYFffeSZ8tiEfVKzDZy5pG3oL8ozJ6292LGDi4YHQaj5eW
7+u8u+GYZH81mjUxPFpMwKUMFqRM6RJrjeXWEB1W6nbT1GvIWY30lobYXM5HI1e4
tkvmjg+9upHPCPVwBx35hSWpVQWK+oR2CA1625dtu4IyT3xQg6F0lOVTmfa+m8R9
S2kWi4rpAgMBAAECggEAHbvwevQkTJbea6G6IL5UH9onnBzE3Qv9i+g/88/0OOIn
+Io72rqnoCHLYL8IIaQXGjGijjgE7UN7BnyHQk7OrboxU9TTwOrc/vIyWQoAqe9O
1t/2D15RYd6UcGa9wmCiGwJEfJ6lUQW/POhLnPYmvfFSDCH2M5yEiILLadQ7ViYt
6kHYrjE16Ht/T3HgH6vcsoEVn0TzD4xZRVTiXAc4NNtpG0gKUWhhcC/UU478iQAi
3+7x65jPiJ0WSbTHsLFK6vsN4otEaRd+ITAZucEAv+Rcu0KCD6vCAw/cy2+CYBt6
yjXPnYm4uXqqTkgHU8hx/LluwJpJelKqGs5BfOjlLQKBgQD9rduyw0Rb1a5t5EJg
RWsdDOXpnDFWiyQAs9zk7G0z9DqCHAacyWNu1Vew1XNRC9hd977C6QyRGh5dusUz
hzcXPvwK6LR1Z8LN0AR6BnsxMCFiexhX+e4hGPHp4m8N3Ff3yvzWzqyFkZy1MaGo
yMztXNI0zJe0DQnAbVB3KzpwJQKBgQDUjlIBXozw9aYaQeK5m8JbDougLn4zyV1b
o71DguBXw5EVM9TsKJneurCuqrh9kc2IC9s0bR1cV5CoYZMrSqWVffrPA5G2yHRv
PlXN3fpvrjnEUOV9VoDCvyONesEy33hqy1UZNS9KcLo7SqWMwR2KRWtAaaY/RfaH
3xOcqz4CdQKBgQCdGXA3Uqog3UH6mCNrD1J4WSaA99OuLtkK/lhMBQbT5+nb7ZNC
wY0sdD6sKmQRyu4hs22Vs1GvAqfPj/zUHmbFpKHd96LaGnoPj0VWdHESUyY5oNXA
le0c3h/iofH4eX6Y3EKcnL1GspiDtcrRhhky3grn29QPEwv4+Tmds02raQKBgAMh
OVnlz4N4yoJWeAUtovX+R9YK+Ta//0zrI01MLwt7yLYcNkVn76QU8acQwniu3ezj
581k0erbKzkffrBDgB6sZTYJImsjlntQ2qiWXSqp0RXv7wEidfDoKZjatt+N5NMF
vXIKk3CwKj3XQorJCStRDFw9cgI6gH/NrBdBej9FAoGALSm9IYY8XIKvOkxtgWLV
Qdh3hPTUWeupKKeDB370CGhrRzh28yfT145N1GX9fRNjD4qurHZAhKwSDEL/cED5
ICzl3wpYJ780edREiMTtdpES71Cvm2u3rBH7O40R4yvL533A2K8Dq62KGSemSDEL
8OZfivignOEW4RnFXbcNDpk=
-----END PRIVATE KEY-----''';

const String _propfindXml = '''<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/backup_new.json</d:href>
    <d:propstat><d:prop>
      <d:resourcetype/>
      <d:getcontentlength>100</d:getcontentlength>
      <d:getlastmodified>Wed, 09 Jun 2027 10:18:14 GMT</d:getlastmodified>
      <d:displayname>new backup</d:displayname>
    </d:prop></d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/backup%20old.bak</d:href>
    <d:propstat><d:prop>
      <d:resourcetype/>
      <d:getcontentlength>50</d:getcontentlength>
      <d:getlastmodified>Tue, 08 Jun 2021 10:18:14 GMT</d:getlastmodified>
    </d:prop></d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/notes.txt</d:href>
    <d:propstat><d:prop><d:resourcetype/></d:prop></d:propstat>
  </d:response>
</d:multistatus>''';

class _RecordedRequest {
  _RecordedRequest(this.method, this.path, this.depth, this.body);
  final String method;
  final String path;
  final String? depth;
  final String body;
}

void main() {
  group('EPUB 中文解码', () {
    test('OPF/NCX 中文元数据按 UTF-8 解码（含 BOM）', () async {
      final arc = archive.Archive();
      const opf = '<?xml version="1.0" encoding="utf-8"?>'
          '<package><metadata>'
          '<dc:title>中文书名</dc:title>'
          '<dc:creator>作者名</dc:creator>'
          '<dc:description>内容描述</dc:description>'
          '</metadata></package>';
      final opfBytes = <int>[0xEF, 0xBB, 0xBF, ...utf8.encode(opf)];
      arc.addFile(archive.ArchiveFile('OEBPS/content.opf', opfBytes.length, opfBytes));
      const ncx = '<?xml version="1.0" encoding="utf-8"?><ncx>'
          '<navPoint id="a"><text>第一章 序</text><content src="c1.xhtml"/></navPoint>'
          '<navPoint id="b"><text>第二章 江湖</text><content src="c2.xhtml"/></navPoint>'
          '</ncx>';
      final ncxBytes = utf8.encode(ncx);
      arc.addFile(
          archive.ArchiveFile('OEBPS/toc.ncx', ncxBytes.length, ncxBytes));
      final zipped = archive.ZipEncoder().encode(arc)!;

      final dir = await Directory.systemTemp.createTemp('gap_epub_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/book.epub');
      await file.writeAsBytes(zipped);

      final book = await EpubParser.parse(file.path);
      expect(book, isNotNull);
      expect(book!.name, '中文书名');
      expect(book.author, '作者名');
      expect(book.intro, '内容描述');

      final chapters = await EpubParser.parseToc(file.path);
      expect(chapters.length, 2);
      expect(chapters[0].title, '第一章 序');
      expect(chapters[1].title, '第二章 江湖');
    });
  });

  group('WebDAV', () {
    test('normalizeBaseUrl 归一 dav/davs scheme 与尾斜杠', () {
      expect(WebDavService.normalizeBaseUrl('dav://host/dav'),
          'http://host/dav/');
      expect(WebDavService.normalizeBaseUrl('DAVS://host/dav/'),
          'https://host/dav/');
      expect(WebDavService.normalizeBaseUrl('https://host/dav'),
          'https://host/dav/');
      expect(WebDavService.normalizeBaseUrl('  http://host  '),
          'http://host/');
    });

    test('PROPFIND 请求体显式声明所需属性', () {
      const body = WebDavService.propfindBody;
      expect(body, contains('<d:propfind'));
      expect(body, contains('getlastmodified'));
      expect(body, contains('getcontentlength'));
      expect(body, contains('displayname'));
      expect(body, contains('resourcetype'));
    });

    test('parsePropfindResponse 解析 size/时间/显示名与百分号编码', () {
      final entries = WebDavService.parsePropfindResponse(_propfindXml);
      expect(entries.length, 3);
      final newer = entries.firstWhere((e) => e.name == 'backup_new.json');
      expect(newer.size, 100);
      expect(newer.displayName, 'new backup');
      expect(newer.lastModified, isNotNull);
      expect(newer.isDir, isFalse);
      expect(entries.any((e) => e.name == 'backup old.bak'), isTrue);
      final plain = entries.firstWhere((e) => e.name == 'notes.txt');
      expect(plain.size, isNull);
      expect(plain.lastModified, isNull);
    });

    test('本地服务器往返：scheme 归一、5xx 重试、PROPFIND body、最新备份', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async => server.close());
      final requests = <_RecordedRequest>[];
      var count = 0;
      server.listen((req) async {
        final body = await utf8.decoder.bind(req).join();
        requests.add(_RecordedRequest(
            req.method, req.uri.path, req.headers.value('depth'), body));
        if (count++ == 0) {
          req.response.statusCode = 500;
          await req.response.close();
          return;
        }
        req.response.statusCode = 207;
        req.response.headers.contentType =
            ContentType('application', 'xml', charset: 'utf-8');
        req.response.write(_propfindXml);
        await req.response.close();
      });

      final svc = WebDavService();
      svc.configure(baseUrl: 'dav://127.0.0.1:${server.port}');
      expect(await svc.testConnection(), isTrue, reason: '首次 5xx 应重试后成功');
      expect(count, 2);
      expect(requests.first.method, 'PROPFIND');
      expect(requests.first.depth, '0');
      expect(requests.first.body, contains('<d:propfind'));

      final entries = await svc.listDir('');
      expect(entries.length, 3);
      expect(await svc.latestBackup(dir: ''), 'backup_new.json');
    });
  });

  group('Cookie 持久化', () {
    test('持久 Cookie 写入/重载/单键删除，会话层不落盘', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final cm = CookieManager();
      await cm.ready();
      cm.clear();
      await cm.flush();

      cm.saveFromResponse('https://www.example.com/', [
        'token=abc123; Max-Age=3600; Path=/',
        'sid=session123; Path=/',
      ]);
      expect(cm.persistentCount, 1);
      expect(cm.sessionCount, 1);
      await cm.flush();

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(CookieManager.persistentPrefsKey);
      expect(raw, contains('token'));
      expect(raw, isNot(contains('sid')));

      // 模拟进程重启：清空内存后从磁盘重载，会话层随之丢失。
      await cm.reload();
      cm.clearSession();
      expect(cm.persistentCount, 1);
      expect(cm.cookieHeader('https://www.example.com/'),
          contains('token=abc123'));

      cm.removeCookie('https://www.example.com/', 'token');
      await cm.flush();
      expect(cm.persistentCount, 0);
      expect(cm.cookieHeader('https://www.example.com/'), isNull);
    });
  });

  group('SSL 上下文', () {
    test('buildSecurityContext 无配置返回 null，证书配置返回上下文', () {
      expect(SslHelper.buildSecurityContext(), isNull);
      final cert = utf8.encode(_testCertPem);
      final trusted = SslHelper.buildSecurityContext(
          trustedCertificates: [cert], withTrustedRoots: false);
      expect(trusted, isNotNull);
      final mtls = SslHelper.buildSecurityContext(
          clientCertificateBytes: cert,
          clientPrivateKeyBytes: utf8.encode(_testKeyPem),
          withTrustedRoots: false);
      expect(mtls, isNotNull);
    });

    test('attach 保留适配器并接受证书参数', () {
      final dio = Dio();
      SslHelper.attach(
        dio,
        trustAll: false,
        trustedCertificates: [utf8.encode(_testCertPem)],
        clientCertificateBytes: utf8.encode(_testCertPem),
        clientPrivateKeyBytes: utf8.encode(_testKeyPem),
      );
      expect(dio.httpClientAdapter, isA<IOHttpClientAdapter>());
    });
  });

  group('加密算法依赖边界', () {
    test('GCM 与非 RSA 非对称算法明确拒绝（需外部依赖）', () {
      expect(
          () => SymmetricCrypto('AES/GCM/NoPadding', '0123456789abcdef'),
          throwsArgumentError);
      expect(
          () => AsymmetricCrypto('SM2', publicKey: 'x'), throwsArgumentError);
      expect(() => AsymmetricCrypto('EC', publicKey: 'x'), throwsArgumentError);
    });
  });
}
