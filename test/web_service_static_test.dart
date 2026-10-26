import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:legado_md3/help/web/web_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Web 服务静态托管（web-yuedu3）端到端：启动 shelf，用真实 HttpClient
/// 取首页与其引用的一个 JS 分块，验证 SPA 与静态资源（含 MIME）真正可访问。
void main() {
  test('WebService 提供 web-yuedu3 首页与静态资源', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    HttpOverrides.global = null; // 允许真实 HttpClient
    const port = 18399;
    final ws = WebService();
    await ws.start(port: port);

    final client = HttpClient();
    try {
      // 首页
      final indexReq = await client.get('127.0.0.1', port, '/');
      final indexResp = await indexReq.close();
      expect(indexResp.statusCode, 200);
      final indexBody = await indexResp.transform(utf8.decoder).join();
      expect(indexBody.contains('app.') || indexBody.contains('<div'), isTrue);

      // 从首页取一个 js 路径并请求
      final jsMatch = RegExp(r'js/[^"]+\.js').firstMatch(indexBody);
      expect(jsMatch, isNotNull);
      final jsPath = '/${jsMatch!.group(0)}';
      final jsReq = await client.get('127.0.0.1', port, jsPath);
      final jsResp = await jsReq.close();
      expect(jsResp.statusCode, 200);
      final ct = jsResp.headers.contentType?.mimeType ?? '';
      expect(ct, contains('javascript'));
      final jsBytes = await jsResp.fold<int>(0, (a, b) => a + b.length);
      expect(jsBytes, greaterThan(0));
    } finally {
      client.close();
      await ws.stop();
    }
  });

  test('WebService 保存/读取阅读配置使用权威键 read_config_json', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    HttpOverrides.global = null;
    const port = 18401;
    final ws = WebService();
    await ws.start(port: port);
    final client = HttpClient();
    try {
      // 保存阅读配置
      final postReq = await client.post('127.0.0.1', port, '/saveReadConfig');
      postReq.headers.contentType = ContentType('application', 'json');
      postReq.write('{"textSize":24}');
      final postResp = await postReq.close();
      expect(postResp.statusCode, 200);

      // 读取应与保存一致（响应为信封结构，data 为存储的字符串）
      final getReq = await client.get('127.0.0.1', port, '/getReadConfig');
      final getResp = await getReq.close();
      expect(getResp.statusCode, 200);
      final body = await getResp.transform(utf8.decoder).join();
      final env = jsonDecode(body) as Map<String, dynamic>;
      expect(env['data'], '{"textSize":24}');

      // 关键回归：写入的是权威键，而非旧错键 web_read_config
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('read_config_json'), '{"textSize":24}');
      expect(prefs.getString('web_read_config'), isNull);
    } finally {
      client.close();
      await ws.stop();
    }
  });
}
