import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:legado_md3/help/device/native_bridge.dart';

/// 归档类型（按文件头魔术字节判定）。
enum ArchiveKind { zip, rar, sevenZip, unknown }

/// 归档内一个文件条目（解压后的字节）。
class ArchiveEntry {
  final String name;
  final Uint8List bytes;

  const ArchiveEntry(this.name, this.bytes);

  bool get isBookFile {
    final lower = name.toLowerCase();
    return lower.endsWith('.txt') ||
        lower.endsWith('.epub') ||
        lower.endsWith('.mobi') ||
        lower.endsWith('.azw') ||
        lower.endsWith('.azw3') ||
        lower.endsWith('.pdf') ||
        lower.endsWith('.umd');
  }
}

/// 需要主代理接线的解码器：传入文件路径，返回解压后的条目列表。
/// RAR / 7z 由原生侧（或主代理引入的解码实现）提供，通过
/// [ArchiveImportHelper.registerExternalDecoder] 注入即可参与统一路由。
typedef ExternalArchiveDecoder = Future<List<ArchiveEntry>> Function(
    String path, ArchiveKind kind);

class ArchiveImportException implements Exception {
  final String message;
  const ArchiveImportException(this.message);

  @override
  String toString() => message;
}

/// 本地书归档导入的 Dart 侧路由入口（供 `import_book_service.dart` 调用）。
///
/// * ZIP / EPUB（本质是 ZIP）：用现有 `archive` 包 [ZipDecoder] 真实解压；
/// * RAR / 7z：按魔术字节路由到已注入的外部解码器（主代理接原生通道）；
/// * 提供 [extractBookEntriesToTemp] 把书文件落盘，返回可直接交给
///   `import_book_service.dart` 的本地路径列表。
class ArchiveImportHelper {
  ArchiveImportHelper._();

  static final Map<ArchiveKind, ExternalArchiveDecoder> _external = {};

  static void registerExternalDecoder(ArchiveKind kind, ExternalArchiveDecoder decoder) {
    _external[kind] = decoder;
  }

  static ArchiveKind detect(List<int> head) {
    if (head.length >= 4) {
      // "PK\x03\x04"
      if (head[0] == 0x50 && head[1] == 0x4B && head[2] == 0x03 && head[3] == 0x04) {
        return ArchiveKind.zip;
      }
      // "Rar!\x1A\x07"
      if (head[0] == 0x52 &&
          head[1] == 0x61 &&
          head[2] == 0x72 &&
          head[3] == 0x21) {
        return ArchiveKind.rar;
      }
      // "7z\xBC\xAF"
      if (head[0] == 0x37 &&
          head[1] == 0x7A &&
          head[2] == 0xBC &&
          head[3] == 0xAF) {
        return ArchiveKind.sevenZip;
      }
    }
    return ArchiveKind.unknown;
  }

  static Future<ArchiveKind> detectFile(String path) async {
    final raf = await File(path).open();
    final head = await raf.read(8);
    await raf.close();
    return detect(head);
  }

  /// 打开归档并列出全部（已解压的）文件条目。
  static Future<List<ArchiveEntry>> open(String path) async {
    final bytes = await File(path).readAsBytes();
    final kind = detect(bytes);
    switch (kind) {
      case ArchiveKind.zip:
        return _fromZip(bytes);
      case ArchiveKind.rar:
      case ArchiveKind.sevenZip:
        final decoder = _external[kind];
        if (decoder == null) {
          throw ArchiveImportException(
            '${kind == ArchiveKind.rar ? 'RAR' : '7z'} 归档需要原生解码器：'
            '请在 import_book_service.dart 启动时调用 '
            'ArchiveImportHelper.registerExternalDecoder(ArchiveKind.$kind, 原生解码回调)。',
          );
        }
        return decoder(path, kind);
      case ArchiveKind.unknown:
        throw const ArchiveImportException('无法识别的归档格式（仅支持 zip/rar/7z）。');
    }
  }

  static List<ArchiveEntry> _fromZip(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final out = <ArchiveEntry>[];
    for (final f in archive) {
      if (!f.isFile) continue;
      final dynamic raw = f.content;
      if (raw is! List) continue;
      out.add(ArchiveEntry(f.name, Uint8List.fromList(List<int>.from(raw))));
    }
    return out;
  }

