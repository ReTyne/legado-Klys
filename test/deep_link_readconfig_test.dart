import 'package:flutter_test/flutter_test.dart';
import 'package:legado_md3/common/deep_link_service.dart';
import 'package:legado_md3/data/model/read_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 深链导入阅读配置（legado-E OnLineImport readConfig）的回归测试。
/// 重点验证：写入权威键 `read_config_json`（而非旧错键 `web_read_config`），
/// 与 Web 服务一致，阅读器才能加载到导入的配置。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('导入 readConfig 写入权威键 read_config_json', () async {
    SharedPreferences.setMockInitialValues({});
    final svc = DeepLinkService.instance;
    const json = '{"textSize":22,"textColor":4280379862}';
    await svc.importRaw(json, type: 'readConfig');

    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('read_config_json');
    expect(stored, isNotNull, reason: '应写入 read_config_json');
    final cfg = ReadConfig.fromJsonString(stored!);
    expect(cfg.textSize, 22);
    // 关键回归：不得再写入旧的错键，否则阅读器读不到
    expect(prefs.getString('web_read_config'), isNull);
  });

  test('导入 readConfig 支持数组包裹 [{}]', () async {
    SharedPreferences.setMockInitialValues({});
    final svc = DeepLinkService.instance;
    const json = '[{"textSize":18}]';
    await svc.importRaw(json, type: 'readConfig');

    final prefs = await SharedPreferences.getInstance();
    final cfg = ReadConfig.fromJsonString(prefs.getString('read_config_json')!);
    expect(cfg.textSize, 18);
  });
}
