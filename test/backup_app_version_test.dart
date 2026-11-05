import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:legado_md3/help/storage/backup_service.dart';

/// 回归：备份元信息里的 appVersion 曾两处写死 '3.30.0'（旧 Kotlin 版号），
/// 跨版本恢复时无法据真实版本判断兼容。改为 PackageInfo 读取 + 明确兜底。
void main() {
  test('currentAppVersion 返回真实版本而非写死的 3.30.0', () async {
    final v = await BackupService.currentAppVersion();
    expect(v.trim(), isNotEmpty);
    expect(v, isNot('3.30.0'));
    // 纯 Dart 测试环境平台通道不可用，应回退到 pubspec 版本常量
    expect(v, BackupService.fallbackAppVersion);
  });

  test('createBackup 与 createZipBackup 均调用 currentAppVersion（调用链契约）', () {
    final src = File('lib/help/storage/backup_service.dart').readAsStringSync();
    expect(src.contains("'3.30.0'"), isFalse, reason: '仍残留写死旧版号');
    expect(src.contains('static Future<String> currentAppVersion()'), isTrue);
    // 两处备份入口都要用真实版本
    expect('await currentAppVersion()'.allMatches(src).length,
        greaterThanOrEqualTo(2));
  });
}
