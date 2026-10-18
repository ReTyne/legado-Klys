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

  /// 读取表目录，返回 tag -> (offset, length)
  Map<String, (int, int)> _tableDirectory() {
    final numTables = _data.getUint16(4);
    final tables = <String, (int, int)>{};
    var offset = 12;
    for (var i = 0; i < numTables; i++) {
      final tag = ascii.decode(_data.buffer.asUint8List(offset, 4));
      final tableOffset = _data.getUint32(offset + 8);
      final length = _data.getUint32(offset + 12);
      tables[tag] = (tableOffset, length);
      offset += 16;
    }
    return tables;
  }

  /// 解析 cmap 表，返回 Unicode codePoint -> glyph ID
  Map<int, int> parseCmap() {
    final tables = _tableDirectory();
    final cmapInfo = tables['cmap'];
    if (cmapInfo == null) return {};
    final (offset, _) = cmapInfo;
    final numTables = _data.getUint16(offset + 2);
    final result = <int, int>{};

    for (var i = 0; i < numTables; i++) {
      final recOffset = offset + 4 + i * 8;
      final platformID = _data.getUint16(recOffset);
      final subOffset = offset + _data.getUint32(recOffset + 4);
      final format = _data.getUint16(subOffset);

      // 只处理 Unicode 平台 (platformID=3) 或 全平台 (0)
      if (platformID != 0 && platformID != 3) continue;

      if (format == 4) {
        _parseCmapFormat4(subOffset, result);
      } else if (format == 12) {
        _parseCmapFormat12(subOffset, result);
      }
    }
    return result;
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
          final glyphIndexOffset =
              idRangeOffsetsOffset + i * 2 + idRangeOffset + (c - startCode) * 2;
          glyphId = _data.getUint16(glyphIndexOffset);
          if (glyphId != 0) glyphId = (glyphId + idDelta) & 0xFFFF;
        }
        if (glyphId != 0) result[c] = glyphId;
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
        result[c] = startGlyphID + (c - startCharCode);
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
        '.notdef', '.null', 'nonmarkingreturn', 'space', 'exclam', 'quotedbl',
        'numbersign', 'dollar', 'percent', 'ampersand', 'quotesingle',
        'parenleft', 'parenright', 'asterisk', 'plus', 'comma', 'hyphen',
        'period', 'slash', 'zero', 'one', 'two', 'three', 'four', 'five',
        'six', 'seven', 'eight', 'nine', 'colon', 'semicolon', 'less',
        'equal', 'greater', 'question', 'at', 'A', 'B', 'C', 'D', 'E', 'F',
        'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S',
        'T', 'U', 'V', 'W', 'X', 'Y', 'Z', 'bracketleft', 'backslash',
        'bracketright', 'asciicircum', 'underscore', 'grave', 'a', 'b', 'c',
        'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p',
        'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', 'braceleft',
        'bar', 'braceright', 'asciitilde', 'Adieresis', 'Aring', 'Ccedilla',
        'Eacute', 'Ntilde', 'Odieresis', 'Udieresis', 'aacute', 'agrave',
        'acircumflex', 'adieresis', 'atilde', 'aring', 'ccedilla', 'eacute',
        'egrave', 'ecircumflex', 'edieresis', 'iacute', 'igrave',
        'icircumflex', 'idieresis', 'ntilde', 'oacute', 'ograve',
        'ocircumflex', 'odieresis', 'otilde', 'uacute', 'ugrave',
        'ucircumflex', 'udieresis', 'dagger', 'degree', 'cent', 'sterling',
        'section', 'bullet', 'paragraph', 'germandbls', 'registered',
        'copyright', 'trademark', 'acute', 'dieresis', 'notequal', 'AE',
        'Oslash', 'infinity', 'plusminus', 'lessequal', 'greaterequal',
        'yen', 'mu', 'partialdiff', 'summation', 'product', 'pi',
        'integral', 'ordfeminine', 'ordmasculine', 'Omega', 'ae', 'oslash',
        'questiondown', 'exclamdown', 'logicalnot', 'radical', 'florin',
        'approxequal', 'Delta', 'guillemotleft', 'guillemotright',
        'ellipsis', 'nonbreakingspace', 'Agrave', 'Atilde', 'Otilde',
        'OE', 'oe', 'endash', 'emdash', 'quotedblleft', 'quotedblright',
        'quoteleft', 'quoteright', 'divide', 'lozenge', 'ydieresis',
        'Ydieresis', 'fraction', 'currency', 'guilsinglleft',
        'guilsinglright', 'fi', 'fl', 'daggerdbl', 'periodcentered',
        'quotesinglbase', 'quotedblbase', 'perthousand', 'Acircumflex',
        'Ecircumflex', 'Aacute', 'Edieresis', 'Egrave', 'Iacute',
        'Icircumflex', 'Idieresis', 'Igrave', 'Oacute', 'Ocircumflex',
        'apple', 'Ograve', 'Uacute', 'Ucircumflex', 'Ugrave', 'dotlessi',
        'circumflex', 'tilde', 'macron', 'breve', 'dotaccent', 'ring',
        'cedilla', 'hungarumlaut', 'ogonek', 'caron', 'Lslash', 'lslash',
        'Scaron', 'scaron', 'Zcaron', 'zcaron', 'brokenbar', 'Eth', 'eth',
        'Yacute', 'yacute', 'Thorn', 'thorn', 'minus', 'multiply',
        'onesuperior', 'twosuperior', 'threesuperior', 'onehalf',
        'onequarter', 'threequarters', 'franc', 'Gbreve', 'gbreve',
        'Idotaccent', 'Scedilla', 'scedilla', 'Cacute', 'cacute',
        'Ccaron', 'ccaron', 'dcaron', 'Dcaron', 'Ecaron', 'ecaron',
        'Nacute', 'nacute', 'Ncaron', 'ncaron', 'Oacute', 'ocircumflex',
        'Ograve', 'Racute', 'racute', 'Rcaron', 'rcaron', 'Abreve',
        'abreve', 'Acircumflex', 'acircumflex', 'Aacute', 'aacute',
        'Agrave', 'agrave', 'Ccedilla', 'ccedilla', 'Ecaron', 'ecaron',
        'Ecircumflex', 'ecircumflex', 'Eacute', 'eacute', 'Egrave',
        'egrave', 'Edieresis', 'edieresis', 'Iacute', 'iacute',
        'Icircumflex', 'icircumflex', 'Igrave', 'igrave', 'Idieresis',
        'idieresis', 'Ntilde', 'ntilde', 'Ocircumflex', 'ocircumflex',
        'Oacute', 'oacute', 'Ograve', 'ograve', 'Odieresis', 'odieresis',
        'Racute', 'racute', 'Rcaron', 'rcaron', 'Sacute', 'sacute',
        'Scaron', 'scaron', 'Tcaron', 'tcaron', 'Uacute', 'uacute',
        'Ucircumflex', 'ucircumflex', 'Ugrave', 'ugrave', 'Udieresis',
        'udieresis', 'Yacute', 'yacute', 'dieresis', 'dotaccent',
        'grave', 'acute', 'cedilla', 'ring', 'hungarumlaut', 'ogonek',
        'caron', 'breve', 'macron', 'dotlessi', 'dotlessj', 'grave',
        'acute', 'circumflex', 'tilde', 'dieresis', 'ring', 'cedilla',
        'ogonek', 'caron', 'breve', 'macron', 'dotaccent',
      ];

      var nameOffset = namesOffset;
      for (var i = 0; i < numGlyphs; i++) {
        final nameIndex = _data.getUint16(glyphNameIndexOffset + i * 2);
        if (nameIndex < standardNames.length) {
          result[i] = standardNames[nameIndex];
        } else {
          // 自定义名称：读取 Pascal 字符串
          final nameLen = _data.getUint8(nameOffset);
          final name = ascii.decode(
              _data.buffer.asUint8List(nameOffset + 1, nameLen));
          result[i] = name;
          nameOffset += 1 + nameLen;
        }
      }
    }
    return result;
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
