import 'dart:convert';
import 'dart:typed_data';

/// TTF 字体解析器：提取 cmap（Unicode→字形ID）和 post（字形ID→字形名）表
/// 用于字体反爬：某些站点用自定义字体混淆字符，通过 cmap+post 还原真实字符
class TtfParser {
  final ByteData _data;
  TtfParser(this._data);

  /// 从字节数据解析
  factory TtfParser.fromBytes(List<int> bytes) =>
      TtfParser(ByteData.sublistView(Uint8List.fromList(bytes)));

  int get _length => _data.lengthInBytes;

  /// 是否需要读取 [offset] 起的 [count] 个字节。非法字体/非字体数据
  /// （WAF 拦截页、空响应等）会越界，统一在此拦下，让解析安全降级。
  bool _hasBytes(int offset, int count) =>
      offset >= 0 && count >= 0 && offset + count <= _length;

  /// 读取表目录，返回 tag -> (offset, length)
  Map<String, (int, int)> _tableDirectory() {
    final tables = <String, (int, int)>{};
    if (!_hasBytes(4, 2)) return tables;
    final numTables = _data.getUint16(4);
    var offset = 12;
    for (var i = 0; i < numTables; i++) {
      if (!_hasBytes(offset, 16)) break;
      final tag =
          ascii.decode(_data.buffer.asUint8List(offset, 4), allowInvalid: true);
      final tableOffset = _data.getUint32(offset + 8);
      final length = _data.getUint32(offset + 12);
      // 只登记落在数据范围内的表，避免后续解析读越界
      if (_hasBytes(tableOffset, 0) && tableOffset + length <= _length) {
        tables[tag] = (tableOffset, length);
      }
      offset += 16;
    }
    return tables;
  }

  /// 解析 cmap 表，返回 Unicode codePoint -> glyph ID。
  ///
  /// 支持 format 0 / 4 / 6 / 12，并按「多平台子表优先级」逐条填充：
  /// Unicode UCS-4(3,10) > Unicode(0) format12 > Windows BMP(3,1) >
  /// Unicode(0) format4 > 其它 > Macintosh(1)。高优先级子表先写且不被
  /// 低优先级覆盖（用 putIfAbsent），保证同一字符取到最可信的字形 ID。
  Map<int, int> parseCmap() {
    final tables = _tableDirectory();
    final cmapInfo = tables['cmap'];
    if (cmapInfo == null) return {};
    final (offset, _) = cmapInfo;
    if (!_hasBytes(offset + 2, 2)) return {};
    final numTables = _data.getUint16(offset + 2);
    final records = <(int, int, int, int)>[];

    for (var i = 0; i < numTables; i++) {
      final recOffset = offset + 4 + i * 8;
      if (!_hasBytes(recOffset, 8)) break;
      final platformID = _data.getUint16(recOffset);
      final encodingID = _data.getUint16(recOffset + 2);
      final subOffset = offset + _data.getUint32(recOffset + 4);
      if (!_hasBytes(subOffset, 2)) continue;
      final format = _data.getUint16(subOffset);
      records.add((platformID, encodingID, subOffset, format));
    }

    records.sort((a, b) => _cmapPriority(a).compareTo(_cmapPriority(b)));
    final result = <int, int>{};
    for (final r in records) {
      final subOffset = r.$3;
      switch (r.$4) {
        case 0:
          _parseCmapFormat0(subOffset, result);
          break;
        case 4:
          _parseCmapFormat4(subOffset, result);
          break;
        case 6:
          _parseCmapFormat6(subOffset, result);
          break;
        case 12:
          _parseCmapFormat12(subOffset, result);
          break;
      }
    }
    return result;
  }

  /// 数字越小优先级越高：UCS-4 Unicode 子表优先于 BMP 与符号/Mac 子表。
  int _cmapPriority((int, int, int, int) r) {
    final pid = r.$1, eid = r.$2, fmt = r.$4;
    if (pid == 3 && eid == 10) return 0;
    if (pid == 0 && fmt == 12) return 1;
    if (pid == 3 && eid == 1) return 2;
    if (pid == 0 && fmt == 4) return 3;
    if (pid == 0) return 4;
    if (pid == 3) return 5;
    if (pid == 1) return 6;
    return 7;
  }

