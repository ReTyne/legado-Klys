import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:legado_md3/help/source/js_mini_eval.dart';
import 'package:legado_md3/help/source/json_path.dart';
import 'package:legado_md3/help/storage/direct_link_upload.dart';

/// C2 直链上传：规则模型 / 默认规则 / 下载地址规则求值链路。
/// 对齐 legado-E help/DirectLinkUpload.kt 与 assets/defaultData/directLinkUpload.json。
void main() {
  group('DirectLinkRule 模型', () {
    test('默认规则与 E assets 一致（3 条）', () {
      expect(DirectLinkUploadService.defaultRules.length, 3);
      expect(
        DirectLinkUploadService.defaultRules[0].uploadUrl,
        'https://sy.nyasama.net/shuyuan,{"method":"POST","body":{"file":"fileRequest"},"type":"multipart/form-data"}',
      );
      expect(DirectLinkUploadService.defaultRules[0].expiryDate, 30);
      expect(DirectLinkUploadService.defaultRules[1].expiryDate, 7);
      expect(DirectLinkUploadService.defaultRules[2].downloadUrlRule, r'$.msg');
      expect(DirectLinkUploadService.defaultRules[2].expiryDate, 0);
    });

    test('E 默认规则 JSON 原样解析', () {
      // E assets/defaultData/directLinkUpload.json 原文
      const eJson = '''
[
  {
    "uploadUrl": "https://sy.nyasama.net/shuyuan,{\\"method\\":\\"POST\\",\\"body\\": {\\"file\\": \\"fileRequest\\"},\\"type\\": \\"multipart/form-data\\"}",
    "downloadUrlRule": "\$.data@js:if (result == '') \\n '' \\n else \\n 'https://shuyuan.nyasama.net/shuyuan/' + result",
    "summary": "喵公子网盘①(有效期30天·香港G口)",
    "compress": false,
    "expiryDate": 30
  },
  {
    "uploadUrl": "http://v2.jt12.eu/up-v2.php,{\\"method\\":\\"POST\\",\\"body\\": {\\"file\\": \\"fileRequest\\"},\\"type\\": \\"multipart/form-data\\"}",
    "downloadUrlRule": "\$.msg",
    "summary": "橘涂书源网盘2.0 Beta(永久有效)",
    "compress": false,
    "expiryDate": 0
  }
]
''';
      final list = (jsonDecode(eJson) as List)
          .map(DirectLinkRule.fromJson)
          .toList();
      expect(list.length, 2);
      expect(list.every((r) => r != null), true);
      expect(list[0]!.summary, '喵公子网盘①(有效期30天·香港G口)');
      expect(list[0]!.uploadUrl.startsWith('https://sy.nyasama.net/shuyuan,'), true);
      expect(list[1]!.downloadUrlRule, r'$.msg');
    });

    test('toJson/fromJson 往返', () {
      const rule = DirectLinkRule(
        uploadUrl: 'https://example.com/up,{"method":"POST"}',
        downloadUrlRule: r'$.data@js:result',
        summary: '测试规则',
        compress: true,
        expiryDate: 7,
      );
      final back = DirectLinkRule.fromJson(jsonDecode(jsonEncode(rule.toJson())))!;
      expect(back.uploadUrl, rule.uploadUrl);
      expect(back.downloadUrlRule, rule.downloadUrlRule);
      expect(back.summary, rule.summary);
      expect(back.compress, true);
      expect(back.expiryDate, 7);
    });

    test('缺 uploadUrl / downloadUrlRule 时 fromJson 返回 null', () {
      expect(DirectLinkRule.fromJson({'downloadUrlRule': r'$.msg'}), null);
      expect(DirectLinkRule.fromJson({'uploadUrl': 'https://x.com'}), null);
      expect(DirectLinkRule.fromJson('not a map'), null);
    });
  });

  group('下载地址规则求值链路（_extractDownloadUrl 等价逻辑）', () {
    /// 复刻服务内的拆分逻辑：JsonPath 取值 + @js: 后处理
    String extract(dynamic root, String downloadUrlRule) {
      final rule = downloadUrlRule.trim();
      final jsIdx = rule.indexOf('@js:');
      final pathPart = (jsIdx >= 0 ? rule.substring(0, jsIdx) : rule).trim();
      final jsPart = jsIdx >= 0 ? rule.substring(jsIdx + 4).trim() : null;
      String value;
      if (pathPart.isEmpty) {
        value = root is String ? root : jsonEncode(root);
      } else {
        final v = JsonPath.selectFirst(root, pathPart);
        value = v == null
            ? ''
            : (v is Map || v is List ? jsonEncode(v) : v.toString());
      }
      if (jsPart != null && jsPart.isNotEmpty) {
        final jsResult = JsMiniEvaluator.eval(jsPart, result: value);
        if (jsResult != null && jsResult.isNotEmpty) value = jsResult;
      }
      return value;
    }

    test(r'纯 JsonPath 规则（橘涂网盘 $.msg）', () {
      final root = jsonDecode('{"code":200,"msg":"https://v2.jt12.eu/f/abc.zip"}');
      expect(extract(root, r'$.msg'), 'https://v2.jt12.eu/f/abc.zip');
    });

    test(r'$.data@js:if/else 规则（喵公子网盘）', () {
      final root = jsonDecode('{"code":0,"data":"abc123.txt"}');
      final rule = DirectLinkUploadService.defaultRules[0].downloadUrlRule;
      expect(extract(root, rule), 'https://shuyuan.nyasama.net/shuyuan/abc123.txt');
    });

    test(r'$.data@js: 空 result 时走空分支', () {
      final root = jsonDecode('{"code":1,"data":""}');
      final rule = DirectLinkUploadService.defaultRules[1].downloadUrlRule;
      expect(extract(root, rule), '');
    });

    test('响应非 JSON 时按文本处理', () {
      expect(extract('https://example.com/f.txt', '@js:'), 'https://example.com/f.txt');
    });

    test('迷你求值器直接支持 if (cond) expr else expr', () {
      const js = "if (result == '') \n '' \n else \n 'https://s/' + result";
      expect(JsMiniEvaluator.eval(js, result: 'a.txt'), 'https://s/a.txt');
      expect(JsMiniEvaluator.eval(js, result: ''), '');
    });
  });
}
