import 'dart:convert';
import 'dart:io';

import 'package:enough_convert/enough_convert.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legado_md3/help/storage/local_book_parser.dart';

// ========== 离线 fixture 构造（不依赖网络/平台通道） ==========

List<int> _be32(int v) => [
      (v >> 24) & 0xff,
      (v >> 16) & 0xff,
      (v >> 8) & 0xff,
      v & 0xff,
    ];

void _put16(List<int> b, int off, int v) {
  b[off] = (v >> 8) & 0xff;
  b[off + 1] = v & 0xff;
}

void _put32(List<int> b, int off, int v) {
  b[off] = (v >> 24) & 0xff;
  b[off + 1] = (v >> 16) & 0xff;
  b[off + 2] = (v >> 8) & 0xff;
  b[off + 3] = v & 0xff;
}

/// EXTH 记录：type(4) + length(4, 含 8 字节头) + data。
List<int> _exthRecord(int type, List<int> data) =>
    [..._be32(type), ..._be32(8 + data.length), ...data];

/// 最小 PalmDB/MOBI(KF7, 无压缩) fixture：
/// record0=PalmDOC+MOBI+EXTH，record1=正文，record2=封面图片。
/// 字段偏移对齐 legado-E 的 MobiReader（exthFlag@128、resource@108、EXTH=headerLen+16）。
List<int> _buildMobi({
  required String pdbName,
  String? exthTitle,
  String? author,
  String? description,
  String? subject,
  required String text,
  List<int> cover = const [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x00],
  int compression = 1,
  bool withExth = true,
}) {
  final textBytes = utf8.encode(text);
  final records = <int>[];
  var count = 0;
  if (withExth) {
    if (author != null) {
      records.addAll(_exthRecord(100, utf8.encode(author)));
      count++;
    }
    if (description != null) {
      records.addAll(_exthRecord(103, utf8.encode(description)));
      count++;
    }
    if (subject != null) {
      records.addAll(_exthRecord(105, utf8.encode(subject)));
      count++;
    }
    if (exthTitle != null) {
      records.addAll(_exthRecord(503, utf8.encode(exthTitle)));
      count++;
    }
    records.addAll(_exthRecord(201, _be32(2))); // coverOffset -> record 2
    count++;
  }
  const mobiLen = 232;
  final exth = <int>[
    ...ascii.encode('EXTH'),
    ..._be32(12 + records.length),
    ..._be32(count),
    ...records,
  ];

  final rec0 = List<int>.filled(16 + mobiLen + exth.length, 0);
  _put16(rec0, 0, compression);
  _put32(rec0, 4, textBytes.length); // textLength
  _put16(rec0, 8, 1); // recordCount（文本记录数）
  _put16(rec0, 10, 4096);
  rec0.setRange(16, 20, ascii.encode('MOBI'));
  _put32(rec0, 20, mobiLen);
  _put32(rec0, 24, 2); // mobiType
  _put32(rec0, 28, 65001); // UTF-8
  _put32(rec0, 36, 6); // version
  _put32(rec0, 84, 0); // fullName offset（不启用）
  _put32(rec0, 88, 0); // fullName length
  _put32(rec0, 108, 2); // firstResourceIndex
  _put32(rec0, 112, 0); // huffcdic
  _put32(rec0, 128, withExth ? 0x40 : 0); // exthFlag（E: readUInt32(128)）
  rec0.setRange(16 + mobiLen, 16 + mobiLen + exth.length, exth);

  const numRecords = 3;
  final header = List<int>.filled(78 + numRecords * 8, 0);
  final nameBytes = ascii.encode(pdbName);
  header.setRange(0, nameBytes.length, nameBytes); // 其余字节为 0（NUL 结尾 + 填充）
  header.setRange(60, 64, ascii.encode('BOOK'));
  header.setRange(64, 68, ascii.encode('MOBI'));
  _put16(header, 76, numRecords);

  final out = <int>[...header, ...rec0, ...textBytes, ...cover];
  final off0 = header.length;
  final off1 = off0 + rec0.length;
  final off2 = off1 + textBytes.length;
  _put32(out, 78, off0);
  _put32(out, 86, off1);
  _put32(out, 94, off2);
  return out;
}

