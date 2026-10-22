import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:legado_md3/help/storage/backup_zip.dart';

void main() {
  group('LightCrypto XOR 轻量加密', () {
    test('加解密往返一致', () {
      final plain = utf8.encode('{"bookSources":[{"url":"http://a.com","login":"secret"}]}');
      final enc = LightCrypto.encrypt(plain, 'pass123');
      // 文件头标识
      expect(LightCrypto.isEncrypted(enc), true);
      // 非明文：密文中不应出现敏感关键字
      expect(utf8.decode(enc, allowMalformed: true).contains('secret'), false);
      final dec = LightCrypto.decrypt(enc, 'pass123');
      expect(utf8.decode(dec), utf8.decode(plain));
    });

    test('错误密码抛出异常', () {
      final plain = utf8.encode('hello');
      final enc = LightCrypto.encrypt(plain, 'right');
      expect(() => LightCrypto.decrypt(enc, 'wrong'), throwsA(isA<FormatException>()));
    });

    test('无加密头数据 isEncrypted 为 false', () {
      expect(LightCrypto.isEncrypted(utf8.encode('{"a":1}')), false);
    });
  });

  group('ZipBackupBuilder', () {
    test('zip 打包带 PK 文件头且可解析', () {
      final index = ZipBackupIndex(
        version: '2.0',
        time: '2026-10-22T00:00:00.000',
        deviceName: '测试设备',
        appVersion: '3.30.0',
        encrypted: true,
        selection: BackupSelection.all(),
      );
      final payloads = <BackupType, String>{
        BackupType.books: '[{"name":"book1"}]',
        BackupType.bookSources: '[{"url":"http://a.com","login":"secret"}]',
        BackupType.searchHistory: '["关键词"]',
      };
      final bytes = ZipBackupBuilder.build(
        index: index,
        payloads: payloads,
        password: 'pw',
      );
      // zip 文件头 PK\x03\x04
      expect(bytes[0], 0x50);
      expect(bytes[1], 0x4B);
      expect(bytes[2], 0x03);
      expect(bytes[3], 0x04);

      // 正确密码解析
      final data = ZipBackupBuilder.parse(bytes, password: 'pw');
      expect(data.index.deviceName, '测试设备');
      expect(data.index.encrypted, true);
      expect(data.hasType(BackupType.books), true);
      expect(data.files[BackupType.books.file], '[{"name":"book1"}]');
      // 敏感文件已解密还原
      expect(data.files[BackupType.bookSources.file], '[{"url":"http://a.com","login":"secret"}]');
      expect(data.hasType(BackupType.servers), false);

      // 错误密码解析失败
      expect(() => ZipBackupBuilder.parse(bytes, password: 'bad'), throwsA(anything));

      // 缺少密码解析失败
      expect(() => ZipBackupBuilder.parse(bytes), throwsA(isA<FormatException>()));
    });

    test('无密码构建时敏感文件为明文', () {
      final index = ZipBackupIndex(
        version: '2.0',
        time: 't',
        deviceName: 'd',
        appVersion: '1',
        encrypted: false,
        selection: BackupSelection(const {BackupType.bookSources}),
      );
      final bytes = ZipBackupBuilder.build(
        index: index,
        payloads: {BackupType.bookSources: '[{"url":"u"}]'},
      );
      final data = ZipBackupBuilder.parse(bytes);
      expect(data.files[BackupType.bookSources.file], '[{"url":"u"}]');
    });
  });

  group('BackupSelection', () {
    test('往返序列化', () {
      final sel = BackupSelection.fromList(['books', 'bookSources', 'unknownType']);
      expect(sel.contains(BackupType.books), true);
      expect(sel.contains(BackupType.bookSources), true);
      expect(sel.contains(BackupType.servers), false);
      expect(sel.toList(), containsAll(['books', 'bookSources']));
    });
  });

  test('旧版纯 JSON 备份数据可被 jsonDecode（向后兼容路径）', () {
    // 模拟旧版备份内容（与旧 backup_service 输出结构一致）
    final legacy = {
      'version': '1.0',
      'backupTime': '2026-01-01T00:00:00.000',
      'books': <dynamic>[],
      'bookSources': <dynamic>[],
    };
    final text = jsonEncode(legacy);
    final parsed = jsonDecode(text) as Map<String, dynamic>;
    expect(parsed['books'], isList);
    expect(parsed['bookSources'], isList);
    // 旧版不是 zip：首字符不是 P
    expect(utf8.encode(text)[0], 0x7B);
  });
}
