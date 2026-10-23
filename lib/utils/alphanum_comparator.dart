/// 自然排序比较器（对齐 legado-E utils/AlphanumComparator.kt）。
///
/// 把字符串按「数字块 / 非数字块」交替切分后比较：数字块按数值比较，
/// 因此 "file2" < "file10"（字典序会得到相反结果）。
///
/// 用途：书架排序、本地文件管理（TXT/EPUB 列表按文件名）等场景。
/// 目前先提供工具能力，调用点由后续书架/文件管理排序接入：
///   list.sort(AlphanumComparator.compare)
///   list.sort((a, b) => AlphanumComparator.naturalCompare(a, b))
///   AlphanumComparator.naturalSorted(list)
library;

import 'dart:collection';

/// 与 legado-E AlphanumComparator 等价的 Comparator<String>。
class AlphanumComparator {
  const AlphanumComparator._();

  /// 单例（Comparator 用法）。
  static const AlphanumComparator instance = AlphanumComparator._();

  /// Comparator 风格比较：负数表示 a 在 b 前。
  static int compare(String s1, String s2) {
    var thisMarker = 0;
    var thatMarker = 0;
    final s1Length = s1.length;
    final s2Length = s2.length;

    while (thisMarker < s1Length && thatMarker < s2Length) {
      final thisChunk = _getChunk(s1, s1Length, thisMarker);
      thisMarker += thisChunk.length;

      final thatChunk = _getChunk(s2, s2Length, thatMarker);
      thatMarker += thatChunk.length;

      // 两个块都是数字时按数值比较
      var result = 0;
      if (_isDigit(thisChunk[0]) && _isDigit(thatChunk[0])) {
        // 先按块长度比（去掉前导零的影响：更长的数字串数值更大）
        final thisChunkLength = thisChunk.length;
        result = thisChunkLength - thatChunk.length;
        // 长度相等时逐字符比较
        if (result == 0) {
          for (var i = 0; i < thisChunkLength; i++) {
            result = thisChunk[i].codeUnitAt(0) - thatChunk.codeUnitAt(0);
            if (result != 0) return result;
          }
        }
      } else {
        result = thisChunk.compareTo(thatChunk);
      }

      if (result != 0) return result;
    }

    return s1Length - s2Length;
  }

  /// 便捷函数：naturalCompare(a, b)。
  static int naturalCompare(String a, String b) => compare(a, b);

  /// 返回按自然序排列的新列表（不改动入参）。
  static List<String> naturalSorted(Iterable<String> items) {
    final list = List<String>.from(items);
    list.sort(compare);
    return list;
  }

  /// 从 marker 处切出一个块：全数字块或全非数字块。
  static String _getChunk(String string, int length, int marker) {
    var current = marker;
    final sb = StringBuffer();
    var c = string[current];
    sb.write(c);
    current++;
    if (_isDigit(c)) {
      while (current < length) {
        c = string[current];
        if (!_isDigit(c)) break;
        sb.write(c);
        current++;
      }
    } else {
      while (current < length) {
        c = string[current];
        if (_isDigit(c)) break;
        sb.write(c);
        current++;
      }
    }
    return sb.toString();
  }

  static bool _isDigit(String ch) => ch.codeUnitAt(0) ^ 0x30 <= 9;

  /// 供 HashSet/HashMap 场景的排序集合（插入即保序）。
  static LinkedHashSet<String> naturalSet(Iterable<String> items) {
    final set = LinkedHashSet<String>(equals: (a, b) => a == b, hashCode: (s) => s.hashCode);
    final sorted = naturalSorted(items);
    for (final s in sorted) {
      set.add(s);
    }
    return set;
  }
}
