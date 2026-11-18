import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/help/storage/local_import_browse.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('local_import_browse_');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Future<File> makeFile(String name, {String content = 'x', int? modifiedMs}) async {
    final f = File('${tmp.path}/$name');
    await f.writeAsString(content);
    if (modifiedMs != null) await f.setLastModified(DateTime.fromMillisecondsSinceEpoch(modifiedMs));
    return f;
  }

  group('排序', () {
    test('默认目录优先 + 名称升序', () async {
      await Directory('${tmp.path}/zz_dir').create();
      await Directory('${tmp.path}/aa_dir').create();
      await makeFile('b.txt');
      await makeFile('a.txt');

      final sorted = sortDirectoryEntries(tmp.listSync(), LocalSortMode.name);
      final names = sorted.map(entityName).toList();

      expect(names.sublist(0, 2), <String>['aa_dir', 'zz_dir'], reason: '目录始终在前且按名称');
      expect(names.sublist(2), <String>['a.txt', 'b.txt'], reason: '文件按名称升序');
    });

    test('按大小降序，目录仍优先', () async {
      await Directory('${tmp.path}/dir').create();
      await makeFile('small.txt', content: 'x');
      await makeFile('big.txt', content: 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx');

      final sorted = sortDirectoryEntries(tmp.listSync(), LocalSortMode.size);
      final names = sorted.map(entityName).toList();

      expect(names.first, 'dir');
      expect(names.sublist(1), <String>['big.txt', 'small.txt']);
    });

    test('按时间降序，最新在前', () async {
      final base = DateTime(2020, 1, 1).millisecondsSinceEpoch;
      await makeFile('old.txt', modifiedMs: base);
      await makeFile('new.txt', modifiedMs: base + 100000);

      final sorted = sortDirectoryEntries(tmp.listSync(), LocalSortMode.time);
      expect(sorted.map(entityName).toList(), <String>['new.txt', 'old.txt']);
    });
  });

  group('扩展名过滤', () {
    test('只保留导入服务支持的书籍/压缩包扩展名', () {
      expect(isBookFile('book.txt'), isTrue);
      expect(isBookFile('BOOK.EPUB'), isTrue);
      expect(isBookFile('a.pdf'), isTrue);
      expect(isBookFile('a.mobi'), isTrue);
      expect(isBookFile('a.azw3'), isTrue);
      expect(isBookFile('pack.zip'), isTrue);
      expect(isBookFile('doc.docx'), isFalse);
      expect(isBookFile('noext'), isFalse);
      expect(isBookFile('trailing.'), isFalse);
    });
  });

  group('递归扫描', () {
    test('收集子树内全部书籍文件，排除非书籍文件', () async {
      final sub = Directory('${tmp.path}/sub')..createSync();
      final deep = Directory('${sub.path}/deep')..createSync();
      await makeFile('top.txt');
      await File('${sub.path}/mid.epub').writeAsString('x');
      await File('${deep.path}/bottom.pdf').writeAsString('x');
      await File('${sub.path}/notes.md').writeAsString('x');

      final found = await scanDirectory(tmp, batchSize: 2);
      final names = found.map((s) => s.name).toList()..sort();

      expect(names, <String>['bottom.pdf', 'mid.epub', 'top.txt']);
      expect(found.every((s) => s.path.contains(tmp.path)), isTrue);
    });

    test('并发分批参数不影响收集结果', () async {
      for (var i = 0; i < 5; i++) {
        await makeFile('f$i.txt');
      }
      final found = await scanDirectory(tmp, batchSize: 2);
      expect(found.length, 5);
    });
  });

  group('文件名解析', () {
    test('默认规则「书名 - 作者」', () {
      final info = parseBookNameFromFileName('三体 - 刘慈欣.txt');
      expect(info.name, '三体');
      expect(info.author, '刘慈欣');
    });

    test('内置兜底规则「作者《书名》」', () {
      final info = parseBookNameFromFileName('刘慈欣《三体》.txt');
      expect(info.name, '三体');
      expect(info.author, '刘慈欣');
    });

    test('无匹配时以文件名为书名、作者未知', () {
      final info = parseBookNameFromFileName('随笔.txt');
      expect(info.name, '随笔');
      expect(info.author, '未知');
    });

    test('用户自定义规则优先', () {
      final info = parseBookNameFromFileName(
        '[作者]书名.txt',
        rule: r'^\[(?<author>.+?)\](?<name>.+)$',
      );
      expect(info.author, '作者');
      expect(info.name, '书名');
    });
  });

  group('isImported 判定', () {
    test('bookUrl / noteUrl / fileName 任一命中即为已入库', () {
      const path = '/storage/emulated/0/books/a.txt';
      final byUrl = Book(name: 'n', author: 'a', bookUrl: 'local://$path');
      final byNote = Book(name: 'n', author: 'a', noteUrl: 'local://$path');
      final byFile = Book(name: 'n', author: 'a', fileName: path);
      final other = Book(name: 'n', author: 'a', bookUrl: 'local:///other.txt');

      expect(isImported(path, <Book>[byUrl]), isTrue);
      expect(isImported(path, <Book>[byNote]), isTrue);
      expect(isImported(path, <Book>[byFile]), isTrue);
      expect(isImported(path, <Book>[other]), isFalse);
      expect(isImported(path, <Book>[]), isFalse);
    });
  });

  group('页面静态契约', () {
    test('浏览式导入页包含关键入口', () {
      final source = File('lib/ui/book/local_import_screen.dart').readAsStringSync();
      for (final token in <String>[
        '扫描当前目录',
        '按文件名导入',
        '批量导入选中',
        '删除源文件',
        '返回上级',
        'readerForBook',
        'PopupMenuButton',
        'AppSwitchTile',
        'isImported',
        'getExternalStorageDirectory',
        'scanDirectory',
      ]) {
        expect(source, contains(token), reason: '缺少入口：$token');
      }
    });
  });
}
