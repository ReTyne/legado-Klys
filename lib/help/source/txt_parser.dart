import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:enough_convert/enough_convert.dart';
import 'package:legado_md3/data/model/book_chapter.dart';
import 'package:legado_md3/data/model/txt_toc_rule.dart';
import 'package:legado_md3/utils/encoding_detect.dart';

class TxtParserService {
  /// 自动识别编码并解码 TXT 字节（支持 UTF-8 / UTF-16 LE/BE / GBK / Big5）
  static String decodeBytes(List<int> bytes) {
    if (bytes.isEmpty) return '';
    final b = Uint8List.fromList(bytes);
    // BOM 检测
    if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
      return utf8.decode(bytes.sublist(3), allowMalformed: true);
    }
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      return utf16leDecode(bytes.sublist(2));
    }
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      return utf16beDecode(bytes.sublist(2));
    }
    // 统计探测：区分 UTF-8 / UTF-16 / GBK / Big5
    switch (EncodingDetector.detect(b)) {
      case 'utf-8':
        return utf8.decode(bytes, allowMalformed: true);
      case 'utf-16le':
        return utf16leDecode(bytes);
      case 'utf-16be':
        return utf16beDecode(bytes);
      case 'big5':
        try {
          return const Big5Codec().decode(bytes);
        } catch (_) {}
        return utf8.decode(bytes, allowMalformed: true);
      case 'gbk':
      default:
        try {
          return const GbkCodec().decode(bytes);
        } catch (_) {}
        return utf8.decode(bytes, allowMalformed: true);
    }
  }

  static String utf16leDecode(List<int> bytes) {
    final codes = <int>[];
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      codes.add(bytes[i] | (bytes[i + 1] << 8));
    }
    return String.fromCharCodes(codes);
  }

  static String utf16beDecode(List<int> bytes) {
    final codes = <int>[];
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      codes.add((bytes[i] << 8) | bytes[i + 1]);
    }
    return String.fromCharCodes(codes);
  }

  /// 读取文件并自动识别编码
  static Future<String> readFileAutoDetect(File file) async {
    return decodeBytes(await file.readAsBytes());
  }

  /// 默认章节匹配规则
  static const List<String> defaultPatterns = [
    r'^\s*第[零一二三四五六七八九十百千万两\d]+[章节回卷集部篇].*$',
    r'^\s*Chapter\s+\d+.*$',
    r'^\s*\d+\s*[、.．].*$',
  ];

  /// 解析TXT内容为章节列表。
  ///
  /// 同时记录每个章节在「规范化文本」中的字符区间 [startPos, endPos)：
  /// 规范化文本 = `LineSplitter.convert(content).join('\n')`（读取侧用同一
  /// 规范化方式还原，保证偏移精确可复现）。长章节拆分后的子章节同样带区间，
  /// 使 `LocalBookParser.readTxtChapter` 能按位置直取正文（标题匹配对
  /// `原标题(n)` 子章节会失效，必须走位置）。
  List<BookChapter> parseChapters(String content, {TxtTocRule? rule}) {
    final chapters = <BookChapter>[];
    final lines = const LineSplitter().convert(content);

    // 每行在规范化文本中的起始偏移（行间以单个 \n 连接）
    final lineStarts = <int>[];
    var p = 0;
    for (final line in lines) {
      lineStarts.add(p);
      p += line.length + 1;
    }
    final normalizedLength = lines.isEmpty ? 0 : (lineStarts.last + lines.last.length);

    // 确定匹配规则
    List<RegExp> patterns;
    if (rule != null && rule.chapterRule.isNotEmpty) {
      patterns = [RegExp(rule.chapterRule, multiLine: true)];
      if (rule.volumeRule.isNotEmpty) {
        patterns.add(RegExp(rule.volumeRule, multiLine: true));
      }
    } else {
      patterns = defaultPatterns.map((p) => RegExp(p)).toList();
    }

    int chapterStart = 0;
    String? currentTitle;
    int index = 0;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      // 检查是否匹配章节标题
      bool isChapter = false;
      for (final pattern in patterns) {
        if (pattern.hasMatch(line)) {
          isChapter = true;
          break;
        }
      }

      if (isChapter) {
        // 保存上一个章节
        if (currentTitle != null) {
          final chapterContent = lines.sublist(chapterStart, i).join('\n').trim();
          chapters.add(BookChapter(
            index: index,
            title: currentTitle,
            url: 'local://chapter/$index',
            content: chapterContent,
            startPos: lineStarts[chapterStart],
            endPos: lineStarts[i],
          ));
          index++;
        }
        currentTitle = line;
        chapterStart = i + 1;
      }
    }

    // 保存最后一个章节
    if (currentTitle != null) {
      final chapterContent = lines.sublist(chapterStart).join('\n').trim();
      chapters.add(BookChapter(
        index: index,
        title: currentTitle,
        url: 'local://chapter/$index',
        content: chapterContent,
        // 标题是最后一行时 chapterStart == lines.length（空正文），区间取全文末尾
        startPos: chapterStart < lines.length ? lineStarts[chapterStart] : normalizedLength,
        endPos: normalizedLength,
      ));
    }

    // 如果没有找到章节，将整个内容作为一章
    if (chapters.isEmpty) {
      chapters.add(BookChapter(
        index: 0,
        title: '正文',
        url: 'local://chapter/0',
        content: content.trim(),
        startPos: 0,
        endPos: normalizedLength,
      ));
    }

    return chapters;
  }

  /// 长章节拆分（对齐 legado-E model/localBook/TextFile.kt）：
  /// 超过 [maxChapterBytes]（E: maxLengthWithToc=102400）的章节按
  /// [chunkBytes]（E: maxLengthWithNoToc=10240）在换行处切分为多个子章节，
  /// 子章节命名为 `原标题(n)`（E 从 1 开始编号），原章节转为卷标（isVolume）。
  /// [enabled] 为 false 时原样返回（E: Book.splitLongChapter 开关）。
  ///
  /// [fullText] 为规范化全文（`LineSplitter.convert(content).join('\n')`）：
  /// 传入且章节带 startPos/endPos 时，子章节按全文字符区间切分并继承区间，
  /// 读取侧可按位置直取正文；不传则退化为按章节 content 拆分（无位置信息）。
  static List<BookChapter> splitLongChapters(
    List<BookChapter> chapters, {
    bool enabled = true,
    int maxChapterBytes = 102400,
    int chunkBytes = 10240,
    String? fullText,
  }) {
    if (!enabled) return chapters;
    final result = <BookChapter>[];
    var index = 0;
    for (final ch in chapters) {
      // 有全文 + 位置时用原始区间切片（content 被 trim 过，偏移会失真）
      final hasRange = ch.startPos != null && ch.endPos != null;
      String content;
      int rawStart;
      if (fullText != null && hasRange) {
        rawStart = ch.startPos!.clamp(0, fullText.length);
        final rawEnd = ch.endPos!.clamp(rawStart, fullText.length);
        content = fullText.substring(rawStart, rawEnd);
      } else {
        content = ch.content ?? '';
        rawStart = ch.startPos ?? 0;
      }
      if (utf8.encode(content).length <= maxChapterBytes) {
        result.add(BookChapter(
          title: ch.title,
          url: ch.url,
          index: index++,
          isVolume: ch.isVolume,
          isVip: ch.isVip,
          isPay: ch.isPay,
          updateTime: ch.updateTime,
          // 与 parseChapters 一致：入库 content 去首尾空白（读取侧按位置切片时也会 trim）
          content: content.trim(),
          startPos: hasRange ? rawStart : null,
          endPos: hasRange ? ch.endPos : null,
          variable: ch.variable,
        ));
        continue;
      }
      // 超长章节：原章节转为卷标（E: it.end = it.start，零长度区间）
      if (hasRange) {
        result.add(BookChapter(
          title: ch.title,
          url: 'local://volume/$index',
          index: index++,
          isVolume: true,
          startPos: rawStart,
          endPos: rawStart,
        ));
      } else {
        result.add(BookChapter(
          title: ch.title,
          url: 'local://volume/$index',
          index: index++,
          isVolume: true,
        ));
      }
      final lines = content.split('\n');
      final buf = <String>[];
      var bufBytes = 0;
      var chunkStart = 0; // 当前块在章节内容中的字符偏移
      var part = 1;
      void flush(int chunkEnd) {
        if (buf.isEmpty) return;
        result.add(BookChapter(
          title: '${ch.title}($part)',
          url: 'local://chapter/$index',
          index: index++,
          content: buf.join('\n').trim(),
          startPos: hasRange ? rawStart + chunkStart : null,
          endPos: hasRange ? rawStart + chunkEnd : null,
        ));
        part++;
        buf.clear();
        bufBytes = 0;
      }

      var offset = 0; // 已扫描内容（含行间 \n）的字符偏移
      for (final line in lines) {
        final lineBytes = utf8.encode(line).length + 1; // +1 近似行间 \n
        buf.add(line);
        bufBytes += lineBytes;
        offset += line.length + 1;
        // 与 E 一致：累计达到 chunkBytes 后在当前行边界切分
        if (bufBytes >= chunkBytes) {
          flush(offset);
          chunkStart = offset;
        }
      }
      flush(offset);
    }
    return result;
  }

  /// 目录重排后迁移阅读进度（对齐 E 重新解析目录后的位置保持思路）：
  /// 先按标题精确匹配；标题带 `(n)` 后缀的（旧列表已拆分）去掉后缀匹配父章节；
  /// 父章节变为卷标时落到其第一个子章节；都失败回退 0。
  static int remapChapterIndex(
    List<BookChapter> oldChapters,
    int oldIndex,
    List<BookChapter> newChapters,
  ) {
    if (newChapters.isEmpty) return 0;
    if (oldIndex < 0 || oldIndex >= oldChapters.length) {
      return oldIndex.clamp(0, newChapters.length - 1);
    }
    final oldTitle = oldChapters[oldIndex].title;
    // 1) 精确匹配
    for (var i = 0; i < newChapters.length; i++) {
      if (newChapters[i].title == oldTitle) {
        // 原章节已转为卷标：落到紧跟其后的第一个正文章节
        if (newChapters[i].isVolume) {
          for (var j = i + 1; j < newChapters.length; j++) {
            if (!newChapters[j].isVolume) return j;
          }
        }
        return i;
      }
    }
    // 2) 去掉 "标题(n)" 后缀匹配父章节（关闭拆分时子章节 → 原章节）
    final parentTitle = oldTitle.replaceFirst(RegExp(r'\(\d+\)$'), '');
    if (parentTitle != oldTitle) {
      for (var i = 0; i < newChapters.length; i++) {
        if (newChapters[i].title == parentTitle) return i;
      }
    }
    return 0;
  }

  /// 从TXT内容提取书籍信息
  Map<String, String?> extractBookInfo(String content, String fileName) {
    final lines = const LineSplitter().convert(content);
    String? name = fileName.replaceAll('.txt', '').replaceAll('.TXT', '');
    String? author;
    String? intro;

    // 尝试从前几行提取书名和作者
    for (var i = 0; i < lines.length && i < 20; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      // 匹配 "书名 作者" 格式
      final authorMatch = RegExp(r'[《【](.+?)[》】]\s*作者[：:]\s*(.+)').firstMatch(line);
      if (authorMatch != null) {
        name = authorMatch.group(1);
        author = authorMatch.group(2);
        break;
      }

      // 匹配 "作者：xxx"
      if (line.startsWith('作者') || line.startsWith('作 者')) {
        author = line.replaceAll(RegExp(r'^作\s*者[：:\s]*'), '').trim();
      }
    }

    // 简介：取正文前几段
    final contentLines = lines.where((l) => l.trim().isNotEmpty).toList();
    if (contentLines.length > 2) {
      intro = contentLines.sublist(0, contentLines.length > 5 ? 5 : contentLines.length).join('\n');
      if (intro.length > 200) intro = intro.substring(0, 200) + '...';
    }

    return {
      'name': name,
      'author': author,
      'intro': intro,
    };
  }
}
