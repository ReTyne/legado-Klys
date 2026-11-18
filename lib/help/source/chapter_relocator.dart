import 'package:legado_md3/help/source/js_text_utils.dart';

/// 目录刷新 / 换源后，把「旧目录里的当前章节」重新定位到新目录的章节下标。
///
/// 纯 Dart 实现，不依赖 Flutter / 数据库。匹配按优先级：
/// ① 比例映射得到候选位；② 候选位 ±10 邻域内标题归一化后的 Jaccard 相似度；
/// ③ 章节号数值相等；④ 越界钳制到合法区间。
const String _numChars =
    '0-9〇零一二三四五六七八九壹贰叁肆伍陆柒捌玖十百千万亿拾佰仟两';

/// 读取章节对象的标题：`BookChapter.title` 或 `Map['title']`。
String chapterTitleOf(dynamic chapter) {
  if (chapter == null) return '';
  if (chapter is Map) return (chapter['title'] ?? '').toString();
  try {
    return (chapter.title ?? '').toString();
  } catch (_) {
    return '';
  }
}

/// 把「第X章 / 第X节 / 第X卷」中的数字统一成阿拉伯数字，便于跨格式比较。
int? _numberValue(String raw) {
  final arabic = int.tryParse(raw);
  if (arabic != null) return arabic;
  final chinese = JsTextUtils.chineseNumToInt(raw);
  return chinese >= 0 ? chinese : null;
}

/// 标题归一化：全角转半角、去空白、章节号转阿拉伯数字，其余标点剔除，
/// 只保留中日韩文字、数字与字母。
String normalizeChapterTitle(String title) {
  var s = JsTextUtils.fullToHalf(title).replaceAll(RegExp(r'\s+'), '');
  s = s.replaceAllMapped(
    RegExp('第([$_numChars]+)([章节卷])'),
    (m) {
      final n = _numberValue(m.group(1)!);
      return n == null ? m.group(0)! : '第$n${m.group(2)}';
    },
  );
  final keep = RegExp(r'[\u4e00-\u9fffA-Za-z0-9]');
  final buf = StringBuffer();
  for (final r in s.runes) {
    final c = String.fromCharCode(r);
    if (keep.hasMatch(c)) buf.write(c);
  }
  return buf.toString();
}

/// 从标题中提取章节号：优先「第X章 / 第X节」，其次「第X卷」，
/// 再退回首段阿拉伯数字或中文数字。提取不到返回 null。
int? extractChapterNumber(String title) {
  final half = JsTextUtils.fullToHalf(title);
  for (final pattern in <String>[
    '第\\s*([$_numChars]+)\\s*[章节]',
    '第\\s*([$_numChars]+)\\s*卷',
  ]) {
    final m = RegExp(pattern).firstMatch(half);
    if (m != null) {
      final n = _numberValue(m.group(1)!);
      if (n != null) return n;
    }
  }
  final digits = RegExp(r'\d+').firstMatch(half);
  if (digits != null) return int.tryParse(digits.group(0)!);
  final chinese = RegExp('[$_numChars]+').firstMatch(half);
  if (chinese != null) return _numberValue(chinese.group(0)!);
  return null;
}

/// 中文标题字符的 bigram 集合（按 rune 切分，兼容增补汉字）。
Set<String> _bigrams(String normalized) {
  final chars = normalized.runes.map(String.fromCharCode).toList();
  final set = <String>{};
  if (chars.length == 1) {
    set.add(chars[0]);
    return set;
  }
  for (var i = 0; i < chars.length - 1; i++) {
    set.add(chars[i] + chars[i + 1]);
  }
  return set;
}

double _jaccard(Set<String> a, Set<String> b) {
  if (a.isEmpty && b.isEmpty) return 1.0;
  if (a.isEmpty || b.isEmpty) return 0.0;
  return a.intersection(b).length / a.union(b).length;
}

/// 归一化后两标题的 Jaccard 相似度（0.0 ~ 1.0）。
double chapterTitleJaccard(String a, String b) =>
    _jaccard(_bigrams(normalizeChapterTitle(a)),
        _bigrams(normalizeChapterTitle(b)));

/// 智能重定位当前章节。
///
/// [oldIndex] 旧目录中的阅读下标，[oldTitle] 旧目录当前章标题，
/// [newChapters] 新目录章节列表（元素含 `title` 字段），
/// [oldSize] 旧目录长度（<=0 时直接用 [oldIndex] 作候选位）。
/// 新目录为空返回 -1；其余情况返回一个 0..newLen-1 的合法下标。
int getDurChapter(
  int oldIndex,
  String oldTitle,
  List<dynamic> newChapters,
  int oldSize,
) {
  final newLen = newChapters.length;
  if (newLen <= 0) return -1;

  // ① 比例映射候选位：旧目录变长/变短时按比例缩放下标。
  final approx = oldSize <= 0
      ? oldIndex
      : (oldIndex * newLen / oldSize).round();

  // ② 候选位 ±10 邻域内取归一化标题 Jaccard 最大的一项，>=0.96 才命中。
  final oldNorm = normalizeChapterTitle(oldTitle);
  if (oldNorm.isNotEmpty) {
    var bestIndex = -1;
    var bestScore = 0.0;
    final from = approx - 10 < 0 ? 0 : approx - 10;
    final to = approx + 10 >= newLen ? newLen - 1 : approx + 10;
    for (var i = from; i <= to; i++) {
      final score = _jaccard(
          _bigrams(oldNorm), _bigrams(normalizeChapterTitle(chapterTitleOf(newChapters[i]))));
      if (score > bestScore) {
        bestScore = score;
        bestIndex = i;
      }
    }
    if (bestIndex >= 0 && bestScore >= 0.96) return bestIndex;
  }

  // ③ 标题格式差异较大时，用章节号相等做全目录匹配。
  final oldNum = extractChapterNumber(oldTitle);
  if (oldNum != null) {
    var bestIndex = -1;
    var bestDiff = 1 << 30;
    for (var i = 0; i < newLen; i++) {
      final n = extractChapterNumber(chapterTitleOf(newChapters[i]));
      if (n == null) continue;
      final diff = (n - oldNum).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        bestIndex = i;
      }
    }
    if (bestIndex >= 0 && bestDiff < 1) return bestIndex;
  }

  // ④ 都不命中时退化为按比例映射的候选位，并钳制到合法区间。
  if (approx < 0) return 0;
  if (approx >= newLen) return newLen - 1;
  return approx;
}
