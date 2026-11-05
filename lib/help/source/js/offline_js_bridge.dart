import 'dart:convert';

import 'js_source.dart';

/// 纯 Dart 实现的 legado JS 桥 API 子集（离线可测，不依赖 WebView / 网络 / 平台通道）。
///
/// 用途：把「两个真实聚合源（7632 / 7814）重度依赖、且可纯 Dart 实现」的桥 API
/// 做成真实实现，供 `test/real_source_compat_test.dart` 在无 WebView 的单测里断言。
/// 与 `legado_bridge_js.dart`（注入 WebView 的 JS 桥）语义对齐：
///   * java.base64Encode / base64Decode / base64DecodeToByteArray
///   * java.getWebViewUA、java.timeFormat
///   * cache.put/get/putMemory/getFromMemory
///   * cookie.getCookie/setCookie/removeCookie/getKey
///   * source.getVariable/setVariable/getLoginInfo/putLoginInfo/getLoginInfoMap/getKey/getLoginHeader
///   * java.createSymmetricCrypto（AES / DES，ECB / CBC，PKCS5 / PKCS7）
///
/// 平台边界（不在此假实现）：java.ajax / startBrowserAwait / searchBook /
/// refreshExplore、Packages.*、java.deviceID（iOS 专属）依赖 Android 原生、
/// Rhino Java 互操作或可见 WebView，仍由 WebView 桥 + 原生通道承担。

/// 对齐 java.base64Encode / base64Decode / base64DecodeToByteArray 的真实编解码。
class JsBridgeCodec {
  JsBridgeCodec._();

  /// base64 编码（对齐 __b64Unicode：先取 UTF-8 字节）。
  static String base64Encode(String text) => base64.encode(utf8.encode(text));

  /// base64 解码为 UTF-8 字符串（解码失败返回空串，对齐桥的 try/catch 兜底）。
  static String base64Decode(String text) {
    try {
      return utf8.decode(base64.decode(_clean(text)));
    } catch (_) {
      return '';
    }
  }

  /// 对齐 java.base64DecodeToByteArray：返回字节数组，供 createSymmetricCrypto 解密。
  static List<int> base64DecodeToByteArray(String text) {
    try {
      return base64.decode(_clean(text));
    } catch (_) {
      return <int>[];
    }
  }

  /// 字节数组 -> base64（对齐 encryptBase64）。
  static String bytesToBase64(List<int> bytes) => base64.encode(bytes);

  /// 字节数组 -> 小写 hex（对齐 encryptHex）。
  static String bytesToHex(List<int> bytes) =>
      bytes.map((b) => (b & 0xff).toRadixString(16).padLeft(2, '0')).join();

  /// hex 字符串 -> 字节数组（对齐 __hexToBytes）。
  static List<int> hexToBytes(String hex) {
    final h = hex.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    final out = <int>[];
    for (var i = 0; i + 1 < h.length; i += 2) {
      out.add(int.parse(h.substring(i, i + 2), radix: 16));
    }
    return out;
  }

  static String _clean(String s) => s.replaceAll(RegExp(r'\s'), '');
}

/// 对齐 java.getWebViewUA：无 WebView 时的默认 UA（与桥 __state.ua 默认值一致）。
class JsBridgeEnv {
  JsBridgeEnv._();

  static const String webViewUA =
      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/120.0.0.0 Mobile Safari/537.36';
}

/// 对齐 java.timeFormat / timeFormatUTC（桥侧 __timeFormat 的 yyyy/MM/dd/HH/mm/ss）。
class JsBridgeTime {
  JsBridgeTime._();

  /// [time] 可为秒/毫秒时间戳或日期字符串；[pattern] 默认 yyyy-MM-dd HH:mm:ss。
  static String timeFormat(Object? time,
      [String pattern = 'yyyy-MM-dd HH:mm:ss', bool utc = false]) {
    if (time == null) return '';
    DateTime? d;
    if (time is int) {
      d = DateTime.fromMillisecondsSinceEpoch(_ms(time), isUtc: utc);
    } else {
      final s = time.toString();
      if (RegExp(r'^\d+$').hasMatch(s)) {
        d = DateTime.fromMillisecondsSinceEpoch(_ms(int.parse(s)), isUtc: utc);
      } else {
        d = DateTime.tryParse(s.replaceAll('-', '/'));
        if (d != null && utc) d = d.toUtc();
      }
    }
    if (d == null) return '';
    if (!utc) d = d.toLocal();
    String p2(int n) => n.toString().padLeft(2, '0');
    return pattern
        .replaceAll('yyyy', d.year.toString())
        .replaceAll('yy', d.year.toString().substring(2))
        .replaceAll('MM', p2(d.month))
        .replaceAll('dd', p2(d.day))
        .replaceAll('HH', p2(d.hour))
        .replaceAll('mm', p2(d.minute))
        .replaceAll('ss', p2(d.second));
  }