  /// cmap format 0：byte encoding table，256 字节的 glyphIdArray。
  void _parseCmapFormat0(int subOffset, Map<int, int> result) {
    final base = subOffset + 6; // format(2) length(2) language(2)
    for (var c = 0; c < 256; c++) {
      if (!_hasBytes(base + c, 1)) break;
      final gid = _data.getUint8(base + c);
      if (gid != 0) result.putIfAbsent(c, () => gid);
    }
  }

  /// cmap format 6：trimmed table，firstCode 起 entryCount 个连续字形。
  void _parseCmapFormat6(int subOffset, Map<int, int> result) {
    if (!_hasBytes(subOffset + 10, 2)) return;
    final firstCode = _data.getUint16(subOffset + 6);
    final entryCount = _data.getUint16(subOffset + 8);
    final base = subOffset + 10;
    for (var i = 0; i < entryCount; i++) {
      if (!_hasBytes(base + i * 2, 2)) break;
      final gid = _data.getUint16(base + i * 2);
      if (gid != 0) result.putIfAbsent(firstCode + i, () => gid);
    }
  }

  void _parseCmapFormat4(int subOffset, Map<int, int> result) {
    final segCount = _data.getUint16(subOffset + 6) ~/ 2;
    final endCodesOffset = subOffset + 14;
    final startCodesOffset = endCodesOffset + segCount * 2 + 2;
    final idDeltasOffset = startCodesOffset + segCount * 2;
    final idRangeOffsetsOffset = idDeltasOffset + segCount * 2;

    for (var i = 0; i < segCount; i++) {
      final endCode = _data.getUint16(endCodesOffset + i * 2);
      final startCode = _data.getUint16(startCodesOffset + i * 2);
      final idDelta = _data.getInt16(idDeltasOffset + i * 2);
      final idRangeOffset = _data.getUint16(idRangeOffsetsOffset + i * 2);

      for (var c = startCode; c <= endCode && c != 0xFFFF; c++) {
        int glyphId;
        if (idRangeOffset == 0) {
          glyphId = (c + idDelta) & 0xFFFF;
        } else {
          final glyphIndexOffset = idRangeOffsetsOffset +
              i * 2 +
              idRangeOffset +
              (c - startCode) * 2;
          glyphId = _data.getUint16(glyphIndexOffset);
          if (glyphId != 0) glyphId = (glyphId + idDelta) & 0xFFFF;
        }
        if (glyphId != 0) result.putIfAbsent(c, () => glyphId);
      }
    }
  }

  void _parseCmapFormat12(int subOffset, Map<int, int> result) {
    final numGroups = _data.getUint32(subOffset + 12);
    var groupsOffset = subOffset + 16;
    for (var i = 0; i < numGroups; i++) {
      final startCharCode = _data.getUint32(groupsOffset);
      final endCharCode = _data.getUint32(groupsOffset + 4);
      final startGlyphID = _data.getUint32(groupsOffset + 8);
      for (var c = startCharCode; c <= endCharCode; c++) {
        result.putIfAbsent(c, () => startGlyphID + (c - startCharCode));
      }
      groupsOffset += 12;
    }
  }

