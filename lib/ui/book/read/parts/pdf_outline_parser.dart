/// 由 pdf_reader_screen.dart 按「一类一文件」拆出的 _PdfOutlineParser。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../pdf_reader_screen.dart';


/// PDF 内置 /Outlines 大纲解析（纯 Dart）。
///
/// pdfx 2.6.0 未暴露 pdfium 的 FPDFBookmark_* 接口，因此直接解析 PDF 文件结构：
/// 扫描 `N G obj ... endobj`，把 /ObjStm（FlateDecode）里的压缩对象合并进对象表，
/// 由 /Pages 树建立「页对象编号 -> 0-based 页序」，再沿 /Outlines 的
/// /First -> /Next 链（含 /First 子层级）提取标题与 /Dest、/A /D 的目标页。
/// 加密文档 / 命名目标 / 无内置大纲时返回空列表，由 UI 的手动目录兜底。
class _PdfOutlineParser {
  _PdfOutlineParser._();

  static final RegExp _objRe =
      RegExp(r'(\d+)\s+(\d+)\s+obj\b([\s\S]*?)\bendobj');
  static final RegExp _refRe = RegExp(r'(\d+)\s+\d+\s+R');

  static ({List<PdfOutline> outlines, bool found}) parse(
    Uint8List bytes, {
    required String bookName,
    required String author,
    required int totalPages,
  }) {
    final text = String.fromCharCodes(bytes);
    final objects = <int, String>{};
    for (final m in _objRe.allMatches(text)) {
      final num = int.tryParse(m.group(1)!) ?? -1;
      if (num > 0) objects[num] = m.group(3)!;
    }
    _expandObjectStreams(objects);

    final pageOrder = _buildPageOrder(objects);

    int? root;
    for (final e in objects.entries) {
      if (RegExp(r'/Type\s*/Outlines').hasMatch(e.value)) {
        root = e.key;
        break;
      }
    }
    if (root == null) {
      for (final e in objects.entries) {
        if (RegExp(r'/Type\s*/Catalog').hasMatch(e.value)) {
          root = _firstRef(e.value, '/Outlines');
          if (root != null) break;
        }
      }
    }
    if (root == null) return (outlines: <PdfOutline>[], found: false);

    final raw = <_RawOutline>[];
    final visited = <int>{};
    void walk(int? ref, int level) {
      var cur = ref;
      while (cur != null && visited.add(cur) && raw.length < 5000) {
        final body = objects[cur];
        if (body == null) break;
        raw.add(_RawOutline(
            _decodeTitle(body), level, _destPageRef(body) == null
                ? null
                : pageOrder[_destPageRef(body)]));
        final child = _firstRef(body, '/First');
        if (child != null) walk(child, level + 1);
        cur = _firstRef(body, '/Next');
      }
    }
    walk(_firstRef(objects[root] ?? '', '/First'), 0);

    final list = <PdfOutline>[];
    var lastPage = 0;
    for (final r in raw) {
      if (r.title.isEmpty) continue;
      if (r.page != null) lastPage = r.page!;
      var page = lastPage;
      if (totalPages > 0 && page >= totalPages) page = totalPages - 1;
      if (page < 0) page = 0;
      list.add(PdfOutline(
        bookName: bookName,
        author: author,
        title: r.title,
        level: r.level.clamp(0, 8),
        page: page,
        order: list.length,
      ));
    }
    return (outlines: list, found: true);
  }

  /// 解压 /ObjStm，把其中压缩的间接对象合并进对象表。
  static void _expandObjectStreams(Map<int, String> objects) {
    for (final entry in List.of(objects.entries)) {
      final body = entry.value;
      if (!RegExp(r'/Type\s*/ObjStm').hasMatch(body)) continue;
      final n = int.tryParse(
              RegExp(r'/N\s+(\d+)').firstMatch(body)?.group(1) ?? '') ??
          0;
      final first = int.tryParse(
              RegExp(r'/First\s+(\d+)').firstMatch(body)?.group(1) ?? '') ??
          0;
      if (n <= 0 || first <= 0) continue;
      final start = body.indexOf('stream');
      if (start < 0) continue;
      var dataStart = start + 'stream'.length;
      if (dataStart < body.length && body[dataStart] == '\r') dataStart++;
      if (dataStart < body.length && body[dataStart] == '\n') dataStart++;
      final end = body.indexOf('endstream', dataStart);
      if (end < 0 || end <= dataStart) continue;
      final rawBytes = Uint8List.fromList(
          body.codeUnits.sublist(dataStart, end));
      List<int> decoded;
      try {
        decoded = RegExp(r'/FlateDecode').hasMatch(body)
            ? ZLibCodec().decode(rawBytes)
            : rawBytes;
      } catch (_) {
        continue;
      }
      final inner = String.fromCharCodes(decoded);
      final header =
          inner.substring(0, first.clamp(0, inner.length));
      final pairs = RegExp(r'(\d+)\s+(\d+)').allMatches(header).toList();
      if (pairs.length < n) continue;
      for (var i = 0; i < n; i++) {
        final objNum = int.tryParse(pairs[i].group(1)!) ?? -1;
        final off = int.tryParse(pairs[i].group(2)!) ?? 0;
        final nextOff = i + 1 < n
            ? (int.tryParse(pairs[i + 1].group(2)!) ?? inner.length)
            : inner.length;
        final seg = inner.substring(
            (first + off).clamp(0, inner.length),
            (first + nextOff).clamp(0, inner.length));
        if (objNum > 0) objects.putIfAbsent(objNum, () => seg);
      }
    }
  }

