import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:legado_md3/help/source/js/legado_bridge_js.dart';

/// JS 桥 `java.*` API 完整性回归。
///
/// 首选从本地可选的方法声明基线求差集，避免测试里手写一份会过时的清单；
/// 基线文件不存在时跳过该项，其余两项用内置基线锁死已补齐的能力。
const _optionalApiSource = '/workspace/legado-E/legado-E-main/'
    'app/src/main/java/io/legado/app/help/JsExtensions.kt';

String _src(String rel) => File('/workspace/legado-Klys/legado-Klys-main/$rel')
    .readAsStringSync();

/// 提取 JS 桥中暴露在对象字面量上的键（name: function / name: (..) =>）。
Set<String> _bridgeKeys(String code) {
  final keys = <String>{};
  for (final m in RegExp(r'\b([A-Za-z_][A-Za-z0-9_]*)\s*:\s*function\s*\(')
      .allMatches(code)) {
    keys.add(m.group(1)!);
  }
  for (final m in
      RegExp(r'\b([A-Za-z_][A-Za-z0-9_]*)\s*:\s*\([^)]*\)\s*=>')
          .allMatches(code)) {
    keys.add(m.group(1)!);
  }
  return keys..removeWhere((k) => k.startsWith('_'));
}

/// 从方法声明基线中提取公开方法名（即 `java.*` 应暴露的 API）。
Set<String> _declaredApis(String src) {
  final apis = <String>{};
  for (final m in
      RegExp(r'\bfun\s+(?:<[^>]+>\s*)?([A-Za-z_][A-Za-z0-9_]*)\s*\(')
          .allMatches(src)) {
    apis.add(m.group(1)!);
  }
  const kotlinInternal = {
    'getSource', 'getTag', 'getKey', 'equals', 'hashCode', 'toString',
  };
  return apis.difference(kotlinInternal)..removeWhere((k) => k.startsWith('_'));
}

void main() {
  test('JS 桥暴露声明基线中的全部 java.* API（源码动态差集）', () {
    final declared = _declaredApis(File(_optionalApiSource).readAsStringSync());
    final k = _bridgeKeys(LegadoBridgeJs.code);
    final missing = declared.difference(k).toList()..sort();
    expect(missing, isEmpty,
        reason: 'JS 桥缺失 java.* API：$missing');
  }, skip: File(_optionalApiSource).existsSync()
      ? false
      : '声明基线不在本机，跳过动态差集');

  test('本轮补齐的 6 个字节/文件 API 在桥中且辅助函数齐全', () {
    const code = LegadoBridgeJs.code;
    for (final api in const [
      'getZipByteArrayContent',
      'get7zByteArrayContent',
      'getRarByteArrayContent',
      'getFile',
      'readFile',
      'queryBase64TTF',
    ]) {
      expect(code, contains('$api: function'), reason: '桥缺少 $api');
    }
    expect(code, contains('function __archiveBytes'));
    expect(code, contains('function __makeFile'));
    expect(code, contains('op=bytes'));
    expect(code, contains('legado://file?op=readbytes'));
    expect(code, contains('legado://file?op=stat'));
    // 弃用别名 queryBase64TTF 必须直接委托 queryTTF
    expect(code, contains('queryBase64TTF: function (data, useCache) { '
        'return this.queryTTF(data, useCache); }'));
  });

  test('Dart 侧协议实现：zip 字节分支 / 7z-rar 原始字节 / 文件路径白名单', () {
    final wv = _src('lib/help/source/js/parts/web_view_legado_js.dart');
    expect(wv, contains("op == 'bytes'"));
    expect(wv, contains('base64Encode(raw)'));
    expect(wv, contains('ArchiveNative.extractEntryBytes'));
    expect(wv, contains("op == 'readbytes' || op == 'stat'"));
    expect(wv, contains('File? _safeFile(Directory base, String path)'));
    // 越界路径必须被拒绝
    expect(wv, contains("return _textResponse('非法路径', 400)"));

    final arch = _src('lib/help/source/archive_native.dart');
    expect(arch, contains('static Future<Uint8List?> extractEntryBytes'));
    expect(arch, contains('return Uint8List.fromList(base64Decode(b64))'));
  });
}
