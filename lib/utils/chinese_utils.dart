/// 简繁词组转换工具。
///
/// 与 lib/help/readaloud/chinese_converter.dart 的单字表不同，本文件实现
/// **词组优先（最长匹配）+ 单字兜底** 的两级转换：
///   * 词组表：约 1800 组常用繁简/两岸词汇对（臺灣/台湾、資訊/信息、
///     網路/网络、電腦/计算机、滑鼠/鼠标、軟體/软件、行動電話/移动电话……）
///   * 单字表：复用阅读模块的常用繁简单字对照（兜底）
///
/// 提供 t2s / s2t / containsT / containsS，并导出 [jsBridgeSnippet]
/// 供 legado_bridge_js.dart 注入到 WebView（java.t2s / java.s2t 升级为词组级）。
library;

import 'dart:convert';
import 'data/chinese_char_pair_data.dart';
import 'data/chinese_phrase_data.dart';

/// 简繁词组转换。
class ChineseUtils {
  ChineseUtils._();

  /// 词组对数据（紧凑格式 "繁体:简体"）。
  static const List<String> _phraseData = kChinesePhraseData;

  /// 常用繁简单字对照（与 chinese_converter.dart 保持一致的子集）。
  static const String _charPairData = kChineseCharPairData;

  static final Map<String, String> _t2sPhrase = _buildPhraseMap(true);
  static final Map<String, String> _s2tPhrase = _buildPhraseMap(false);
  static final Map<String, String> _t2sChar = _buildCharMap(true);
  static final Map<String, String> _s2tChar = _buildCharMap(false);

  /// 最长词组长度（用于匹配时限定回视窗口）。
  static final int maxPhraseLen =
      _phraseData.fold(0, (m, p) => m > p.split(':')[0].length ? m : p.split(':')[0].length);

  static Map<String, String> _buildPhraseMap(bool tradToSimp) {
    final m = <String, String>{};
    for (final pair in _phraseData) {
      final idx = pair.indexOf(':');
      if (idx <= 0) continue;
      final t = pair.substring(0, idx);
      final s = pair.substring(idx + 1);
      if (tradToSimp) {
        m.putIfAbsent(t, () => s);
      } else {
        m.putIfAbsent(s, () => t);
      }
    }
    return m;
  }

  static Map<String, String> _buildCharMap(bool tradToSimp) {
    final m = <String, String>{};
    for (var i = 0; i + 1 < _charPairData.length; i += 2) {
      final t = _charPairData[i];
      final s = _charPairData[i + 1];
      if (tradToSimp) {
        m[t] = s;
      } else {
        m.putIfAbsent(s, () => t);
      }
    }
    return m;
  }

  /// 繁体 → 简体（词组优先，单字兜底）。
  static String t2s(String text) => _convert(text, _t2sPhrase, _t2sChar);

  /// 简体 → 繁体（词组优先，单字兜底）。
  static String s2t(String text) => _convert(text, _s2tPhrase, _s2tChar);

  /// 是否包含繁体特征字。
  static bool containsT(String text) {
    for (final ch in text.split('')) {
      if (_t2sChar.containsKey(ch)) return true;
    }
    return false;
  }

  /// 是否包含简体特征字。
  static bool containsS(String text) {
    for (final ch in text.split('')) {
      if (_s2tChar.containsKey(ch)) return true;
    }
    return false;
  }

  /// 词组优先最长匹配转换。
  static String _convert(
      String text, Map<String, String> phrases, Map<String, String> chars) {
    if (text.isEmpty) return text;
    final sb = StringBuffer();
    var i = 0;
    final n = text.length;
    while (i < n) {
      var matched = false;
      final limit = (i + maxPhraseLen <= n) ? maxPhraseLen : n - i;
      for (var len = limit; len >= 2; len--) {
        final key = text.substring(i, i + len);
        final v = phrases[key];
        if (v != null) {
          sb.write(v);
          i += len;
          matched = true;
          break;
        }
      }
      if (!matched) {
        final ch = text[i];
        sb.write(chars[ch] ?? ch);
        i++;
      }
    }
    return sb.toString();
  }

  // ------------------------------------------------------------------
  // JS 桥注入：把词组表与最长匹配函数注入 WebView（java.t2s / java.s2t 使用）
  // ------------------------------------------------------------------

  static String? _jsSnippetCache;

  /// 生成 JS 桥片段（繁/简词组表 + 最长匹配转换函数）。
  static String get jsBridgeSnippet => _jsSnippetCache ??= _buildJsSnippet();

  static String _buildJsSnippet() {
    String arr(Map<String, String> m) => m.entries
        .map((e) => '[${jsonEncode(e.key)},${jsonEncode(e.value)}]')
        .join(',');
    return '''
  // ---- 简繁词组转换（词组优先最长匹配 + 单字兜底，数据由 ChineseUtils 生成）----
  var __T2S_PHRASES = [${arr(_t2sPhrase)}];
  var __S2T_PHRASES = [${arr(_s2tPhrase)}];
  var __T2S_CHARS = ${jsonEncode(_t2sChar)};
  var __S2T_CHARS = ${jsonEncode(_s2tChar)};
  function __phraseConvert(text, phrases, chars) {
    var s = String(text == null ? "" : text);
    if (!s) return s;
    var maxLen = 1;
    for (var i = 0; i < phrases.length; i++) {
      if (phrases[i][0].length > maxLen) maxLen = phrases[i][0].length;
    }
    var map = {};
    for (var i = 0; i < phrases.length; i++) map[phrases[i][0]] = phrases[i][1];
    var out = "";
    var idx = 0, n = s.length;
    while (idx < n) {
      var matched = false;
      var limit = (idx + maxLen <= n) ? maxLen : n - idx;
      for (var len = limit; len >= 2; len--) {
        var key = s.substr(idx, len);
        if (map[key] !== undefined) {
          out += map[key];
          idx += len;
          matched = true;
          break;
        }
      }
      if (!matched) {
        var ch = s.charAt(idx);
        var mapped = chars[ch];
        out += (mapped !== undefined) ? mapped : ch;
        idx++;
      }
    }
    return out;
  }
''';
  }
}