  /// 解析 post 表，返回 glyph ID -> 字形名
  Map<int, String> parsePost() {
    final tables = _tableDirectory();
    final postInfo = tables['post'];
    if (postInfo == null) return {};
    final (offset, _) = postInfo;
    final format = _data.getFixed32(offset); // 0x00020000 = format 2
    final result = <int, String>{};

    if (format == 0x00020000) {
      // Format 2
      final numGlyphs = _data.getUint16(offset + 32);
      final glyphNameIndexOffset = offset + 34;
      final namesOffset = glyphNameIndexOffset + numGlyphs * 2;

      // 标准字形名（Macintosh 顺序）
      const standardNames = [
        '.notdef',
        '.null',
        'nonmarkingreturn',
        'space',
        'exclam',
        'quotedbl',
        'numbersign',
        'dollar',
        'percent',
        'ampersand',
        'quotesingle',
        'parenleft',
        'parenright',
        'asterisk',
        'plus',
        'comma',
        'hyphen',
        'period',
        'slash',
        'zero',
        'one',
        'two',
        'three',
        'four',
        'five',
        'six',
        'seven',
        'eight',
        'nine',
        'colon',
        'semicolon',
        'less',
        'equal',
        'greater',
        'question',
        'at',
        'A',
        'B',
        'C',
        'D',
        'E',
        'F',
        'G',
        'H',
        'I',
        'J',
        'K',
        'L',
        'M',
        'N',
        'O',
        'P',
        'Q',
        'R',
        'S',
        'T',
        'U',
        'V',
        'W',
        'X',
        'Y',
        'Z',
        'bracketleft',
        'backslash',
        'bracketright',
        'asciicircum',
        'underscore',
        'grave',
        'a',
        'b',
        'c',
        'd',
        'e',
        'f',
        'g',
        'h',
        'i',
        'j',
        'k',
        'l',
        'm',
        'n',
        'o',
        'p',
        'q',
        'r',
        's',
        't',
        'u',
        'v',
        'w',
        'x',
        'y',
        'z',
        'braceleft',
        'bar',
        'braceright',
        'asciitilde',
        'Adieresis',
        'Aring',
        'Ccedilla',
        'Eacute',
        'Ntilde',
        'Odieresis',
        'Udieresis',
        'aacute',
        'agrave',
        'acircumflex',
        'adieresis',
        'atilde',
        'aring',
        'ccedilla',
        'eacute',
        'egrave',
        'ecircumflex',
        'edieresis',
        'iacute',
        'igrave',
        'icircumflex',
        'idieresis',
        'ntilde',
        'oacute',
        'ograve',
        'ocircumflex',
        'odieresis',
        'otilde',
        'uacute',
        'ugrave',
        'ucircumflex',
        'udieresis',
        'dagger',
        'degree',
        'cent',
        'sterling',
        'section',
        'bullet',
        'paragraph',
        'germandbls',
        'registered',
        'copyright',
        'trademark',
        'acute',
        'dieresis',
        'notequal',
        'AE',
        'Oslash',
        'infinity',
        'plusminus',
        'lessequal',
        'greaterequal',
        'yen',
        'mu',
        'partialdiff',
        'summation',
        'product',
        'pi',
        'integral',
        'ordfeminine',
        'ordmasculine',
        'Omega',
        'ae',
        'oslash',
        'questiondown',
        'exclamdown',
        'logicalnot',
        'radical',
        'florin',
        'approxequal',
        'Delta',
        'guillemotleft',
        'guillemotright',
        'ellipsis',
        'nonbreakingspace',
        'Agrave',
        'Atilde',
        'Otilde',
        'OE',
        'oe',
        'endash',
        'emdash',
        'quotedblleft',
        'quotedblright',
        'quoteleft',
        'quoteright',
        'divide',
        'lozenge',
        'ydieresis',
        'Ydieresis',
        'fraction',
        'currency',
        'guilsinglleft',
        'guilsinglright',
        'fi',
        'fl',
        'daggerdbl',
        'periodcentered',
        'quotesinglbase',
        'quotedblbase',
        'perthousand',
        'Acircumflex',
        'Ecircumflex',
        'Aacute',
        'Edieresis',
        'Egrave',
        'Iacute',
        'Icircumflex',
        'Idieresis',
        'Igrave',
        'Oacute',
        'Ocircumflex',
        'apple',
        'Ograve',
        'Uacute',
        'Ucircumflex',
        'Ugrave',
        'dotlessi',
        'circumflex',
        'tilde',
        'macron',
        'breve',
        'dotaccent',
        'ring',
        'cedilla',
        'hungarumlaut',
        'ogonek',
        'caron',
        'Lslash',
        'lslash',
        'Scaron',
        'scaron',
        'Zcaron',
        'zcaron',
        'brokenbar',
        'Eth',
        'eth',
        'Yacute',
        'yacute',
        'Thorn',
        'thorn',
        'minus',
        'multiply',
        'onesuperior',
        'twosuperior',
        'threesuperior',
        'onehalf',
        'onequarter',
        'threequarters',
        'franc',
        'Gbreve',
        'gbreve',
        'Idotaccent',
        'Scedilla',
        'scedilla',
        'Cacute',
        'cacute',
        'Ccaron',
        'ccaron',
        'dcaron',
        'Dcaron',
        'Ecaron',
        'ecaron',
        'Nacute',
        'nacute',
        'Ncaron',
        'ncaron',
        'Oacute',
        'ocircumflex',
        'Ograve',
        'Racute',
        'racute',
        'Rcaron',
        'rcaron',
        'Abreve',
        'abreve',
        'Acircumflex',
        'acircumflex',
        'Aacute',
        'aacute',
        'Agrave',
        'agrave',
        'Ccedilla',
        'ccedilla',
        'Ecaron',
        'ecaron',
        'Ecircumflex',
        'ecircumflex',
        'Eacute',
        'eacute',
        'Egrave',
        'egrave',
        'Edieresis',
        'edieresis',
        'Iacute',
        'iacute',
        'Icircumflex',
        'icircumflex',
        'Igrave',
        'igrave',
        'Idieresis',
        'idieresis',
        'Ntilde',
        'ntilde',
        'Ocircumflex',
        'ocircumflex',
        'Oacute',
        'oacute',
        'Ograve',
        'ograve',
        'Odieresis',
        'odieresis',
        'Racute',
        'racute',
        'Rcaron',
        'rcaron',
        'Sacute',
        'sacute',
        'Scaron',
        'scaron',
        'Tcaron',
        'tcaron',
        'Uacute',
        'uacute',
        'Ucircumflex',
        'ucircumflex',
        'Ugrave',
        'ugrave',
        'Udieresis',
        'udieresis',
        'Yacute',
        'yacute',
        'dieresis',
        'dotaccent',
        'grave',
        'acute',
        'cedilla',
        'ring',
        'hungarumlaut',
        'ogonek',
        'caron',
        'breve',
        'macron',
        'dotlessi',
        'dotlessj',
        'grave',
        'acute',
        'circumflex',
        'tilde',
        'dieresis',
        'ring',
        'cedilla',
        'ogonek',
        'caron',
        'breve',
        'macron',
        'dotaccent',
      ];

      var nameOffset = namesOffset;
      for (var i = 0; i < numGlyphs; i++) {
        final nameIndex = _data.getUint16(glyphNameIndexOffset + i * 2);
        if (nameIndex < standardNames.length) {
          result[i] = standardNames[nameIndex];
        } else {
          // 自定义名称：读取 Pascal 字符串
          final nameLen = _data.getUint8(nameOffset);
          final name =
              ascii.decode(_data.buffer.asUint8List(nameOffset + 1, nameLen));
          result[i] = name;
          nameOffset += 1 + nameLen;
        }
      }
    }
    return result;
  }

