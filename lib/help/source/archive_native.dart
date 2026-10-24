import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 7z / rar 压缩包原生解压通道（Android）。
///
/// legado-E 通过 libarchive（JNI）支持 7z/rar；Flutter 侧纯 Dart 生态没有
/// 7z/rar 解码器，故在 Android 端以 `commons-compress`（7z）+ `junrar`（rar）
/// 实现，经 MethodChannel('legado/archive') 暴露两个能力：
///
/// * [extractEntry]：读取压缩包内指定文件的内容（书源 java.get7zStringContent/
///   getRarStringContent）；
/// * [extractAll]：整包解压到 legado_files/unzip/<md5(数据)>，返回**相对目录名**
///   （书源 java.un7zFile/unrarFile，配合 java.getTxtInFolder 使用）。
///
/// 非 Android 平台（iOS/桌面/测试）下两个方法返回 null / 抛
/// [UnsupportedError]，调用方据此降级——与 legado-E 仅在 Android 提供
/// libarchive 的行为一致。
class ArchiveNative {
  ArchiveNative._();

  static const _channel = MethodChannel('legado/archive');

  /// 是否具备原生 7z/rar 解压能力（Android 且插件已注册）。
  static Future<bool> get available async {
    try {
      return await _channel.invokeMethod<bool>('ping') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 读取压缩包内 [entryPath] 对应文件的文本内容；不存在或平台不支持返回 null。
  ///
  /// [kind] 为 `7z` 或 `rar`。
  static Future<String?> extractEntry(
      Uint8List data, String kind, String entryPath) async {
    if (entryPath.isEmpty) return null;
    try {
      final b64 = await _channel.invokeMethod<String>('extractEntry', {
        'kind': kind,
        'data': base64Encode(data),
        'entry': entryPath,
      });
      if (b64 == null || b64.isEmpty) return null;
      return utf8.decode(base64Decode(b64), allowMalformed: true);
    } catch (_) {
      return null;
    }
  }

  /// 整包解压，返回相对目录名（相对 legado_files）；失败/不支持返回 null。
  static Future<String?> extractAll(Uint8List data, String kind) async {
    try {
      final entries = await _channel.invokeMethod<List<Object?>>('extractAll', {
        'kind': kind,
        'data': base64Encode(data),
      });
      if (entries == null) return null;
      final dir = await getApplicationDocumentsDirectory();
      final base = Directory('${dir.path}/legado_files');
      if (!base.existsSync()) base.createSync(recursive: true);
      // 与 zip 解压目录规则一致：unzip/<md5(压缩包名或内容)>
      final key = md5Of(data);
      final outDir = Directory('${base.path}/unzip/$key');
      if (!outDir.existsSync()) outDir.createSync(recursive: true);
      for (final e in entries) {
        if (e is! Map) continue;
        final name = (e['name'] as String?) ?? '';
        final b64 = (e['data'] as String?) ?? '';
        if (name.isEmpty) continue;
        final out = File('${outDir.path}/${p.basename(name)}');
        if (!out.parent.existsSync()) out.parent.createSync(recursive: true);
        await out.writeAsBytes(base64Decode(b64));
      }
      return 'unzip/$key';
    } catch (_) {
      return null;
    }
  }

  static String md5Of(List<int> data) =>
      md5.convert(data).toString();
}