  /// 把归档内的书文件写入临时目录，返回本地路径（供导入服务建 Book）。
  static Future<List<String>> extractBookEntriesToTemp(
      String archivePath) async {
    final entries = await open(archivePath);
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final out = <String>[];
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      if (!e.isBookFile) continue;
      final safe = p.basename(e.name).replaceAll(RegExp(r'[^\w.\-\u4e00-\u9fa5]'), '_');
      final f = File(p.join(dir.path, 'import_${stamp}_${i}_$safe'));
      await f.writeAsBytes(e.bytes, flush: true);
      out.add(f.path);
    }
    return out;
  }
}

/// MOBI HUFF/CDIC 解压结果（从 PDB 记录切出的三块数据）。
class MobiHuffParts {
  final Uint8List huff;
  final List<Uint8List> cdics;
  final Uint8List data;

  const MobiHuffParts({required this.huff, required this.cdics, required this.data});
}

/// MOBI HUFF/CDIC 的 Dart 侧调用封装（真实调 [NativeBridge.mobiHuffDecompress]）。
///
/// 主代理的 `import_book_service.dart` 遇到 HUFF/CDIC 压缩的 MOBI 时：
/// ```dart
/// final text = await MobiHuffDecompressor.decompressFile(path);
/// // text 为解码后的正文（UTF-8 / 按原编码），再交给本地书解析器切章。
/// ```
class MobiHuffDecompressor {
  MobiHuffDecompressor._();

  /// PalmDOC compression=17480 表示 HUFF/CDIC。
  static const int huffCdicCompression = 17480;

  /// 从 PDB/MOBI 字节里切出 HUFF 记录、CDIC 记录与压缩正文数据。
  static MobiHuffParts? parse(Uint8List bytes) {
    if (bytes.length < 78) return null;
    final bd = ByteData.sublistView(bytes);
    final numRecords = bd.getUint16(76, Endian.big);
    final offsets = <int>[];
    for (var i = 0; i < numRecords; i++) {
      final pos = 78 + i * 8;
      if (pos + 4 > bytes.length) break;
      offsets.add(bd.getUint32(pos, Endian.big));
    }
    if (offsets.length < 2) return null;

    Uint8List record(int i) => Uint8List.sublistView(
        bytes, offsets[i], i + 1 < offsets.length ? offsets[i + 1] : bytes.length);

    final rec0 = record(0);
    if (rec0.length < 12) return null;
    final r0 = ByteData.sublistView(rec0);
    final compression = r0.getUint16(0, Endian.big);
    final textRecordCount = r0.getUint16(8, Endian.big);
    if (compression != huffCdicCompression) return null;

    final huffIndex = textRecordCount + 1;
    if (huffIndex >= offsets.length) return null;
    final huff = record(huffIndex);
    final cdics = <Uint8List>[];
    for (var i = huffIndex + 1; i < offsets.length; i++) {
      final r = record(i);
      if (r.length >= 4 && String.fromCharCodes(r.sublist(0, 4)) == 'CDIC') {
        cdics.add(r);
      }
    }
    if (cdics.isEmpty) return null;

    final builder = BytesBuilder(copy: false);
    for (var i = 1; i <= textRecordCount && i < offsets.length; i++) {
      builder.add(record(i));
    }
    return MobiHuffParts(huff: huff, cdics: cdics, data: builder.takeBytes());
  }

  /// 直接对一段 HUFF/CDIC 压缩数据调用原生解码。
  static Future<Uint8List?> decompress({
    required Uint8List huff,
    required List<Uint8List> cdics,
    required Uint8List data,
  }) =>
      NativeBridge.instance.mobiHuffDecompress(huff, cdics, data);

  /// 打开本地 MOBI 文件：切分记录 → 调原生 HUFF/CDIC 解码 → 返回正文文本。
  static Future<String?> decompressFile(String path) async {
    final bytes = await File(path).readAsBytes();
    final parts = parse(bytes);
    if (parts == null) return null;
    final decoded = await decompress(
      huff: parts.huff,
      cdics: parts.cdics,
      data: parts.data,
    );
    if (decoded == null) return null;
    return const Utf8Decoder(allowMalformed: true).convert(decoded);
  }
}