  static int _ms(int n) => n < 1000000000000 ? n * 1000 : n;
}

/// 对齐 cache 对象：put/get 为可回写态，putMemory/getFromMemory 为纯内存态。
class JsBridgeCache {
  final Map<String, String> _disk = <String, String>{};
  final Map<String, dynamic> _memory = <String, dynamic>{};

  /// 存入持久化态（非字符串按 JSON 序列化，对齐桥 cache.put）。
  bool put(String key, Object? value) {
    _disk[key] = value is String ? value : jsonEncode(value);
    return true;
  }

  /// 读取持久化态（能解析成 JSON 则还原对象，对齐桥 cache.get）。
  Object? get(String key) {
    final v = _disk[key];
    if (v == null) return null;
    try {
      return jsonDecode(v);
    } catch (_) {
      return v;
    }
  }

  bool contains(String key) => _disk.containsKey(key);
  void remove(String key) => _disk.remove(key);

  /// 内存态写入：不落盘、不参与 __envelope 回写（对齐 legado putMemory）。
  bool putMemory(String key, Object? value) {
    _memory[key] = value;
    return true;
  }

  /// 内存态读取：仅命中本进程内存，缺省返回 null（对齐 legado getFromMemory）。
  Object? getFromMemory(String key) => _memory[key];
  void removeMemory(String key) => _memory.remove(key);

  /// 持久化态快照（供运行时回写 SharedPreferences，对齐 __state.kv）。
  Map<String, String> get diskSnapshot => Map<String, String>.unmodifiable(_disk);
}

/// 对齐 cookie 对象：按 host 归并 Cookie，支持 getKey(url, name) 取单值。
class JsBridgeCookie {
  final Map<String, String> _jar = <String, String>{};

  /// 合并写入 Cookie（同 host 同名覆盖，对齐桥 __ingestSetCookie）。
  void setCookie(String url, String cookieStr) {
    final host = _hostOf(url);
    final jar = _pairs(_jar[host] ?? '');
    jar.addAll(_pairs(cookieStr));
    _jar[host] = jar.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  /// 读取 host（含子域匹配）的完整 Cookie 串。
  String getCookie(String url) => _jar[_matchHost(_hostOf(url))] ?? '';

  /// 删除某 host 的 Cookie。
  void removeCookie(String url) => _jar.remove(_matchHost(_hostOf(url)));

  /// 取 Cookie 中指定 name 的值（对齐桥 cookie.getKey 的正则语义）。
  String getKey(String url, String name) {
    final c = getCookie(url);
    final m = RegExp('(?:^|;\\s*)${RegExp.escape(name)}=([^;]*)').firstMatch(c);
    return m?.group(1) ?? '';
  }

  String _matchHost(String host) {
    if (host.isEmpty) return '';
    if (_jar.containsKey(host)) return host;
    for (final k in _jar.keys) {
      if (host == k || host.endsWith('.$k') || k.endsWith('.$host')) return k;
    }
    return '';
  }

  static Map<String, String> _pairs(String str) {
    final out = <String, String>{};
    for (final part in str.split(RegExp(r'[;\n]'))) {
      final p = part.trim();
      final idx = p.indexOf('=');
      if (idx <= 0) continue;
      final name = p.substring(0, idx).trim();
      if (RegExp(r'^(path|domain|expires|max-age|secure|httponly|samesite)$',
              caseSensitive: false)
          .hasMatch(name)) {
        continue;
      }
      out[name] = p.substring(idx + 1).trim();
    }
    return out;
  }

  static String _hostOf(String url) {
    final s = url.trim();
    if (RegExp(r'^https?://', caseSensitive: false).hasMatch(s)) {
      return Uri.tryParse(s)?.host ?? s;
    }
    final first = s.replaceFirst(RegExp(r'^https?://', caseSensitive: false), '').split('/').first;
    return first.replaceFirst(RegExp(r':\d+$'), '');
  }
}

/// 对齐 source 对象的登录头 / 变量 / 登录信息管理。
class JsBridgeSource {
  JsBridgeSource({required this.url, this.variable = ''});

  final String url;
  String variable;
  String loginInfo = '';
  String loginHeader = '';

  /// 书源地址（对齐 source.getKey / 全局 getKey）。
  String getKey() => url;

