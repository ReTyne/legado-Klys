import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/help/storage/import_book_service.dart';

/// 回归「代码调用 / 互相联系」：LocalBookParser.parse() 补齐的元数据必须
/// 经 ImportBookService.enrichMetadataFromParser 真正进入导入的 Book，
/// 否则本地书解析能力就是「算了不用」的孤儿实现。
void main() {
  late Directory tmp;
  late String pdfPath;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('legado_import_wire_');
    pdfPath = '${tmp.path}/一本本地书.pdf';
    // 最小 PDF：含明文 Document Info 字典 + 一段正文文本流，供纯 Dart 扫描提取。
    // PDF 字面量字符串按 PDFDocEncoding/latin1 解码，故 Info 用 ASCII
    // （中文/UTF-16 BOM 的解析能力由 local_book_parser_metadata_test 覆盖）。
    const content = '''
%PDF-1.4
1 0 obj
<< /Type /Catalog >>
endobj
2 0 obj
<< /Title (Real Book Title From Info) /Author (Real Author) /Subject (This is an intro extracted from the Info dictionary for wiring test.) >>
endobj
3 0 obj
<< /Length 44 >>
stream
BT (Chapter one content for word count hello world) ET
endstream
endobj
trailer
<< /Info 2 0 R >>
%%EOF
''';
    await File(pdfPath).writeAsString(content);
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('导入 PDF 时 parse 的元数据被回填到 Book（真实调用链）', () async {
    // 模拟 _importSingle 里 pdf 分支造出的最小 Book：只有文件名兜底名 / 未知作者
    final book = Book(
      name: '一本本地书',
      author: '未知',
      origin: 'local',
      originName: '本地书籍',
      noteUrl: 'local://$pdfPath',
      bookUrl: 'local://$pdfPath',
      type: 1,
      local: true,
      fileName: pdfPath,
      lastChapter: '正文',
    );

    await ImportBookService.enrichMetadataFromParser(
        book, pdfPath, '一本本地书.pdf');

    // 关键：书名/作者从「文件名兜底 / 未知」升级为 Info 字典里的真实元数据，
    // 证明 LocalBookParser.parse() 的产出确实被 enrich 消费进 Book（调用链成立）。
    expect(book.name, 'Real Book Title From Info');
    expect(book.author, 'Real Author');
    // 简介：Info 的 /Subject 被提取（PDF 正文流提取属解析器自身能力，
    // 由 local_book_parser_metadata_test 覆盖，此处不重复较劲）。
    expect(book.intro, isNotNull);
    expect(book.intro, contains('Info dictionary'));
    // 导入契约字段不被破坏
    expect(book.origin, 'local');
    expect(book.noteUrl, 'local://$pdfPath');
    expect(book.type, 1);
    expect(book.local, isTrue);
  });

  test('enrich 不覆盖已有的正确元数据（幂等、保护用户数据）', () async {
    final book = Book(
      name: '用户自定义书名',
      author: '用户指定作者',
      intro: '用户填写的简介',
      origin: 'local',
      noteUrl: 'local://$pdfPath',
      type: 1,
      local: true,
      wordCount: 999,
    );

    await ImportBookService.enrichMetadataFromParser(
        book, pdfPath, '一本本地书.pdf');

    expect(book.name, '用户自定义书名');
    expect(book.author, '用户指定作者');
    expect(book.intro, '用户填写的简介');
    expect(book.wordCount, 999);
  });

  test('解析失败/非支持格式时 enrich 安全返回、不影响导入主流程', () async {
    final missing = '${tmp.path}/不存在.pdf';
    final book = Book(
      name: '一本本地书',
      author: '未知',
      origin: 'local',
      noteUrl: 'local://$missing',
      type: 1,
      local: true,
    );
    // 不应抛异常
    await expectLater(
      ImportBookService.enrichMetadataFromParser(book, missing, '不存在.pdf'),
      completes,
    );
    expect(book.name, '一本本地书'); // 保持原状
  });
}
