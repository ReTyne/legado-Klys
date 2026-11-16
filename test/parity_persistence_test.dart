import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:legado_md3/data/model/book_source.dart';

/// 书源规则在导入/导出与数据库读写中的一致性。
void main() {
  group('TXT 目录规则编辑落库', () {
    test('新增、编辑、开关、删除都写入数据库而非仅改内存', () {
      final src =
          File('lib/ui/config/txt_toc_rule_screen.dart').readAsStringSync();
      // 编辑保存落库
      expect(src, contains('await _db.insertTxtTocRule(updated)'));
      // 开关切换落库
      expect(src, contains('await _db.insertTxtTocRule(updated)'));
      // 删除落库
      expect(src, contains('await _db.deleteTxtTocRule(rule.id)'));
      // 落库调用至少 3 处（编辑 / 开关 / 导入）
      expect(
          'insertTxtTocRule'.allMatches(src).length, greaterThanOrEqualTo(3));
    });

    test('开关切换保留卷规则与示例字段', () {
      final src =
          File('lib/ui/config/txt_toc_rule_screen.dart').readAsStringSync();
      expect(src, contains('volumeRule: rule.volumeRule'));
      expect(src, contains('example: rule.example'));
      expect(src, contains('serialNumber: rule.serialNumber'));
    });
  });

  group('书源变量规则持久化', () {
    BookSource buildSource() => BookSource(
          bookSourceUrl: 'https://example.com',
          bookSourceName: '示例源',
          rulePut: r'@put:{token:$.data.token}',
          ruleGet: '@get:{token}',
        );

    test('toJson 保留 rulePut/ruleGet', () {
      final json = buildSource().toJson();
      expect(json['rulePut'], r'@put:{token:$.data.token}');
      expect(json['ruleGet'], '@get:{token}');
    });

    test('fromJson 还原 rulePut/ruleGet', () {
      final restored = BookSource.fromJson(buildSource().toJson());
      expect(restored.rulePut, r'@put:{token:$.data.token}');
      expect(restored.ruleGet, '@get:{token}');
    });

    test('toMap 写入 rulePut/ruleGet 列（保存书源不丢变量规则）', () {
      final map = buildSource().toMap();
      expect(map.containsKey('rulePut'), isTrue,
          reason: 'book_sources 表已有 rulePut 列，toMap 必须写入');
      expect(map.containsKey('ruleGet'), isTrue,
          reason: 'book_sources 表已有 ruleGet 列，toMap 必须写入');
      expect(map['rulePut'], r'@put:{token:$.data.token}');
      expect(map['ruleGet'], '@get:{token}');
    });

    test('toMap → fromMap 往返后变量规则不丢失', () {
      final restored = BookSource.fromMap(buildSource().toMap());
      expect(restored.rulePut, r'@put:{token:$.data.token}');
      expect(restored.ruleGet, '@get:{token}');
    });

    test('toDbMap 别名同样携带变量规则', () {
      final map = buildSource().toDbMap();
      expect(map['rulePut'], r'@put:{token:$.data.token}');
      expect(map['ruleGet'], '@get:{token}');
    });

    test('未设置变量规则时写入 null，不产生多余空串', () {
      final map = BookSource(
        bookSourceUrl: 'https://example.com',
        bookSourceName: '空规则源',
      ).toMap();
      expect(map['rulePut'], isNull);
      expect(map['ruleGet'], isNull);
      expect(BookSource.fromMap(map).rulePut, isNull);
    });
  });
}
