/// 本地书浏览式导入的可测纯逻辑。
///
/// 目录排序、扩展名过滤、递归扫描、文件名解析书名作者、入库判定均为
/// 顶层函数/类，不依赖任何 UI，便于单元测试直接覆盖。
library;

import 'dart:io';

import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/help/storage/import_book_service.dart';
import 'package:path/path.dart' as p;

/// 列表排序方式：名称 / 大小 / 时间。
enum LocalSortMode { name, size, time }

/// 文件名解析的默认规则：书名在前、作者在后，以「空格-空格」分隔。
/// 形如「三体 - 刘慈欣.txt」。命名分组为 name / author。
const String defaultFileNameRule = r'^(?<name>.+?)\s*[-—－]\s*(?<author>.+)$';

/// 内置兜底规则：作者《书名》。形如「刘慈欣《三体》.txt」。
const String _fallbackFileNameRule = r'^(?<author>.+?)《(?<name>.+)》$';

/// 可参与导入的扩展名集合，直接复用导入服务声明的类型，避免两处漂移。
final Set<String> bookFileExtensions = <String>{
  ...ImportBookService.supported,
  ...ImportBookService.archiveExts,
};

/// 去掉文件名扩展名，返回主干（无点时原样返回）。
String stripFileNameExtension(String fileName) {
  final i = fileName.lastIndexOf('.');
  return i > 0 ? fileName.substring(0, i) : fileName;
}

/// 判断是否是可导入的书籍文件（按扩展名，忽略大小写）。
bool isBookFile(String fileName) {
  final i = fileName.lastIndexOf('.');
  if (i <= 0 || i >= fileName.length - 1) return false;
  return bookFileExtensions.contains(fileName.substring(i + 1).toLowerCase());
}

/// 从文件系统实体取展示名。
String entityName(FileSystemEntity entity) => p.basename(entity.path);

/// 目录优先，其次按 [mode] 排序。
///
/// * 目录永远排在文件之前，且始终按名称升序；
/// * 文件在名称模式下按名称升序，在大小/时间模式下分别按
///   体积降序、修改时间降序（相同则回退名称升序）。
List<FileSystemEntity> sortDirectoryEntries(
  List<FileSystemEntity> entries,
  LocalSortMode mode,
) {
  final dirs = <FileSystemEntity>[];
  final files = <FileSystemEntity>[];
  for (final e in entries) {
    (e is Directory ? dirs : files).add(e);
  }

  int sizeOf(FileSystemEntity e) {
    try {
      return e.statSync().size;
    } catch (_) {
      return 0;
    }
  }

  int timeOf(FileSystemEntity e) {
    try {
      return e.statSync().modified.millisecondsSinceEpoch;
    } catch (_) {
      return 0;
    }
  }

  int byName(FileSystemEntity a, FileSystemEntity b) =>
      entityName(a).toLowerCase().compareTo(entityName(b).toLowerCase());

  dirs.sort(byName);
  files.sort((a, b) {
    switch (mode) {
      case LocalSortMode.name:
        return byName(a, b);
      case LocalSortMode.size:
        final c = sizeOf(b).compareTo(sizeOf(a));
        return c != 0 ? c : byName(a, b);
      case LocalSortMode.time:
        final c = timeOf(b).compareTo(timeOf(a));
        return c != 0 ? c : byName(a, b);
    }
  });
  return <FileSystemEntity>[...dirs, ...files];
}

/// 递归扫描出的单个书籍文件及其元数据。
class ScannedBook {
  const ScannedBook(this.path, this.size, this.modifiedMs);

  final String path;
  final int size;
  final int modifiedMs;

  String get name => p.basename(path);
}

/// 对 [root] 子树递归扫描，收集所有可导入的书籍文件。
///
/// 先以流方式枚举实体（只保留路径，不读文件内容），再按 [batchSize]
/// 分批并发读取元数据，避免一次性对所有文件做 I/O。
Future<List<ScannedBook>> scanDirectory(
  Directory root, {
  int batchSize = 16,
}) async {
  final entities = await root.list(recursive: true, followLinks: false).toList();
  final files = entities
      .whereType<File>()
      .where((f) => isBookFile(f.path))
      .toList(growable: false);

  final result = <ScannedBook>[];
  for (var i = 0; i < files.length; i += batchSize) {
    final batch = files.skip(i).take(batchSize).toList(growable: false);
    final metas = await Future.wait(batch.map((f) async {
      try {
        final st = await f.stat();
        return ScannedBook(f.path, st.size, st.modified.millisecondsSinceEpoch);
      } catch (_) {
        return ScannedBook(f.path, 0, 0);
      }
    }));
    result.addAll(metas);
  }
  return result;
}

/// 用命名分组为 name / author 的正则从文件名解析书名与作者。
///
/// 先尝试用户规则 [rule]，未命中则用内置「作者《书名》」规则兜底，
/// 仍未命中时以文件名主干为书名、作者置为「未知」。
({String name, String author}) parseBookNameFromFileName(
  String fileName, {
  String rule = defaultFileNameRule,
}) {
  final base = stripFileNameExtension(fileName);
  final matched = _matchNamedGroups(base, rule);
  if (matched != null) return matched;
  final fallback = _matchNamedGroups(base, _fallbackFileNameRule);
  if (fallback != null) return fallback;
  return (name: base, author: '未知');
}

({String name, String author})? _matchNamedGroups(String base, String rule) {
  if (rule.trim().isEmpty) return null;
  try {
    final m = RegExp(rule).firstMatch(base);
    if (m == null) return null;
    final name = m.namedGroup('name')?.trim();
    if (name == null || name.isEmpty) return null;
    final author = m.namedGroup('author')?.trim();
    return (name: name, author: (author == null || author.isEmpty) ? '未知' : author);
  } catch (_) {
    return null;
  }
}

/// 判断本地路径是否已入库。
///
/// 本地书入库时 bookUrl / noteUrl 记为 `local://<path>`，PDF 另以
/// fileName 保存完整路径；三者任一匹配即视为已入库。
bool isImported(String path, Iterable<Book> books) {
  final localUrl = 'local://$path';
  return books.any((b) =>
      b.bookUrl == localUrl || b.noteUrl == localUrl || b.fileName == path);
}
