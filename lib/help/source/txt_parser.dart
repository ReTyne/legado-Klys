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

  /// 解析TXT内容为章节列表
  List<BookChapter> parseChapters(String content, {TxtTocRule? rule}) {
    final chapters = <BookChapter>[];
    final lines = const LineSplitter().convert(content);

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
      ));
    }

    // 如果没有找到章节，将整个内容作为一章
    if (chapters.isEmpty) {
      chapters.add(BookChapter(
        index: 0,
        title: '正文',
        url: 'local://chapter/0',
        content: content.trim(),
      ));
    }

    return chapters;
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