/// 最小 PDF：含未压缩的 Document Information Dictionary 与一个文本流。
List<int> _buildPdf({
  String? title,
  String? author,
  String? subject,
  String bodyText = 'Hello PDF World',
  String? hexTitleUtf16,
}) {
  final stream = 'BT /F1 12 Tf ($bodyText) Tj ET';
  final infoParts = <String>[];
  if (title != null) infoParts.add('/Title ($title)');
  if (author != null) infoParts.add('/Author ($author)');
  if (subject != null) infoParts.add('/Subject ($subject)');
  if (hexTitleUtf16 != null) infoParts.add('/Title <$hexTitleUtf16>');
  final info = infoParts.join(' ');
  final pdf = '%PDF-1.4\n'
      '2 0 obj\n<< $info >>\nendobj\n'
      '5 0 obj\n<< /Length ${stream.length} >>\nstream\n$stream\nendstream\nendobj\n'
      'trailer\n<< /Info 2 0 R >>\n%%EOF\n';
  return latin1.encode(pdf);
}

/// UMD TLV 块：1 字节 type + 4 字节大端长度 + data。
List<int> _tlv(int type, List<int> data) =>
    [type, ..._be32(data.length), ...data];

/// 最小 UMD：0x02 书名 0x03 作者 0x07 类别 0x82 封面 0x83 正文（首字节为随机填充）。
List<int> _buildUmd({
  required String title,
  required String author,
  String? kind,
  required String text,
  List<int> cover = const [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x00],
}) {
  return [
    ..._tlv(0x02, const GbkCodec().encode(title)),
    ..._tlv(0x03, const GbkCodec().encode(author)),
    if (kind != null) ..._tlv(0x07, const GbkCodec().encode(kind)),
    ..._tlv(0x82, cover),
    ..._tlv(0x83, [0x00, ...const GbkCodec().encode(text)]),
  ];
}

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('local_book_parser_meta_test_');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<String> write(String name, List<int> bytes) async {
    final f = File('${tmp.path}/$name');
    await f.writeAsBytes(bytes);
    return f.path;
  }

  group('MOBI 元数据（对齐 E 的 MobiFile.upBookInfo / MobiBook.metadata）', () {
    test('从 EXTH 提取书名/作者/简介，统计正文字数，导出封面', () async {
      const text = '第一章\n这是MOBI正文测试内容。\n第二章\n更多正文。';
      final path = await write(
          'book.mobi',
          _buildMobi(
            pdbName: 'PdbFallbackName',
            exthTitle: '书名来自EXTH',
            author: 'EXTH作者',
            description: '这是EXTH里的简介内容',
            subject: 'EXTH主题',
            text: text,
          ));

      final book = await LocalBookParser.parse(path);
      expect(book, isNotNull);
      expect(book!.name, '书名来自EXTH'); // EXTH 503 优先于 PDB 头书名
      expect(book.author, 'EXTH作者');
      expect(book.intro, '这是EXTH里的简介内容');
      expect(book.wordCount, text.length);
      expect(book.coverUrl, isNotNull);
      expect(File(book.coverUrl!).existsSync(), isTrue);
      expect(book.local, isTrue);
      expect(book.fileName, path);
      // 真实消费：元数据写进 Book 并进入持久化 map（书架排序/详情页读取）
      expect(book.toMap()['wordCount'], text.length);
      expect(book.toMap()['intro'], '这是EXTH里的简介内容');
    });

    test('无 EXTH 时按 PDB 头回退书名、作者未知、简介取正文开头', () async {
      const text = '第一章 纯正文没有元数据。';
      final path = await write(
          'noexth.mobi',
          _buildMobi(
            pdbName: 'PdbOnlyName',
            text: text,
            withExth: false,
          ));

      final book = await LocalBookParser.parse(path);
      expect(book, isNotNull);
      expect(book!.name, 'PdbOnlyName');
      expect(book.author, '未知作者');
      expect(book.intro, text); // 正文开头兜底（<200 字原样）
      expect(book.wordCount, text.length);
    });

    test('HUFF/CDIC 高压缩：正文给出明确边界提示，EXTH 元数据仍可提取', () async {
      final path = await write(
          'huff.mobi',
          _buildMobi(
            pdbName: 'HuffBook',
            exthTitle: '高压缩书名',
            author: '高压缩作者',
            text: 'compressed body',
            compression: 17480,
          ));

      final book = await LocalBookParser.parse(path);
      expect(book, isNotNull);
      expect(book!.name, '高压缩书名'); // 元数据区在 record0 明文，不受正文压缩影响
      expect(book.wordCount, isNull); // 正文解压为平台边界

      final content = await LocalBookParser.readChapter(path, 0, const []);
      expect(content, isNotNull);
      expect(content, contains('HUFF/CDIC'));
    });
  });

  group('PDF 元数据（对齐 E 的 PdfFile.upBookInfo）', () {
    test('从 Info 字典取 /Title /Author /Subject，用正文流统计字数', () async {
      final path = await write(
          'book.pdf',
          _buildPdf(
            title: 'PDF Title',
            author: 'PDF Author',
            subject: 'PDF Subject Intro',
            bodyText: 'Hello PDF World',
          ));

      final book = await LocalBookParser.parse(path);
      expect(book, isNotNull);
      expect(book!.name, 'PDF Title');
      expect(book.author, 'PDF Author');
      expect(book.intro, 'PDF Subject Intro');
      expect(book.wordCount, 'Hello PDF World'.length);
      expect(book.coverUrl, isNull); // 封面渲染属平台边界，不写假路径
      expect(book.toMap()['wordCount'], 'Hello PDF World'.length);
    });

    test('无 Info 字典时按文件名 + 正文流兜底', () async {
      final path = await write('plain.pdf', _buildPdf(bodyText: 'Fallback Body'));

      final book = await LocalBookParser.parse(path);
      expect(book, isNotNull);
      expect(book!.name, 'plain');
      expect(book.author, '未知作者');
      expect(book.wordCount, 'Fallback Body'.length);
      expect(book.intro, 'Fallback Body');
    });

    test('Info 十六进制 UTF-16BE 标题（含 BOM）正确解码', () async {
      // FEFF BOM + 中(4E2D) 文(6587)
      final path = await write(
          'utf16.pdf',
          _buildPdf(hexTitleUtf16: 'FEFF4E2D6587', bodyText: 'Body'));

      final book = await LocalBookParser.parse(path);
      expect(book, isNotNull);
      expect(book!.name, '中文');
      expect(book.wordCount, 'Body'.length);
    });
  });

  group('UMD 元数据（对齐 E 的 UmdFile.upBookInfo）', () {
    test('复用 TLV 取书名/作者/类别，统计正文字数，导出封面', () async {
      const body = '这是UMD正文ABC内容。';
      final path = await write(
          'book.umd',
          _buildUmd(
            title: 'UmdTitle',
            author: 'UmdAuthor',
            kind: 'Comic',
            text: body,
          ));

      final book = await LocalBookParser.parse(path);
      expect(book, isNotNull);
      expect(book!.name, 'UmdTitle');
      expect(book.author, 'UmdAuthor');
      expect(book.kind, 'Comic');
      expect(book.wordCount, isNotNull);
      expect(book.wordCount! > 0, isTrue);
      expect(book.intro, isNotNull);
      expect(book.intro!.contains('UMD'), isTrue);
      expect(book.coverUrl, isNotNull);
      expect(File(book.coverUrl!).existsSync(), isTrue);
      expect(book.toMap()['wordCount'], book.wordCount);
    });

    test('空/损坏 UMD 安全兜底，不抛异常', () async {
      final path = await write('empty.umd', <int>[]);

      final book = await LocalBookParser.parse(path);
      expect(book, isNotNull);
      expect(book!.name, 'empty'); // 按文件名兜底
      expect(book.wordCount, isNull);
      expect(book.author, '未知作者');
    });
  });
}
