/// LRC 歌词解析器（对齐 legado 音频播放歌词能力）。
///
/// 支持标准 LRC 格式：
/// ```
/// [00:00.00]第一句
/// [00:15.30]第二句
/// [ti:歌名]
/// [ar:歌手]
/// [offset:500]
/// ```
/// 也支持多时间标签共用一行、毫秒省略（[mm:ss]）等常见变体。
class LrcParser {
  LrcParser._();

  /// 判断文本是否像 LRC 歌词（含 [mm:ss] 时间标签）。
  static bool looksLikeLrc(String? text) {
    if (text == null || text.isEmpty) return false;
    return _timeTag.hasMatch(text);
  }

  /// 解析 LRC 文本为按时间排序的歌词行。
  static List<LrcLine> parse(String lrc) {
    final lines = <LrcLine>[];
    var offset = Duration.zero;
    final offsetRe = RegExp(r'\[offset:\s*(-?\d+)\]', caseSensitive: false);
    final om = offsetRe.firstMatch(lrc);
    if (om != null) {
      offset = Duration(milliseconds: int.tryParse(om.group(1)!) ?? 0);
    }
    for (final raw in lrc.split(RegExp(r'\r?\n'))) {
      final matches = _timeTag.allMatches(raw).toList();
      if (matches.isEmpty) continue;
      final text = raw.substring(matches.last.end).trim();
      for (final m in matches) {
        final min = int.tryParse(m.group(1)!) ?? 0;
        final sec = int.tryParse(m.group(2)!) ?? 0;
        final frac = (m.group(3) ?? '').padRight(3, '0').substring(0, 3);
        final ms = int.tryParse(frac) ?? 0;
        final t = Duration(minutes: min, seconds: sec, milliseconds: ms) + offset;
        if (t.isNegative) continue;
        lines.add(LrcLine(t, text));
      }
    }
    lines.sort((a, b) => a.time.compareTo(b.time));
    return lines;
  }

  /// 根据播放位置返回当前歌词行下标（无匹配返回 -1）。
  static int indexAt(List<LrcLine> lines, Duration position) {
    var idx = -1;
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].time <= position) {
        idx = i;
      } else {
        break;
      }
    }
    return idx;
  }

  static final RegExp _timeTag = RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');
}

class LrcLine {
  LrcLine(this.time, this.text);
  final Duration time;
  final String text;
}
