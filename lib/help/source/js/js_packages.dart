/// Rhino `Packages.*` → 本桥已注入 Java/工具包的真实映射。
///
/// legado（Android / Rhino）里书源脚本常写 `Packages.android.util.Base64`、
/// `Packages.java.lang.String`、`Packages.java.lang.Thread` 等访问 Java 类。
/// WebView 使用 V8，没有 JVM；本文件把这些类名映射为桥内**已实现**的等价
/// JS 值/工具（java.*、cookie、__b64Unicode 等），使书源脚本里的
/// `Packages.xxx` 真正可用，而不是原先恒返回 null 的死 Proxy。
///
/// 未在本映射表中的类（例如某些 fork 特供的
/// `io.legato.kazusa.utils.TimeoutCancellationException`）取值为 undefined，
/// 书源 `checkEnv()` 之类「取不到即非改版」的环境判定因此仍能正确工作。
///
/// 本片段被拼进 [LegadoBridgeJs] 的 IIFE 末尾（见 `legado_bridge_js.dart`
/// 的 `code` 拼接），此时 java / __b64Unicode 等全部工具均已定义，可直接引用。
library;

class JsPackages {
  JsPackages._();

  /// 注入到桥 IIFE 末尾的 JS 片段（原始字符串，Dart 不转义反斜杠与 `$`）。
  static const String definition = r'''

  // ---- Rhino Packages.* 真实映射（对齐 legado 的 Java 互操作）----
  // 说明：以下每个键都是一串完整 Java 类名，值是桥里已实现的等价 JS 工具；
  // 最后按「.」拆成嵌套命名空间挂到 globalThis.Packages 上。未登记的类名
  // 取值为 undefined —— 这是「真实映射」而非「恒 null 假装存在」。

  // 字节数组（Array / Uint8Array / 字符串）→ 标准 base64（等价 NO_WRAP）。
  function __pkgBytesToB64(bytes) {
    if (bytes === null || bytes === undefined) return "";
    if (typeof bytes === "string") return __b64Unicode(bytes);
    var arr = bytes;
    if (!Array.isArray(arr) && !(typeof Uint8Array !== "undefined" && arr instanceof Uint8Array)) {
      if (arr && typeof arr.length === "number") arr = Array.prototype.slice.call(arr);
      else return __b64Unicode(String(arr));
    }
    var bin = "";
    for (var i = 0; i < arr.length; i++) bin += String.fromCharCode(arr[i] & 0xff);
    return btoa(bin);
  }
  // 标准 base64 → 字节数组（等价 android.util.Base64.decode）。
  function __pkgB64ToBytes(str) {
    try { return Array.from(__b64ToBytes(String(str == null ? "" : str))); }
    catch (e) { return []; }
  }
  // 字节数组 → UTF-8 文本（等价 new String(byte[], "UTF-8")）。
  function __pkgBytesToStr(bytes) {
    if (bytes === null || bytes === undefined) return "";
    if (typeof bytes === "string") return bytes;
    try {
      var arr = (typeof Uint8Array !== "undefined" && bytes instanceof Uint8Array)
          ? bytes : Uint8Array.from(bytes || []);
      return new TextDecoder("utf-8").decode(arr);
    } catch (e) { return String(bytes); }
  }
  // Thread.sleep：V8 没有原生阻塞 sleep，用限时忙等对齐 Android 的节流语义
  // （上限 60s，避免异常入参把 WebView 卡死；legado 本来也阻塞后台线程）。
  function __pkgSleep(ms) {
    var n = Math.max(0, Math.min(Number(ms) || 0, 60000));
    if (n <= 0) return;
    var end = Date.now() + n;
    while (Date.now() < end) {}
  }
  function __pkgStringBuilder(init) {
    this._s = (init === null || init === undefined) ? "" : String(init);
  }
  __pkgStringBuilder.prototype.append = function (v) {
    this._s += (v === null || v === undefined) ? "null" : String(v);
    return this;
  };
  __pkgStringBuilder.prototype.toString = function () { return this._s; };
  __pkgStringBuilder.prototype.length = function () { return this._s.length; };
  __pkgStringBuilder.prototype.setLength = function (n) {
    this._s = this._s.substring(0, Number(n) || 0);
    return this;
  };
  __pkgStringBuilder.prototype.reverse = function () {
    this._s = this._s.split("").reverse().join("");
    return this;
  };

  // android.util.Base64 / java.util.Base64 的等价实现。
  var __pkgAndroidBase64 = {
    encodeToString: function (bytes, flags) { return __pkgBytesToB64(bytes); },
    encode: function (bytes, flags) { return __pkgBytesToB64(bytes); },
    decode: function (str, flags) { return __pkgB64ToBytes(str); }
  };
  var __pkgJavaBase64 = {
    getEncoder: function () {
      return { encodeToString: function (b) { return __pkgBytesToB64(b); },
               encode: function (b) { return __pkgB64ToBytes(__pkgBytesToB64(b)); } };
    },
    getDecoder: function () {
      return { decode: function (s) { return __pkgB64ToBytes(s); },
               decodeToString: function (s) { return __pkgBytesToStr(__pkgB64ToBytes(s)); } };
    },
    getUrlEncoder: function () {
      return { encodeToString: function (b) {
        return __pkgBytesToB64(b).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
      } };
    },
    getMimeEncoder: function () {
      return { encodeToString: function (b) { return __pkgBytesToB64(b); } };
    }
  };
  var __pkgSystem = {
    currentTimeMillis: function () { return Date.now(); },
    nanoTime: function () { return Date.now() * 1000000; },
    getProperty: function (k) { return String(k) === "line.separator" ? "\n" : ""; },
    getenv: function (k) { return ""; },
    arraycopy: function (src, srcPos, dst, dstPos, len) {
      for (var i = 0; i < len; i++) dst[dstPos + i] = src[srcPos + i];
    }
  };
  var __pkgLog = {
    v: function (t, m) { java.log("[V]" + t + ":" + m); },
    d: function (t, m) { java.log("[D]" + t + ":" + m); },
    i: function (t, m) { java.log("[I]" + t + ":" + m); },
    w: function (t, m) { java.log("[W]" + t + ":" + m); },
    e: function (t, m) { java.log("[E]" + t + ":" + m); }
  };

  // 已注入工具的 Java 类名映射表（键 = 完整类名，值 = 等价 JS 实现）。
  var __pkgClassMap = {
    "java.lang.String": String,
    "java.lang.CharSequence": String,
    "java.lang.Object": Object,
    "java.lang.Math": Math,
    "java.lang.Boolean": Boolean,
    "java.lang.Number": Number,
    "java.lang.Integer": Number,
    "java.lang.Long": Number,
    "java.lang.Double": Number,
    "java.lang.Float": Number,
    "java.lang.Short": Number,
    "java.lang.Byte": Number,
    "java.lang.System": __pkgSystem,
    "java.lang.Thread": { sleep: __pkgSleep },
    "java.lang.StringBuilder": __pkgStringBuilder,
    "java.lang.StringBuffer": __pkgStringBuilder,
    "java.util.UUID": { randomUUID: function () { return java.randomUUID(); } },
    "java.util.Base64": __pkgJavaBase64,
    "java.util.Arrays": {
      toString: function (a) { return (a && a.join) ? a.join(",") : String(a); },
      asList: function () { return Array.prototype.slice.call(arguments); }
    },
    "java.net.URLEncoder": {
      encode: function (s, enc) { return encodeURIComponent(String(s == null ? "" : s)); }
    },
    "java.net.URLDecoder": {
      decode: function (s, enc) {
        try { return decodeURIComponent(String(s == null ? "" : s)); }
        catch (e) { return String(s); }
      }
    },
    "java.net.URL": function (u) {
      return {
        toString: function () { return String(u); },
        getHost: function () { try { return new URL(String(u)).host; } catch (e) { return ""; } },
        getPath: function () { try { return new URL(String(u)).pathname; } catch (e) { return ""; } }
      };
    },
    "android.util.Base64": __pkgAndroidBase64,
    "android.util.Log": __pkgLog,
    "android.text.TextUtils": {
      isEmpty: function (s) { return s === null || s === undefined || String(s).length === 0; },
      equals: function (a, b) { return String(a) === String(b); },
      join: function (sep, arr) { return (arr && arr.join) ? arr.join(sep) : ""; }
    },
    // legado 自有工具类：直接映射到桥已实现的 java.* 方法（非占位）。
    "io.legado.app.utils.MD5Utils": {
      md5Encode: function (s) { return java.md5Encode(s); },
      md5Encode16: function (s) { return java.md5Encode16(s); }
    },
    "io.legado.app.help.EncodeUtils": {
      base64Encode: function (s) { return java.base64Encode(s); },
      base64Decode: function (s) { return java.base64Decode(s); },
      hexEncodeToString: function (s) { return java.hexEncodeToString(s); },
      hexDecodeToString: function (s) { return java.hexDecodeToString(s); }
    },
    "io.legado.app.utils.HexUtils": {
      encodeToString: function (s) { return java.hexEncodeToString(s); },
      decodeToString: function (s) { return java.hexDecodeToString(s); }
    },
    "io.legado.app.utils.GZIPUtils": {
      compress: function (s) { return java.gzipCompress(s); },
      uncompress: function (s) { return java.gzipDecompress(s); }
    },
    "io.legado.app.utils.StringUtils": {
      isEmpty: function (s) { return s === null || s === undefined || String(s).length === 0; },
      trim: function (s) { return String(s == null ? "" : s).trim(); }
    },
    "io.legado.app.help.JsExtensions": java
  };

  // 把扁平类名表展开成嵌套命名空间：Packages.java.lang.String / Packages.android.util.Base64 …
  var __pkgRoot = {};
  Object.keys(__pkgClassMap).forEach(function (path) {
    var parts = path.split(".");
    var node = __pkgRoot;
    for (var i = 0; i < parts.length - 1; i++) {
      if (!node[parts[i]] || typeof node[parts[i]] !== "object") node[parts[i]] = {};
      node = node[parts[i]];
    }
    node[parts[parts.length - 1]] = __pkgClassMap[path];
  });
  globalThis.Packages = __pkgRoot;
''';
}