  // ==================== 字形轮廓指纹（loca / glyf / maxp） ====================

  /// head 表的 indexToLocFormat：0=short(uint16*2)，1=long(uint32)。
  /// 缺 head 表时按 short 处理。
  bool _longLocaFormat(Map<String, (int, int)> tables) {
    final head = tables['head'];
    if (head != null && _hasBytes(head.$1 + 50, 2)) {
      return _data.getInt16(head.$1 + 50) == 1;
    }
    return false;
  }

  /// 读 loca 表第 [index] 个字形的起始偏移（相对 glyf 表）。
  int? _locaOffset(int locaOff, int index, bool longFormat) {
    if (longFormat) {
      final o = locaOff + index * 4;
      if (!_hasBytes(o, 4)) return null;
      return _data.getUint32(o);
    }
    final o = locaOff + index * 2;
    if (!_hasBytes(o, 2)) return null;
    return _data.getUint16(o) * 2;
  }

  /// 返回某字形的「轮廓指纹」：
  ///  * 简单字形 → 规范化坐标串（`S:轮廓数;x,y;...`）；
  ///  * 复合字形 → 组件参数串（`C|gid=..,a=..|...`）；
  ///  * 空字形 / 越界 / 缺表 → null。
  ///
  /// 字体反爬常把字符映射到自定义字形而改 cmap/post，轮廓指纹不依赖
  /// 字符编码与字形名，可作为跨字体的稳定比对依据。
  String? glyfFingerprint(int glyphId) {
    try {
      final tables = _tableDirectory();
      final maxp = tables['maxp'];
      final loca = tables['loca'];
      final glyf = tables['glyf'];
      if (maxp == null || loca == null || glyf == null) return null;
      if (!_hasBytes(maxp.$1 + 4, 2)) return null;
      final numGlyphs = _data.getUint16(maxp.$1 + 4);
      if (glyphId < 0 || glyphId >= numGlyphs) return null;

      final longFormat = _longLocaFormat(tables);
      final start = _locaOffset(loca.$1, glyphId, longFormat);
      final end = _locaOffset(loca.$1, glyphId + 1, longFormat);
      if (start == null || end == null || end <= start) return null;

      final gOff = glyf.$1 + start;
      final gLen = end - start;
      if (!_hasBytes(gOff, gLen) || gLen < 10) return null;
      final numberOfContours = _data.getInt16(gOff);
      if (numberOfContours >= 0) {
        return _simpleGlyphFingerprint(gOff, gLen, numberOfContours);
      }
      return _compositeGlyphFingerprint(gOff, gLen);
    } catch (_) {
      return null;
    }
  }