  /// 无 key 返回整份变量；有 key 时按 JSON 对象取值（对齐桥 source.getVariable）。
  String getVariable([String? key]) {
    if (key == null || key.isEmpty) return variable;
    try {
      final o = jsonDecode(variable.isEmpty ? '{}' : variable);
      if (o is Map) {
        final v = o[key];
        return v == null ? '' : (v is String ? v : jsonEncode(v));
      }
    } catch (_) {}
    return '';
  }

  /// 写入变量（对象按 JSON 序列化，对齐桥 source.setVariable）。
  String setVariable(Object? v) {
    variable = v is String ? v : jsonEncode(v);
    return variable;
  }

  String getLoginInfo() => loginInfo;

  /// 写入登录信息（对齐桥 source.putLoginInfo）。
  bool putLoginInfo(Object? v) {
    loginInfo = v is String ? v : jsonEncode(v);
    return true;
  }

  /// 登录信息解析为 Map（对齐桥 source.getLoginInfoMap）。
  Map<String, dynamic> getLoginInfoMap() {
    try {
      final o = jsonDecode(loginInfo.isEmpty ? '{}' : loginInfo);
      return o is Map ? Map<String, dynamic>.from(o) : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  String getLoginHeader() => loginHeader;
  bool putLoginHeader(String header) {
    loginHeader = header;
    return true;
  }
}

/// createSymmetricCrypto 返回的加解密句柄（对齐 legado JsExtensions）。
class JsSymmetricCrypto {
  JsSymmetricCrypto._(this._isAes, this._cbc, this._block, this._iv,
      this._aes, this._des);

  final bool _isAes;
  final bool _cbc;
  final int _block;
  final List<int> _iv;
  final _AesCore? _aes;
  final _DesCore? _des;

  List<int> _encBlock(List<int> b) =>
      _isAes ? _aes!.encryptBlock(b) : _des!.encryptBlock(b);
  List<int> _decBlock(List<int> b) =>
      _isAes ? _aes!.decryptBlock(b) : _des!.decryptBlock(b);

  /// 单分组 ECB 原语（无填充/无 CBC 链），用于对齐 AES / DES 标准测试向量。
  List<int> encryptBlock(List<int> block) => _encBlock(block);

  /// 单分组 ECB 解密原语（与 [encryptBlock] 互逆）。
  List<int> decryptBlock(List<int> block) => _decBlock(block);

  /// 加密字节（PKCS5/PKCS7 填充 + 可选 CBC），返回字节数组（对齐 encrypt）。
  List<int> encrypt(List<int> data) {
    final padded = _pad(data, _block);
    final out = <int>[];
    var prev = List<int>.from(_iv);
    for (var off = 0; off < padded.length; off += _block) {
      final block = padded.sublist(off, off + _block);
      final x = _cbc
          ? List<int>.generate(_block, (i) => block[i] ^ prev[i])
          : block;
      final c = _encBlock(x);
      out.addAll(c);
      prev = c;
    }
    return out;
  }

  /// 加密字符串为 base64（对齐 encryptBase64）。
  String encryptBase64(String text) =>
      JsBridgeCodec.bytesToBase64(encrypt(utf8.encode(text)));

  /// 加密字符串为 hex（对齐 encryptHex）。
  String encryptHex(String text) =>
      JsBridgeCodec.bytesToHex(encrypt(utf8.encode(text)));

  /// 解密字节数组（可选 CBC + 去填充），返回明文字节（对齐 decrypt）。
  List<int> decrypt(List<int> cipher) {
    final out = <int>[];
    var prev = List<int>.from(_iv);
    for (var off = 0; off + _block <= cipher.length; off += _block) {
      final c = cipher.sublist(off, off + _block);
      final p = _decBlock(c);
      out.addAll(_cbc
          ? List<int>.generate(_block, (i) => p[i] ^ prev[i])
          : p);
      prev = c;
    }
    return _unpad(out, _block);
  }

  /// 解密字符串（hex 或 base64；亦兼容 7814 传入的字节数组）为 UTF-8 明文。
  String decryptStr(Object input) {
    List<int> bytes;
    if (input is List<int>) {
      bytes = input;
    } else {
      final s = input.toString();
      bytes = RegExp(r'^[0-9a-fA-F]+$').hasMatch(s) && s.length.isEven
          ? JsBridgeCodec.hexToBytes(s)
          : JsBridgeCodec.base64DecodeToByteArray(s);
    }
    try {
      return utf8.decode(decrypt(bytes));
    } catch (_) {
      return '';
    }
  }

  static List<int> _pad(List<int> data, int block) {
    final pad = block - (data.length % block);
    return [...data, ...List<int>.filled(pad, pad)];
  }

  static List<int> _unpad(List<int> data, int block) {
    if (data.isEmpty) return data;
    final p = data.last;
    if (p > 0 && p <= block && data.length >= p) {
      for (var i = data.length - p; i < data.length; i++) {
        if (data[i] != p) return data;
      }
      return data.sublist(0, data.length - p);
    }
    return data;
  }
}

/// 对齐 java.createSymmetricCrypto(transformation, key, iv)：纯 Dart AES / DES。
class JsBridgeCrypto {
  JsBridgeCrypto._();

  /// transformation 形如 "AES"、"AES/CBC/PKCS5Padding"、"DES/CBC/PKCS5Padding"。
  /// 含 CBC 走 CBC，否则 ECB；含 DES 走 DES（8 字节分组），否则 AES（16 字节分组）。
  /// key/iv 可为 String（书源原始值，按 UTF-8 取字节）或 List<int>（字节数组，供标准向量测试）。
  static JsSymmetricCrypto createSymmetricCrypto(
      String transformation, Object key, [Object iv = '']) {
    final mode = transformation.toUpperCase();
    final isAes = !mode.contains('DES');
    final cbc = mode.contains('CBC');
    final block = isAes ? 16 : 8;
    final kb = _bytesOf(key);
    final keyBytes = isAes ? _aesKeyBytes(kb) : _padTo(kb, 8);
    final ivBytes = _padTo(_bytesOf(iv), block);
    return JsSymmetricCrypto._(
      isAes,
      cbc,
      block,
      ivBytes,
      isAes ? _AesCore(keyBytes) : null,
      isAes ? null : _DesCore(keyBytes),
    );
  }

  static List<int> _bytesOf(Object v) =>
      v is List<int> ? List<int>.from(v) : utf8.encode(v.toString());

  /// 对齐桥 __aesKeyBytes：key 补零到最近的 16/24/32 字节，超长截断到 32。
  static List<int> _aesKeyBytes(List<int> kb) {
    for (final size in const [16, 24, 32]) {
      if (kb.length <= size) return _padTo(kb, size);
    }
    return kb.sublist(0, 32);
  }

  static List<int> _padTo(List<int> bytes, int size) {
    final out = List<int>.filled(size, 0);
    final n = bytes.length < size ? bytes.length : size;
    for (var i = 0; i < n; i++) {
      out[i] = bytes[i];
    }
    return out;
  }
}

/// 离线 JS 运行时外观：把书源的 jsLib / loginUrl 组装为「注入脚本」供断言。
///
/// 与 `WebViewLegadoJs.loadSource` 的注入顺序一致（bridge 之后执行 jsLib、
/// 再执行 loginUrl）；仅做脚本收集与函数检测，不执行 JS、不触碰 WebView。
class OfflineJsBridge {
  final JsBridgeCache cache = JsBridgeCache();
  final JsBridgeCookie cookie = JsBridgeCookie();
  late final JsBridgeSource source;
  String _script = '';

  /// 注入书源脚本（对齐 WebViewLegadoJs.loadSource 的 jsLib + loginUrl 顺序）。
  void loadSource(JsSource src) {
    source = JsBridgeSource(url: src.jsUrl, variable: src.variable ?? '');
    final buf = StringBuffer();
    final lib = (src.jsLib ?? '').trim();
    if (lib.isNotEmpty) buf.writeln(lib);
    final login = (src.loginUrl ?? '').trim();
    if (login.isNotEmpty) buf.writeln(login);
    _script = buf.toString();
  }

  /// 已组装的注入脚本（jsLib + loginUrl）。
  String get script => _script;

  /// 注入脚本是否定义了关键全局函数（如 getArguments / getServerHost）。
  bool containsFunction(String name) => RegExp(
          r'function\s+' +
              RegExp.escape(name) +
              r'\s*\(|(?:var|let|const)\s+' +
              RegExp.escape(name) +
              r'\s*=')
      .hasMatch(_script);
}

// ============================ AES（FIPS-197，纯 Dart） ============================

/// AES-128/192/256 单分组密码核心（ECB 原语），供 CBC / 填充层复用。
class _AesCore {
  _AesCore(List<int> key)
      : _nk = key.length ~/ 4,
        _nr = key.length ~/ 4 + 6 {
    _invSbox = List<int>.filled(256, 0);
    for (var i = 0; i < 256; i++) {
      _invSbox[_sbox[i]] = i;
    }
    _expandKey(key);
  }

  final int _nk;
  final int _nr;
  final List<List<int>> _w = <List<int>>[];
  late final List<int> _invSbox;

  void _expandKey(List<int> key) {
    final total = 4 * (_nr + 1);
    for (var i = 0; i < _nk; i++) {
      _w.add(key.sublist(4 * i, 4 * i + 4));
    }
    var rcon = 1;
    for (var i = _nk; i < total; i++) {
      var t = List<int>.from(_w[i - 1]);
      if (i % _nk == 0) {
        t = [t[1], t[2], t[3], t[0]].map((b) => _sbox[b]).toList();
        t[0] ^= rcon;
        rcon = _xtime(rcon);
      } else if (_nk > 6 && i % _nk == 4) {
        t = t.map((b) => _sbox[b]).toList();
      }
      final p = _w[i - _nk];
      _w.add([
        p[0] ^ t[0],
        p[1] ^ t[1],
        p[2] ^ t[2],
        p[3] ^ t[3],
      ]);
    }
  }

  static int _xtime(int a) =>
      ((a << 1) ^ ((a & 0x80) != 0 ? 0x1b : 0)) & 0xff;

  List<int> _roundKey(int round) {
    final out = <int>[];
    for (var c = 0; c < 4; c++) {
      out.addAll(_w[4 * round + c]);
    }
    return out;
  }

  static void _addRoundKey(List<int> s, List<int> rk) {
    for (var i = 0; i < 16; i++) {
      s[i] ^= rk[i];
    }
  }

  void _subBytes(List<int> s) {
    for (var i = 0; i < 16; i++) {
      s[i] = _sbox[s[i]];
    }
  }

  void _invSubBytes(List<int> s) {
    for (var i = 0; i < 16; i++) {
      s[i] = _invSbox[s[i]];
    }
  }

  static List<int> _shiftRows(List<int> s) {
    final o = List<int>.filled(16, 0);
    for (var r = 0; r < 4; r++) {
      for (var c = 0; c < 4; c++) {
        o[r + 4 * c] = s[r + 4 * ((c + r) % 4)];
      }
    }
    return o;
  }

  static List<int> _invShiftRows(List<int> s) {
    final o = List<int>.filled(16, 0);
    for (var r = 0; r < 4; r++) {
      for (var c = 0; c < 4; c++) {
        o[r + 4 * c] = s[r + 4 * ((c - r + 4) % 4)];
      }
    }
    return o;
  }

  static List<int> _mixColumns(List<int> s, bool inverse) {
    final o = List<int>.filled(16, 0);
    for (var c = 0; c < 4; c++) {
      final a0 = s[4 * c], a1 = s[4 * c + 1], a2 = s[4 * c + 2], a3 = s[4 * c + 3];
      if (inverse) {
        o[4 * c] = _g(a0, 14) ^ _g(a1, 11) ^ _g(a2, 13) ^ _g(a3, 9);
        o[4 * c + 1] = _g(a0, 9) ^ _g(a1, 14) ^ _g(a2, 11) ^ _g(a3, 13);
        o[4 * c + 2] = _g(a0, 13) ^ _g(a1, 9) ^ _g(a2, 14) ^ _g(a3, 11);
        o[4 * c + 3] = _g(a0, 11) ^ _g(a1, 13) ^ _g(a2, 9) ^ _g(a3, 14);
      } else {
        o[4 * c] = _g(a0, 2) ^ _g(a1, 3) ^ a2 ^ a3;
        o[4 * c + 1] = a0 ^ _g(a1, 2) ^ _g(a2, 3) ^ a3;
        o[4 * c + 2] = a0 ^ a1 ^ _g(a2, 2) ^ _g(a3, 3);
        o[4 * c + 3] = _g(a0, 3) ^ a1 ^ a2 ^ _g(a3, 2);
      }
    }
    return o;
  }

  static int _g(int a, int b) {
    var p = 0;
    var aa = a;
    var bb = b;
    for (var i = 0; i < 8; i++) {
      if ((bb & 1) != 0) p ^= aa;
      final hi = aa & 0x80;
      aa = (aa << 1) & 0xff;
      if (hi != 0) aa ^= 0x1b;
      bb >>= 1;
    }
    return p & 0xff;
  }

  static void _copy(List<int> dst, List<int> src) {
    for (var i = 0; i < 16; i++) {
      dst[i] = src[i];
    }
  }

  List<int> encryptBlock(List<int> block) {
    final s = List<int>.from(block);
    _addRoundKey(s, _roundKey(0));
    for (var r = 1; r < _nr; r++) {
      _subBytes(s);
      _copy(s, _shiftRows(s));
      _copy(s, _mixColumns(s, false));
      _addRoundKey(s, _roundKey(r));
    }
    _subBytes(s);
    _copy(s, _shiftRows(s));
    _addRoundKey(s, _roundKey(_nr));
    return s;
  }

  List<int> decryptBlock(List<int> block) {
    final s = List<int>.from(block);
    _addRoundKey(s, _roundKey(_nr));
    for (var r = _nr - 1; r >= 1; r--) {
      _copy(s, _invShiftRows(s));
      _invSubBytes(s);
      _addRoundKey(s, _roundKey(r));
      _copy(s, _mixColumns(s, true));
    }
    _copy(s, _invShiftRows(s));
    _invSubBytes(s);
    _addRoundKey(s, _roundKey(0));
    return s;
  }

  static const List<int> _sbox = <int>[
    0x63, 0x7c, 0x77, 0x7b, 0xf2, 0x6b, 0x6f, 0xc5, 0x30, 0x01, 0x67, 0x2b, 0xfe, 0xd7, 0xab, 0x76,
    0xca, 0x82, 0xc9, 0x7d, 0xfa, 0x59, 0x47, 0xf0, 0xad, 0xd4, 0xa2, 0xaf, 0x9c, 0xa4, 0x72, 0xc0,
    0xb7, 0xfd, 0x93, 0x26, 0x36, 0x3f, 0xf7, 0xcc, 0x34, 0xa5, 0xe5, 0xf1, 0x71, 0xd8, 0x31, 0x15,
    0x04, 0xc7, 0x23, 0xc3, 0x18, 0x96, 0x05, 0x9a, 0x07, 0x12, 0x80, 0xe2, 0xeb, 0x27, 0xb2, 0x75,
    0x09, 0x83, 0x2c, 0x1a, 0x1b, 0x6e, 0x5a, 0xa0, 0x52, 0x3b, 0xd6, 0xb3, 0x29, 0xe3, 0x2f, 0x84,
    0x53, 0xd1, 0x00, 0xed, 0x20, 0xfc, 0xb1, 0x5b, 0x6a, 0xcb, 0xbe, 0x39, 0x4a, 0x4c, 0x58, 0xcf,
    0xd0, 0xef, 0xaa, 0xfb, 0x43, 0x4d, 0x33, 0x85, 0x45, 0xf9, 0x02, 0x7f, 0x50, 0x3c, 0x9f, 0xa8,
    0x51, 0xa3, 0x40, 0x8f, 0x92, 0x9d, 0x38, 0xf5, 0xbc, 0xb6, 0xda, 0x21, 0x10, 0xff, 0xf3, 0xd2,
    0xcd, 0x0c, 0x13, 0xec, 0x5f, 0x97, 0x44, 0x17, 0xc4, 0xa7, 0x7e, 0x3d, 0x64, 0x5d, 0x19, 0x73,
    0x60, 0x81, 0x4f, 0xdc, 0x22, 0x2a, 0x90, 0x88, 0x46, 0xee, 0xb8, 0x14, 0xde, 0x5e, 0x0b, 0xdb,
    0xe0, 0x32, 0x3a, 0x0a, 0x49, 0x06, 0x24, 0x5c, 0xc2, 0xd3, 0xac, 0x62, 0x91, 0x95, 0xe4, 0x79,
    0xe7, 0xc8, 0x37, 0x6d, 0x8d, 0xd5, 0x4e, 0xa9, 0x6c, 0x56, 0xf4, 0xea, 0x65, 0x7a, 0xae, 0x08,
    0xba, 0x78, 0x25, 0x2e, 0x1c, 0xa6, 0xb4, 0xc6, 0xe8, 0xdd, 0x74, 0x1f, 0x4b, 0xbd, 0x8b, 0x8a,
    0x70, 0x3e, 0xb5, 0x66, 0x48, 0x03, 0xf6, 0x0e, 0x61, 0x35, 0x57, 0xb9, 0x86, 0xc1, 0x1d, 0x9e,
    0xe1, 0xf8, 0x98, 0x11, 0x69, 0xd9, 0x8e, 0x94, 0x9b, 0x1e, 0x87, 0xe9, 0xce, 0x55, 0x28, 0xdf,
    0x8c, 0xa1, 0x89, 0x0d, 0xbf, 0xe6, 0x42, 0x68, 0x41, 0x99, 0x2d, 0x0f, 0xb0, 0x54, 0xbb, 0x16,
  ];
}

// ============================ DES（FIPS 46-3，纯 Dart） ============================

/// DES 单分组密码核心（ECB 原语，16 轮 Feistel），供 CBC / 填充层复用。
class _DesCore {
  _DesCore(List<int> key8) {
    _schedule(key8);
  }

  final List<List<int>> _subkeys = <List<int>>[];

  void _schedule(List<int> key8) {
    final pc1 = _permute(_bytesToBits(key8), _pc1);
    var c = pc1.sublist(0, 28);
    var d = pc1.sublist(28, 56);
    for (var r = 0; r < 16; r++) {
      final sh = _shifts[r];
      c = <int>[...c.sublist(sh), ...c.sublist(0, sh)];
      d = <int>[...d.sublist(sh), ...d.sublist(0, sh)];
      _subkeys.add(_permute(<int>[...c, ...d], _pc2));
    }
  }

  List<int> _feistel(List<int> r, List<int> subkey) {
    final er = _permute(r, _e);
    final x = List<int>.generate(48, (i) => er[i] ^ subkey[i]);
    final sOut = <int>[];
    for (var i = 0; i < 8; i++) {
      final b = x.sublist(i * 6, i * 6 + 6);
      final row = (b[0] << 1) | b[5];
      final col = (b[1] << 3) | (b[2] << 2) | (b[3] << 1) | b[4];
      final v = _s[i][row * 16 + col];
      for (var j = 3; j >= 0; j--) {
        sOut.add((v >> j) & 1);
      }
    }
    return _permute(sOut, _p);
  }

  List<int> _crypt(List<int> block8, bool decrypt) {
    var bits = _permute(_bytesToBits(block8), _ip);
    var l = bits.sublist(0, 32);
    var r = bits.sublist(32, 64);
    for (var i = 0; i < 16; i++) {
      final subkey = _subkeys[decrypt ? 15 - i : i];
      final f = _feistel(r, subkey);
      final newR = List<int>.generate(32, (j) => l[j] ^ f[j]);
      l = r;
      r = newR;
    }
    return _bitsToBytes(_permute(<int>[...r, ...l], _fp));
  }

  List<int> encryptBlock(List<int> block8) => _crypt(block8, false);
  List<int> decryptBlock(List<int> block8) => _crypt(block8, true);

  static List<int> _bytesToBits(List<int> bytes) {
    final bits = <int>[];
    for (final b in bytes) {
      for (var i = 7; i >= 0; i--) {
        bits.add((b >> i) & 1);
      }
    }
    return bits;
  }

  static List<int> _bitsToBytes(List<int> bits) {
    final out = <int>[];
    for (var i = 0; i < bits.length; i += 8) {
      var v = 0;
      for (var j = 0; j < 8; j++) {
        v = (v << 1) | bits[i + j];
      }
      out.add(v);
    }
    return out;
  }

  static List<int> _permute(List<int> src, List<int> table) =>
      table.map((p) => src[p - 1]).toList();

  static const List<int> _ip = <int>[
    58, 50, 42, 34, 26, 18, 10, 2, 60, 52, 44, 36, 28, 20, 12, 4,
    62, 54, 46, 38, 30, 22, 14, 6, 64, 56, 48, 40, 32, 24, 16, 8,
    57, 49, 41, 33, 25, 17, 9, 1, 59, 51, 43, 35, 27, 19, 11, 3,
    61, 53, 45, 37, 29, 21, 13, 5, 63, 55, 47, 39, 31, 23, 15, 7,
  ];
  static const List<int> _fp = <int>[
    40, 8, 48, 16, 56, 24, 64, 32, 39, 7, 47, 15, 55, 23, 63, 31,
    38, 6, 46, 14, 54, 22, 62, 30, 37, 5, 45, 13, 53, 21, 61, 29,
    36, 4, 44, 12, 52, 20, 60, 28, 35, 3, 43, 11, 51, 19, 59, 27,
    34, 2, 42, 10, 50, 18, 58, 26, 33, 1, 41, 9, 49, 17, 57, 25,
  ];
  static const List<int> _e = <int>[
    32, 1, 2, 3, 4, 5, 4, 5, 6, 7, 8, 9, 8, 9, 10, 11, 12, 13,
    12, 13, 14, 15, 16, 17, 16, 17, 18, 19, 20, 21, 20, 21, 22, 23,
    24, 25, 24, 25, 26, 27, 28, 29, 28, 29, 30, 31, 32, 1,
  ];
  static const List<int> _p = <int>[
    16, 7, 20, 21, 29, 12, 28, 17, 1, 15, 23, 26, 5, 18, 31, 10,
    2, 8, 24, 14, 32, 27, 3, 9, 19, 13, 30, 6, 22, 11, 4, 25,
  ];
  static const List<int> _pc1 = <int>[
    57, 49, 41, 33, 25, 17, 9, 1, 58, 50, 42, 34, 26, 18,
    10, 2, 59, 51, 43, 35, 27, 19, 11, 3, 60, 52, 44, 36,
    63, 55, 47, 39, 31, 23, 15, 7, 62, 54, 46, 38, 30, 22,
    14, 6, 61, 53, 45, 37, 29, 21, 13, 5, 28, 20, 12, 4,
  ];
  static const List<int> _pc2 = <int>[
    14, 17, 11, 24, 1, 5, 3, 28, 15, 6, 21, 10,
    23, 19, 12, 4, 26, 8, 16, 7, 27, 20, 13, 2,
    41, 52, 31, 37, 47, 55, 30, 40, 51, 45, 33, 48,
    44, 49, 39, 56, 34, 53, 46, 42, 50, 36, 29, 32,
  ];
  static const List<int> _shifts = <int>[
    1, 1, 2, 2, 2, 2, 2, 2, 1, 2, 2, 2, 2, 2, 2, 1,
  ];
  static const List<List<int>> _s = <List<int>>[
    <int>[
      14, 4, 13, 1, 2, 15, 11, 8, 3, 10, 6, 12, 5, 9, 0, 7,
      0, 15, 7, 4, 14, 2, 13, 1, 10, 6, 12, 11, 9, 5, 3, 8,
      4, 1, 14, 8, 13, 6, 2, 11, 15, 12, 9, 7, 3, 10, 5, 0,
      15, 12, 8, 2, 4, 9, 1, 7, 5, 11, 3, 14, 10, 0, 6, 13,
    ],
    <int>[
      15, 1, 8, 14, 6, 11, 3, 4, 9, 7, 2, 13, 12, 0, 5, 10,
      3, 13, 4, 7, 15, 2, 8, 14, 12, 0, 1, 10, 6, 9, 11, 5,
      0, 14, 7, 11, 10, 4, 13, 1, 5, 8, 12, 6, 9, 3, 2, 15,
      13, 8, 10, 1, 3, 15, 4, 2, 11, 6, 7, 12, 0, 5, 14, 9,
    ],
    <int>[
      10, 0, 9, 14, 6, 3, 15, 5, 1, 13, 12, 7, 11, 4, 2, 8,
      13, 7, 0, 9, 3, 4, 6, 10, 2, 8, 5, 14, 12, 11, 15, 1,
      13, 6, 4, 9, 8, 15, 3, 0, 11, 1, 2, 12, 5, 10, 14, 7,
      1, 10, 13, 0, 6, 9, 8, 7, 4, 15, 14, 3, 11, 5, 2, 12,
    ],
    <int>[
      7, 13, 14, 3, 0, 6, 9, 10, 1, 2, 8, 5, 11, 12, 4, 15,
      13, 8, 11, 5, 6, 15, 0, 3, 4, 7, 2, 12, 1, 10, 14, 9,
      10, 6, 9, 0, 12, 11, 7, 13, 15, 1, 3, 14, 5, 2, 8, 4,
      3, 15, 0, 6, 10, 1, 13, 8, 9, 4, 5, 11, 12, 7, 2, 14,
    ],
    <int>[
      2, 12, 4, 1, 7, 10, 11, 6, 8, 5, 3, 15, 13, 0, 14, 9,
      14, 11, 2, 12, 4, 7, 13, 1, 5, 0, 15, 10, 3, 9, 8, 6,
      4, 2, 1, 11, 10, 13, 7, 8, 15, 9, 12, 5, 6, 3, 0, 14,
      11, 8, 12, 7, 1, 14, 2, 13, 6, 15, 0, 9, 10, 4, 5, 3,
    ],
    <int>[
      12, 1, 10, 15, 9, 2, 6, 8, 0, 13, 3, 4, 14, 7, 5, 11,
      10, 15, 4, 2, 7, 12, 9, 5, 6, 1, 13, 14, 0, 11, 3, 8,
      9, 14, 15, 5, 2, 8, 12, 3, 7, 0, 4, 10, 1, 13, 11, 6,
      4, 3, 2, 12, 9, 5, 15, 10, 11, 14, 1, 7, 6, 0, 8, 13,
    ],
    <int>[
      4, 11, 2, 14, 15, 0, 8, 13, 3, 12, 9, 7, 5, 10, 6, 1,
      13, 0, 11, 7, 4, 9, 1, 10, 14, 3, 5, 12, 2, 15, 8, 6,
      1, 4, 11, 13, 12, 3, 7, 14, 10, 15, 6, 8, 0, 5, 9, 2,
      6, 11, 13, 8, 1, 4, 10, 7, 9, 5, 0, 15, 14, 2, 3, 12,
    ],
    <int>[
      13, 2, 8, 4, 6, 15, 11, 1, 10, 9, 3, 14, 5, 0, 12, 7,
      1, 15, 13, 8, 10, 3, 7, 4, 12, 5, 6, 11, 0, 14, 9, 2,
      7, 11, 4, 1, 9, 12, 14, 2, 0, 6, 10, 13, 15, 3, 5, 8,
      2, 1, 14, 7, 4, 10, 8, 13, 15, 12, 9, 0, 3, 5, 6, 11,
    ],
  ];
}
