import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/help/source/source_engine.dart';
import 'package:legado_md3/help/source/js/legado_js_runtime.dart';

/// 锁定 legado `type` URL 选项语义（AnalyzeUrl.getStrResponseAwait）：
/// URL 选项带 type 时，data: 书址的响应体为解码字节的小写 hex 编码
/// （Hutool HexUtil.encodeHexStr），供书源 JS 以 java.hexDecodeToString(result) 还原。
/// 大灰狼聚合（yck2026.fun id/7632）书详情/目录/正文三环均依赖该机制。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final payload = jsonEncode({
    'book_id': 'NzE0MzAzODY5MTk0NDk1OTAxMQ',
    'sources': '番茄',
    'tab': '小说',
    'url': '',
  });
  final b64 = base64Encode(utf8.encode(payload));
  // 期望的 hex（Hutool HexUtil.encodeHexStr：小写）
  final expectHex = utf8.encode(payload).map((b) {
    final v = b & 0xff;
    return v.toRadixString(16).padLeft(2, '0');
  }).join();

  // 构造 base64 长度 % 4 == 0（无 = 填充）的载荷：
  // 此时尾部挂载的 ,{"type":...} 只能靠「非 base64 字符集截断」剔除
  var noPadPayload = '{"k":"value"}';
  while (base64Encode(utf8.encode(noPadPayload)).length % 4 != 0) {
    noPadPayload += 'x';
  }
  final noPadB64 = base64Encode(utf8.encode(noPadPayload));
  final noPadHex = utf8.encode(noPadPayload).map((b) {
    final v = b & 0xff;
    return v.toRadixString(16).padLeft(2, '0');
  }).join();

  BookSource mkSource() => BookSource.fromJson({
        'bookSourceUrl': 'https://v5.langge.uk',
        'bookSourceName': 'type选项测试源',
        'bookSourceGroup': '',
        'bookSourceType': 0,
        'enabled': true,
        'enabledExplore': true,
        'header': '',
        'loginUrl': '',
        'loginUi': '',
        'jsLib': '',
        'ruleSearch': {},
        'ruleBookInfo': {},
        'ruleToc': {},
        'ruleContent': {'content': '<js>result</js>'},
      });

  test('type 选项：data: 书址响应体为小写 hex（7632 详情/目录/正文机制）', () async {
    SharedPreferences.setMockInitialValues({});
    JsRuntimeManager.instance.factoryOverride = (_) => MiniLegadoJs();
    final engine = BookSourceEngine();

    final url = 'data:;base64,$b64,{"type":"qingtian3"}';
    final text = await engine.getContent(mkSource(), url);
    expect(text, expectHex,
        reason: 'type 选项应返回 hex 响应体（对齐 legado HexUtil.encodeHexStr）');
  });

  test('无 type 选项：data: 书址响应体仍为 UTF-8 文本', () async {
    SharedPreferences.setMockInitialValues({});
    JsRuntimeManager.instance.factoryOverride = (_) => MiniLegadoJs();
    final engine = BookSourceEngine();

    final url = 'data:;base64,$b64';
    final text = await engine.getContent(mkSource(), url);
    expect(text, payload);
  });

  test('base64 无填充时尾部挂载选项也不影响解码（字符集截断）', () async {
    SharedPreferences.setMockInitialValues({});
    JsRuntimeManager.instance.factoryOverride = (_) => MiniLegadoJs();
    final engine = BookSourceEngine();

    final url = 'data:;base64,$noPadB64,{"type":"qingtian"}';
    final text = await engine.getContent(mkSource(), url);
    expect(text, noPadHex);
  });
}