  /// 简单字形：解析 flags 与 x/y 增量坐标，产出坐标串。
  String _simpleGlyphFingerprint(int off, int len, int nContours) {
    final end = off + len;
    var p = off + 10; // numberOfContours(2) + xMin/yMin/xMax/yMax(8)
    final endPts = <int>[];
    for (var i = 0; i < nContours; i++) {
      if (!_hasBytes(p, 2) || p + 2 > end) break;
      endPts.add(_data.getUint16(p));
      p += 2;
    }
    final numPoints = endPts.isEmpty ? 0 : endPts.last + 1;
    if (nContours == 0 || numPoints <= 0 || !_hasBytes(p, 2)) {
      return 'S:$nContours;end=${endPts.join(',')}';
    }
    final instrLen = _data.getUint16(p);
    p += 2 + instrLen;

    // flags（含 REPEAT 展开）
    final flags = <int>[];
    var guard = 0;
    while (flags.length < numPoints &&
        _hasBytes(p, 1) &&
        p < end &&
        guard++ < 4096) {
      final f = _data.getUint8(p);
      p++;
      flags.add(f);
      if (f & 0x08 != 0) {
        if (!_hasBytes(p, 1)) break;
        final repeat = _data.getUint8(p);
        p++;
        for (var j = 0; j < repeat && flags.length < numPoints; j++) {
          flags.add(f);
        }
      }
    }

    // x 坐标增量
    final xs = <int>[];
    var x = 0;
    for (var i = 0; i < numPoints && p <= end; i++) {
      final f = i < flags.length ? flags[i] : 0;
      if (f & 0x02 != 0) {
        if (!_hasBytes(p, 1)) break;
        final dx = _data.getUint8(p);
        p++;
        x += (f & 0x10 != 0) ? dx : -dx;
      } else if (f & 0x10 == 0) {
        if (!_hasBytes(p, 2)) break;
        x += _data.getInt16(p);
        p += 2;
      }
      xs.add(x);
    }
    // y 坐标增量
    final ys = <int>[];
    var y = 0;
    for (var i = 0; i < numPoints && p <= end; i++) {
      final f = i < flags.length ? flags[i] : 0;
      if (f & 0x04 != 0) {
        if (!_hasBytes(p, 1)) break;
        final dy = _data.getUint8(p);
        p++;
        y += (f & 0x20 != 0) ? dy : -dy;
      } else if (f & 0x20 == 0) {
        if (!_hasBytes(p, 2)) break;
        y += _data.getInt16(p);
        p += 2;
      }
      ys.add(y);
    }

    final sb = StringBuffer('S:$nContours');
    for (var i = 0; i < xs.length; i++) {
      sb.write(';${xs[i]},${i < ys.length ? ys[i] : 0}');
    }
    return sb.toString();
  }

  /// 复合字形：解析每个组件的 glyphIndex / args / 变换参数，产出参数串。
  String _compositeGlyphFingerprint(int off, int len) {
    final end = off + len;
    var p = off + 10;
    final sb = StringBuffer('C');
    var guard = 0;
    while (p + 4 <= end && guard++ < 256) {
      if (!_hasBytes(p, 4)) break;
      final flags = _data.getUint16(p);
      p += 2;
      final gid = _data.getUint16(p);
      p += 2;
      int arg1 = 0, arg2 = 0;
      if (flags & 0x0001 != 0) {
        if (!_hasBytes(p, 4)) break;
        arg1 = _data.getInt16(p);
        arg2 = _data.getInt16(p + 2);
        p += 4;
      } else {
        if (!_hasBytes(p, 2)) break;
        arg1 = _data.getInt8(p);
        arg2 = _data.getInt8(p + 1);
        p += 2;
      }
      final parts = <String>['gid=$gid', 'a=$arg1,$arg2'];
      if (flags & 0x0008 != 0) {
        if (_hasBytes(p, 2)) {
          parts.add('s=${_data.getInt16(p)}');
          p += 2;
        }
      } else if (flags & 0x0040 != 0) {
        if (_hasBytes(p, 4)) {
          parts.add('xy=${_data.getInt16(p)},${_data.getInt16(p + 2)}');
          p += 4;
        }
      } else if (flags & 0x0080 != 0) {
        if (_hasBytes(p, 8)) {
          parts.add('m=${_data.getInt16(p)},${_data.getInt16(p + 2)},'
              '${_data.getInt16(p + 4)},${_data.getInt16(p + 6)}');
          p += 8;
        }
      }
      sb.write('|${parts.join(',')}');
      if (flags & 0x0020 == 0) break; // 无 MORE_COMPONENTS
    }
    return sb.toString();
  }