  /// 建立页对象编号 -> 0-based 页序；优先 /Pages 树，回退按对象编号排序。
  static Map<int, int> _buildPageOrder(Map<int, String> objects) {
    final order = <int, int>{};
    int? root;
    for (final e in objects.entries) {
      if (RegExp(r'/Type\s*/Catalog').hasMatch(e.value)) {
        root = _firstRef(e.value, '/Pages');
        if (root != null) break;
      }
    }
    if (root == null) {
      for (final e in objects.entries) {
        if (RegExp(r'/Type\s*/Pages\b').hasMatch(e.value) &&
            !e.value.contains('/Parent')) {
          root = e.key;
          break;
        }
      }
    }
    final visited = <int>{};
    void walk(int? ref) {
      if (ref == null || !visited.add(ref)) return;
      final body = objects[ref];
      if (body == null) return;
      if (RegExp(r'/Type\s*/Page\b').hasMatch(body)) {
        order[ref] = order.length;
        return;
      }
      final kids = RegExp(r'/Kids\s*\[([\s\S]*?)\]').firstMatch(body);
      if (kids == null) return;
      for (final m in _refRe.allMatches(kids.group(1)!)) {
        walk(int.tryParse(m.group(1)!));
      }
    }
    walk(root);
    if (order.isEmpty) {
      final pages = objects.entries
          .where((e) => RegExp(r'/Type\s*/Page\b').hasMatch(e.value))
          .map((e) => e.key)
          .toList()
        ..sort();
      for (var i = 0; i < pages.length; i++) {
        order[pages[i]] = i;
      }
    }
    return order;
  }

  static int? _firstRef(String body, String key) {
    final kidx = body.indexOf(key);
    if (kidx < 0) return null;
    final m = _refRe.firstMatch(body.substring(kidx + key.length));
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  static int? _destPageRef(String body) {
    for (final pattern in [r'/Dest\b', r'/D\b']) {
      final m = RegExp('$pattern([\\s\\S]{0,160})').firstMatch(body);
      if (m == null) continue;
      final ref = _refRe.firstMatch(m.group(1)!);
      if (ref != null) return int.tryParse(ref.group(1)!);
    }
    return null;
  }

  static String _decodeTitle(String body) {
    final m = RegExp(r'/Title\s*').firstMatch(body);
    if (m == null) return '';
    final rest = body.substring(m.end);
    if (rest.startsWith('(')) return _literalString(rest);
    if (rest.startsWith('<')) return _hexString(rest);
    return '';
  }

  static String _literalString(String s) {
    final buf = <int>[];
    var depth = 0;
    var i = 0;
    while (i < s.length) {
      final c = s.codeUnitAt(i);
      if (c == 0x28) {
        depth++;
        if (depth > 1) buf.add(c);
        i++;
        continue;
      }
      if (c == 0x29) {
        depth--;
        if (depth == 0) break;
        buf.add(c);
        i++;
        continue;
      }
      if (c == 0x5C && i + 1 < s.length) {
        final n = s.codeUnitAt(i + 1);
        switch (n) {
          case 0x6E: buf.add(0x0A); i += 2; continue;
          case 0x72: buf.add(0x0D); i += 2; continue;
          case 0x74: buf.add(0x09); i += 2; continue;
          case 0x62: buf.add(0x08); i += 2; continue;
          case 0x66: buf.add(0x0C); i += 2; continue;
          case 0x28: buf.add(0x28); i += 2; continue;
          case 0x29: buf.add(0x29); i += 2; continue;
          case 0x5C: buf.add(0x5C); i += 2; continue;
          case 0x0D:
            i += 2;
            if (i < s.length && s.codeUnitAt(i) == 0x0A) i++;
            continue;
          case 0x0A: i += 2; continue;
          default:
            if (n >= 0x30 && n <= 0x37) {
              var oct = '';
              var j = i + 1;
              while (j < s.length && oct.length < 3 &&
                  s.codeUnitAt(j) >= 0x30 && s.codeUnitAt(j) <= 0x37) {
                oct += s[j];
                j++;
              }
              buf.add(int.parse(oct, radix: 8) & 0xFF);
              i = j;
              continue;
            }
            buf.add(n);
            i += 2;
            continue;
        }
      }
      buf.add(c);
      i++;
    }
    return _fromBytes(buf);
  }

  static String _hexString(String s) {
    final end = s.indexOf('>');
    if (end < 0) return '';
    var hex = s.substring(1, end).replaceAll(RegExp(r'\s'), '');
    if (hex.length.isOdd) hex += '0';
    final bytes = <int>[];
    for (var i = 0; i + 1 < hex.length; i += 2) {
      final v = int.tryParse(hex.substring(i, i + 2), radix: 16);
      if (v == null) return '';
      bytes.add(v);
    }
    return _fromBytes(bytes);
  }

  /// 处理 UTF-16 BOM；否则按 PDFDocEncoding（近似 Latin-1）返回。
  static String _fromBytes(List<int> bytes) {
    List<int> data = bytes;
    bool? bigEndian;
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      bigEndian = true;
      data = bytes.sublist(2);
    } else if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      bigEndian = false;
      data = bytes.sublist(2);
    }
    if (bigEndian != null) {
      final units = <int>[];
      for (var i = 0; i + 1 < data.length; i += 2) {
        units.add(bigEndian
            ? (data[i] << 8) | data[i + 1]
            : (data[i + 1] << 8) | data[i]);
      }
      return String.fromCharCodes(units).trim();
    }
    return String.fromCharCodes(data).trim();
  }
}