  /// 构建字体查询结构化数据，供书源侧构造带方法的字体对象：
  ///  * replacement    原字符 -> 真实字符（兼容把返回值当替换表使用的书源）
  ///  * unicodeToGlyphId  Unicode -> 字形 ID
  ///  * unicodeToGlyph    Unicode -> 字形指纹
  ///  * glyphToUnicode    字形指纹 -> Unicode（反查，取首次出现）
  ///
  /// [withOutline] 为 false（默认，无参调用）时字形指纹取 post 字形名，
  /// 缺失时回退 `glyf_<id>`；为 true 时改用 glyf 轮廓指纹，取不到再回退
  /// post 名。无参行为保持不变。
  Map<String, dynamic> buildQueryData({bool withOutline = false}) {
    Map<int, int> cmap;
    Map<int, String> post;
    Map<String, String> replacement;
    try {
      cmap = parseCmap();
    } catch (_) {
      cmap = <int, int>{};
    }
    try {
      post = parsePost();
    } catch (_) {
      post = <int, String>{};
    }
    try {
      replacement = buildReplacementMap();
    } catch (_) {
      replacement = <String, String>{};
    }
    final unicodeToGlyphId = <String, String>{};
    final unicodeToGlyph = <String, String>{};
    final glyphToUnicode = <String, String>{};
    cmap.forEach((codePoint, glyphId) {
      final key = codePoint.toString();
      unicodeToGlyphId[key] = glyphId.toString();
      final name = post[glyphId];
      final fallback =
          (name != null && name.isNotEmpty) ? name : 'glyf_$glyphId';
      String glyf = fallback;
      if (withOutline) {
        final fp = glyfFingerprint(glyphId);
        if (fp != null && fp.isNotEmpty) glyf = fp;
      }
      unicodeToGlyph[key] = glyf;
      glyphToUnicode.putIfAbsent(glyf, () => key);
    });
    return <String, dynamic>{
      'replacement': replacement,
      'unicodeToGlyphId': unicodeToGlyphId,
      'unicodeToGlyph': unicodeToGlyph,
      'glyphToUnicode': glyphToUnicode,
    };
  }

  /// 构建字符替换映射：原字符 -> 真实字符
  /// 原理：cmap 告诉我们 原Unicode→字形ID，post 告诉我们 字形ID→字形名，
  /// 字形名通常就是真实字符（如 "A"、"B"、"a"、"b"）
  Map<String, String> buildReplacementMap() {
    final cmap = parseCmap();
    final post = parsePost();
    final map = <String, String>{};
    cmap.forEach((codePoint, glyphId) {
      final glyphName = post[glyphId];
      if (glyphName == null) return;
      // 字形名转真实字符：单字母直接用，其他尝试解析
      String? realChar;
      if (glyphName.length == 1) {
        realChar = glyphName;
      } else if (glyphName == 'space') {
        realChar = ' ';
      } else if (glyphName.startsWith('uni') && glyphName.length == 7) {
        // uniXXXX 格式
        try {
          final code = int.parse(glyphName.substring(3), radix: 16);
          realChar = String.fromCharCode(code);
        } catch (_) {}
      } else if (glyphName.startsWith('u') && glyphName.length >= 5) {
        // uXXXX 格式
        try {
          final code = int.parse(glyphName.substring(1), radix: 16);
          realChar = String.fromCharCode(code);
        } catch (_) {}
      }
      if (realChar != null && realChar.codeUnitAt(0) != codePoint) {
        map[String.fromCharCode(codePoint)] = realChar;
      }
    });
    return map;
  }
}

extension on ByteData {
  int getFixed32(int offset) =>
      (getUint16(offset) << 16) | getUint16(offset + 2);
}
