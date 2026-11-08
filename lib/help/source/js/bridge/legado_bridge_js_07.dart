/// JS 片段 7/8（按体积均匀切片，拼接顺序不可变）。
const String legadoBridgeJsPart07 = r'''  function __jsoupResponse(url, text, code, message, headers, cookies) {
    var b = (text === null || text === undefined) ? "" : String(text);
    var hdrs = headers || {};
    return {
      body: function () { return b; },
      bodyAsBytes: function () { return new TextEncoder().encode(b); },
      statusCode: function () { return code || 200; },
      statusMessage: function () { return message || "OK"; },
      headers: function () { return hdrs; },
      header: function (name) {
        var keys = Object.keys(hdrs);
        for (var i = 0; i < keys.length; i++) {
          if (keys[i].toLowerCase() === String(name).toLowerCase()) return hdrs[keys[i]];
        }
        return null;
      },
      cookie: function (name) { return (cookies || {})[name] || null; },
      cookies: function () { return cookies || {}; },
      url: function () { return String(url == null ? "" : url); },
      charset: function () { return "utf-8"; },
      parse: function () { return b; },
      execute: function () { return this; },
      toString: function () { return b; }
    };
  }

  // java.connect(url)：legado 语义为「立即执行并返回 StrResponse」；
  // 同时兼容书源里常见的建造者写法（.method().body().execute()）：
  //   * 直接调用 .body()/.url()/.code() → 触发一次 GET 并返回 StrResponse 字段
  //   * 先配置再 .execute() → 按配置发起请求，返回 StrResponse
  function __connect(url) {
    var state = { url: __resolve(url), method: "GET", headers: {}, body: null };
    var executed = null;
    function run() {
      if (executed) return executed;
      var text = __doXhr(state.url, { method: state.method, headers: state.headers, body: state.body });
      executed = __strResponse(state.url, text, 200, "OK", state.headers);
      return executed;
    }
    function invalidate() { executed = null; }
    var conn = {
      __url: state.url, __method: "GET", __headers: {}, __body: null,
      headers: function (h) {
        if (h) Object.keys(h).forEach((k) => { state.headers[k] = h[k]; });
        invalidate(); return this;
      },
      addHeader: function (k, v) { state.headers[k] = v; invalidate(); return this; },
      header: function (k, v) { state.headers[k] = v; invalidate(); return this; },
      method: function (m) { state.method = String(m).toUpperCase(); invalidate(); return this; },
      setBody: function (b) { state.body = b; invalidate(); return this; },
      // body() 无参 = StrResponse.body() 取值；带参 = 建造者设置请求体
      body: function (b) {
        if (b === undefined) return run().body();
        state.body = b; state.method = "POST"; invalidate(); return this;
      },
      get: function () { state.method = "GET"; invalidate(); return this; },
      post: function (b) { state.method = "POST"; if (b !== undefined) state.body = b; invalidate(); return this; },
      followRedirects: function () { return this; },
      timeout: function () { return this; },
      execute: function () { return run(); },
      url: function () { return run().url(); },
      code: function () { return run().code(); },
      message: function () { return run().message(); },
      headers_map: null,
      raw: function () { return run().raw(); },
      toString: function () { return run().toString(); }
    };
    return conn;
  }

  // ============================ 浏览器交互登录 ============================
  function __openBrowser(url, title, awaitFlag) {
    var id = "b" + Date.now() + Math.floor(Math.random() * 1000);
    __state.browser.push({ id: id, url: __resolve(url), title: title || "" });
    return new Promise(function (resolve) {
      __pendings[id] = resolve;
      try {
        if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
          window.flutter_inappwebview.callHandler("legadoBrowser", JSON.stringify({
            id: id, url: __resolve(url), title: title || ""
          }));
        }
      } catch (e) {}
      if (!awaitFlag) {
        setTimeout(function () { if (__pendings[id]) { delete __pendings[id]; resolve(""); } }, 0);
      }
    });
  }
  globalThis.__resolveBrowser = function (id, cookieStr, finalUrl) {
    if (cookieStr) __ingestSetCookie(finalUrl || "", cookieStr);
    if (__pendings[id]) { var r = __pendings[id]; delete __pendings[id]; r(cookieStr || ""); }
  };
  globalThis.__cancelBrowser = function (id) {
    if (__pendings[id]) { var r = __pendings[id]; delete __pendings[id]; r(""); }
  };
  // 验证码结果回传（人工输入界面提交/取消时由 Dart 调用）
  globalThis.__resolveVerification = function (id, code) {
    if (__pendings[id]) { var r = __pendings[id]; delete __pendings[id]; r(String(code == null ? "" : code)); }
  };

  // 阻塞式浏览器交互（对齐 legado startBrowserAwait/showBrowser/reLoginView）：
  // 经「同步 XHR → legado://browser」让原生打开可见 WebView，用户关闭时
  // 回传页面 HTML，包装为 StrResponse 返回（书源写法 .body() 取正文）。
  function __openBrowserAwaitHtml(url, title) {
    var resolved = __resolve(url);
    if (!resolved) return __strResponse("", "", 200, "OK", {});
    try {
      var html = __doXhr("legado://browser?url=" + encodeURIComponent(resolved) +
        "&title=" + encodeURIComponent(title || "登录"), { method: "GET" }, null, resolved);
      return __strResponse(resolved, html, 200, "OK", {});
    } catch (e) {
      return __strResponse(resolved, "", 200, "OK", {});
    }
  }

  // ============================ MD5（纯 JS 实现）============================
  function __md5(str) {
    return __bsToHex(__md5bs(__bsFromUtf8(str)));
  }

  // ============================ SHA1（纯 JS 实现）============================
  function __sha1(str) {
    function rotl(n, s) { return (n << s) | (n >>> (32 - s)); }
    function toHex(num) {
      var s = "";
      for (var j = 7; j >= 0; j--) s += ((num >> (j * 4)) & 0x0F).toString(16);
      return s;
    }
    var msg = unescape(encodeURIComponent(str));
    var len = msg.length;
    var wordCount = (((len + 8) >> 6) + 1) * 16;
    var words = new Array(wordCount - 1);
    for (var i = 0; i < len; i++) words[i >> 2] |= msg.charCodeAt(i) << ((i % 4) * 8);
    words[i >> 2] |= 0x80 << ((i % 4) * 8);
    words[wordCount - 2] = Math.floor(len * 8 / 0x100000000);
    words[wordCount - 1] = (len * 8) & 0xFFFFFFFF;
    var h0 = 0x67452301, h1 = 0xEFCDAB89, h2 = 0x98BADCFE, h3 = 0x10325476, h4 = 0xC3D2E1F0;
    for (var i = 0; i < words.length; i += 16) {
      var w = new Array(80);
      for (var j = 0; j < 16; j++) w[j] = words[i + j];
      for (var j = 16; j < 80; j++) w[j] = rotl(w[j - 3] ^ w[j - 8] ^ w[j - 14] ^ w[j - 16], 1);
      var a = h0, b = h1, c = h2, d = h3, e = h4;
      for (var j = 0; j < 80; j++) {
        var f, k;
        if (j < 20) { f = (b & c) | ((~b) & d); k = 0x5A827999; }
        else if (j < 40) { f = b ^ c ^ d; k = 0x6ED9EBA1; }
        else if (j < 60) { f = (b & c) | (b & d) | (c & d); k = 0x8F1BBCDC; }
        else { f = b ^ c ^ d; k = 0xCA62C1D6; }
        var temp = (rotl(a, 5) + f + e + k + w[j]) | 0;
        e = d; d = c; c = rotl(b, 30); b = a; a = temp;
      }
      h0 = (h0 + a) | 0; h1 = (h1 + b) | 0; h2 = (h2 + c) | 0; h3 = (h3 + d) | 0; h4 = (h4 + e) | 0;
    }
    return toHex(h0) + toHex(h1) + toHex(h2) + toHex(h3) + toHex(h4);
  }

  // ============================ SHA256（纯 JS 实现）============================
  function __sha256(str) {
    function rotr(n, s) { return (n >>> s) | (n << (32 - s)); }
    function toHex(num) {
      var s = "";
      for (var j = 7; j >= 0; j--) s += ((num >> (j * 4)) & 0x0F).toString(16);
      return s;
    }
    var K = [
      0x428A2F98, 0x71374491, 0xB5C0FBCF, 0xE9B5DBA5, 0x3956C25B, 0x59F111F1, 0x923F82A4, 0xAB1C5ED5,
      0xD807AA98, 0x12835B01, 0x243185BE, 0x550C7DC3, 0x72BE5D74, 0x80DEB1FE, 0x9BDC06A7, 0xC19BF174,
      0xE49B69C1, 0xEFBE4786, 0x0FC19DC6, 0x240CA1CC, 0x2DE92C6F, 0x4A7484AA, 0x5CB0A9DC, 0x76F988DA,
      0x983E5152, 0xA831C66D, 0xB00327C8, 0xBF597FC7, 0xC6E00BF3, 0xD5A79147, 0x06CA6351, 0x14292967,
      0x27B70A85, 0x2E1B2138, 0x4D2C6DFC, 0x53380D13, 0x650A7354, 0x766A0ABB, 0x81C2C92E, 0x92722C85,
      0xA2BFE8A1, 0xA81A664B, 0xC24B8B70, 0xC76C51A3, 0xD192E819, 0xD6990624, 0xF40E3585, 0x106AA070,
      0x19A4C116, 0x1E376C08, 0x2748774C, 0x34B0BCB5, 0x391C0CB3, 0x4ED8AA4A, 0x5B9CCA4F, 0x682E6FF3,
      0x748F82EE, 0x78A5636F, 0x84C87814, 0x8CC70208, 0x90BEFFFA, 0xA4506CEB, 0xBEF9A3F7, 0xC67178F2
    ];
    var msg = unescape(encodeURIComponent(str));
    var len = msg.length;
    var bitLen = len * 8;
    var wordCount = (((len + 8) >> 6) + 1) * 16;
    var words = new Array(wordCount - 1);
    for (var i = 0; i < len; i++) words[i >> 2] |= msg.charCodeAt(i) << ((3 - (i % 4)) * 8);
    words[i >> 2] |= 0x80 << ((3 - (i % 4)) * 8);
    words[wordCount - 2] = Math.floor(bitLen / 0x100000000);
    words[wordCount - 1] = bitLen & 0xFFFFFFFF;
    var h0 = 0x6A09E667, h1 = 0xBB67AE85, h2 = 0x3C6EF372, h3 = 0xA54FF53A;
    var h4 = 0x510E527F, h5 = 0x9B05688C, h6 = 0x1F83D9AB, h7 = 0x5BE0CD19;
    for (var i = 0; i < words.length; i += 16) {
      var w = new Array(64);
      for (var j = 0; j < 16; j++) w[j] = words[i + j];
      for (var j = 16; j < 64; j++) {
        var s0 = rotr(w[j - 15], 7) ^ rotr(w[j - 15], 18) ^ (w[j - 15] >>> 3);
        var s1 = rotr(w[j - 2], 17) ^ rotr(w[j - 2], 19) ^ (w[j - 2] >>> 10);
        w[j] = (w[j - 16] + s0 + w[j - 7] + s1) | 0;
      }
      var a = h0, b = h1, c = h2, d = h3, e = h4, f = h5, g = h6, h = h7;
      for (var j = 0; j < 64; j++) {
        var S1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
        var ch = (e & f) ^ ((~e) & g);
        var temp1 = (h + S1 + ch + K[j] + w[j]) | 0;
        var S0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
        var maj = (a & b) ^ (a & c) ^ (b & c);
        var temp2 = (S0 + maj) | 0;
        h = g; g = f; f = e; e = (d + temp1) | 0;
        d = c; c = b; b = a; a = (temp1 + temp2) | 0;
      }
      h0 = (h0 + a) | 0; h1 = (h1 + b) | 0; h2 = (h2 + c) | 0; h3 = (h3 + d) | 0;
      h4 = (h4 + e) | 0; h5 = (h5 + f) | 0; h6 = (h6 + g) | 0; h7 = (h7 + h) | 0;
    }
    return toHex(h0) + toHex(h1) + toHex(h2) + toHex(h3) + toHex(h4) + toHex(h5) + toHex(h6) + toHex(h7);
  }

  // ============================ 字节级哈希 / HMAC ============================
  // 对齐 legado JsEncodeUtils 的 digestHex / digestBase64Str / HMacHex / HMacBase64。
  // 书源 JS 的 java.xxx() 是同步调用，不能用异步的 WebCrypto，故这里用纯 JS 实现。
  function __bsFromUtf8(s) {
    return __bytesToStr(new TextEncoder().encode(String(s == null ? "" : s)));
  }
  function __bytesToStr(bytes) {
    var s = "";
    for (var i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i] & 0xFF);
    return s;
  }
  function __bsToHex(bs) {
    var s = "";
    for (var i = 0; i < bs.length; i++) s += ("0" + (bs.charCodeAt(i) & 0xFF).toString(16)).slice(-2);
    return s;
  }
  function __le32(n) {
    return String.fromCharCode(n & 0xFF, (n >>> 8) & 0xFF, (n >>> 16) & 0xFF, (n >>> 24) & 0xFF);
  }
  function __be32(n) {
    return String.fromCharCode((n >>> 24) & 0xFF, (n >>> 16) & 0xFF, (n >>> 8) & 0xFF, n & 0xFF);
  }
  // MD5 字节级实现：msg 为字节串（每字符 0-255），返回 little-endian 字节串。
  // 循环式标准实现（RFC 1321），按 512-bit 块逐块做 64 轮。
  function __md5bs(msg) {
    var len = msg.length;
    var wordCount = (((len + 8) >> 6) + 1) * 16;
    var M = new Array(wordCount);
    for (var i = 0; i < wordCount; i++) M[i] = 0;
    for (var i = 0; i < len; i++) M[i >> 2] |= msg.charCodeAt(i) << ((i % 4) * 8);
    M[len >> 2] |= 0x80 << ((len % 4) * 8);
    M[wordCount - 2] = len * 8;
    var K = [0xd76aa478,0xe8c7b756,0x242070db,0xc1bdceee,0xf57c0faf,0x4787c62a,0xa8304613,0xfd469501,0x698098d8,0x8b44f7af,0xffff5bb1,0x895cd7be,0x6b901122,0xfd987193,0xa679438e,0x49b40821,0xf61e2562,0xc040b340,0x265e5a51,0xe9b6c7aa,0xd62f105d,0x02441453,0xd8a1e681,0xe7d3fbc8,0x21e1cde6,0xc33707d6,0xf4d50d87,0x455a14ed,0xa9e3e905,0xfcefa3f8,0x676f02d9,0x8d2a4c8a,0xfffa3942,0x8771f681,0x6d9d6122,0xfde5380c,0xa4beea44,0x4bdecfa9,0xf6bb4b60,0xbebfbc70,0x289b7ec6,0xeaa127fa,0xd4ef3085,0x04881d05,0xd9d4d039,0xe6db99e5,0x1fa27cf8,0xc4ac5665,0xf4292244,0x432aff97,0xab9423a7,0xfc93a039,0x655b59c3,0x8f0ccc92,0xffeff47d,0x85845dd1,0x6fa87e4f,0xfe2ce6e0,0xa3014314,0x4e0811a1,0xf7537e82,0xbd3af235,0x2ad7d2bb,0xeb86d391];
    var S = [7,12,17,22,7,12,17,22,7,12,17,22,7,12,17,22,5,9,14,20,5,9,14,20,5,9,14,20,5,9,14,20,4,11,16,23,4,11,16,23,4,11,16,23,4,11,16,23,6,10,15,21,6,10,15,21,6,10,15,21,6,10,15,21];
    var a = 0x67452301, b = 0xefcdab89, c = 0x98badcfe, d = 0x10325476;
    for (var off = 0; off < wordCount; off += 16) {
      var A = a, B = b, C = c, D = d;
      for (var i = 0; i < 64; i++) {
        var f, g;
        if (i < 16) { f = (B & C) | ((~B) & D); g = i; }
        else if (i < 32) { f = (B & D) | (C & (~D)); g = (5 * i + 1) % 16; }
        else if (i < 48) { f = B ^ C ^ D; g = (3 * i + 5) % 16; }
        else { f = C ^ (B | (~D)); g = (7 * i) % 16; }
        f = (f + A + K[i] + M[off + g]) | 0;
        var tmp = (B + ((f << S[i]) | (f >>> (32 - S[i])))) | 0;
        var ob = B, oc = C, od = D;
        A = od; B = tmp; C = ob; D = oc;
      }
      a = (a + A) | 0; b = (b + B) | 0; c = (c + C) | 0; d = (d + D) | 0;
    }
    return __le32(a) + __le32(b) + __le32(c) + __le32(d);
  }
  // SHA-1 字节级实现：msg 为字节串，返回 big-endian 字节串。
  function __sha1bs(msg) {
    var len = msg.length;
    var bitLen = len * 8;
    var wordCount = (((len + 8) >> 6) + 1) * 16;
    var words = new Array(wordCount);
    for (var i = 0; i < wordCount; i++) words[i] = 0;
    for (var i = 0; i < len; i++) words[i >> 2] |= msg.charCodeAt(i) << ((3 - (i % 4)) * 8);
    words[len >> 2] |= 0x80 << ((3 - (len % 4)) * 8);
    words[wordCount - 2] = Math.floor(bitLen / 0x100000000);
    words[wordCount - 1] = bitLen & 0xFFFFFFFF;
    function rotl(n, s) { return (n << s) | (n >>> (32 - s)); }
    var h0 = 0x67452301, h1 = 0xEFCDAB89, h2 = 0x98BADCFE, h3 = 0x10325476, h4 = 0xC3D2E1F0;
    for (var i = 0; i < wordCount; i += 16) {
      var w = new Array(80);
      for (var j = 0; j < 16; j++) w[j] = words[i + j];
      for (var j = 16; j < 80; j++) w[j] = rotl(w[j - 3] ^ w[j - 8] ^ w[j - 14] ^ w[j - 16], 1);
      var a = h0, b = h1, c = h2, d = h3, e = h4;
      for (var j = 0; j < 80; j++) {
        var f, k;
        if (j < 20) { f = (b & c) | ((~b) & d); k = 0x5A827999; }
        else if (j < 40) { f = b ^ c ^ d; k = 0x6ED9EBA1; }
        else if (j < 60) { f = (b & c) | (b & d) | (c & d); k = 0x8F1BBCDC; }
        else { f = b ^ c ^ d; k = 0xCA62C1D6; }
        var temp = (rotl(a, 5) + f + e + k + w[j]) | 0;
        e = d; d = c; c = rotl(b, 30); b = a; a = temp;
      }
      h0 = (h0 + a) | 0; h1 = (h1 + b) | 0; h2 = (h2 + c) | 0; h3 = (h3 + d) | 0; h4 = (h4 + e) | 0;
    }
    return __be32(h0) + __be32(h1) + __be32(h2) + __be32(h3) + __be32(h4);
  }
  // SHA-256 字节级实现：msg 为字节串，返回 big-endian 字节串。
  function __sha256bs(msg) {
    var K = [
      0x428A2F98, 0x71374491, 0xB5C0FBCF, 0xE9B5DBA5, 0x3956C25B, 0x59F111F1, 0x923F82A4, 0xAB1C5ED5,
      0xD807AA98, 0x12835B01, 0x243185BE, 0x550C7DC3, 0x72BE5D74, 0x80DEB1FE, 0x9BDC06A7, 0xC19BF174,
      0xE49B69C1, 0xEFBE4786, 0x0FC19DC6, 0x240CA1CC, 0x2DE92C6F, 0x4A7484AA, 0x5CB0A9DC, 0x76F988DA,
      0x983E5152, 0xA831C66D, 0xB00327C8, 0xBF597FC7, 0xC6E00BF3, 0xD5A79147, 0x06CA6351, 0x14292967,
      0x27B70A85, 0x2E1B2138, 0x4D2C6DFC, 0x53380D13, 0x650A7354, 0x766A0ABB, 0x81C2C92E, 0x92722C85,
      0xA2BFE8A1, 0xA81A664B, 0xC24B8B70, 0xC76C51A3, 0xD192E819, 0xD6990624, 0xF40E3585, 0x106AA070,
      0x19A4C116, 0x1E376C08, 0x2748774C, 0x34B0BCB5, 0x391C0CB3, 0x4ED8AA4A, 0x5B9CCA4F, 0x682E6FF3,
      0x748F82EE, 0x78A5636F, 0x84C87814, 0x8CC70208, 0x90BEFFFA, 0xA4506CEB, 0xBEF9A3F7, 0xC67178F2
    ];
    var len = msg.length;
    var bitLen = len * 8;
    var wordCount = (((len + 8) >> 6) + 1) * 16;
    var words = new Array(wordCount);
    for (var i = 0; i < wordCount; i++) words[i] = 0;
    for (var i = 0; i < len; i++) words[i >> 2] |= msg.charCodeAt(i) << ((3 - (i % 4)) * 8);
    words[len >> 2] |= 0x80 << ((3 - (len % 4)) * 8);
    words[wordCount - 2] = Math.floor(bitLen / 0x100000000);
    words[wordCount - 1] = bitLen & 0xFFFFFFFF;
    function rotr(n, s) { return (n >>> s) | (n << (32 - s)); }
    var h0 = 0x6A09E667, h1 = 0xBB67AE85, h2 = 0x3C6EF372, h3 = 0xA54FF53A;
    var h4 = 0x510E527F, h5 = 0x9B05688C, h6 = 0x1F83D9AB, h7 = 0x5BE0CD19;
    for (var i = 0; i < wordCount; i += 16) {
      var w = new Array(64);
      for (var j = 0; j < 16; j++) w[j] = words[i + j];
      for (var j = 16; j < 64; j++) {
        var s0 = rotr(w[j - 15], 7) ^ rotr(w[j - 15], 18) ^ (w[j - 15] >>> 3);
        var s1 = rotr(w[j - 2], 17) ^ rotr(w[j - 2], 19) ^ (w[j - 2] >>> 10);
        w[j] = (w[j - 16] + s0 + w[j - 7] + s1) | 0;
      }
      var a = h0, b = h1, c = h2, d = h3, e = h4, f = h5, g = h6, h = h7;
      for (var j = 0; j < 64; j++) {
        var S1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
        var ch = (e & f) ^ ((~e) & g);
        var temp1 = (h + S1 + ch + K[j] + w[j]) | 0;
        var S0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
        var maj = (a & b) ^ (a & c) ^ (b & c);
        var temp2 = (S0 + maj) | 0;
        h = g; g = f; f = e; e = (d + temp1) | 0;
        d = c; c = b; b = a; a = (temp1 + temp2) | 0;
      }
      h0 = (h0 + a) | 0; h1 = (h1 + b) | 0; h2 = (h2 + c) | 0; h3 = (h3 + d) | 0;
      h4 = (h4 + e) | 0; h5 = (h5 + f) | 0; h6 = (h6 + g) | 0; h7 = (h7 + h) | 0;
    }
    return __be32(h0) + __be32(h1) + __be32(h2) + __be32(h3) + __be32(h4) + __be32(h5) + __be32(h6) + __be32(h7);
  }
  function __digestBs(data, algorithm) {
    var a = String(algorithm || "MD5").toUpperCase().replace(/[-_]/g, "");
    var msg = __bsFromUtf8(data);
    if (a === "SHA1") return __sha1bs(msg);
    if (a === "SHA256") return __sha256bs(msg);
    return __md5bs(msg);
  }
  function __hmacBs(data, algorithm, key) {
    var a = String(algorithm || "MD5").toUpperCase().replace(/[-_]/g, "");
    var fn = a === "SHA1" ? __sha1bs : (a === "SHA256" ? __sha256bs : __md5bs);
    var k = __bsFromUtf8(key);
    if (k.length > 64) k = fn(k);
    var ikey = "", okey = "";
    for (var i = 0; i < 64; i++) {
      var kc = i < k.length ? k.charCodeAt(i) : 0;
      ikey += String.fromCharCode(kc ^ 0x36);
      okey += String.fromCharCode(kc ^ 0x5c);
    }
    return fn(okey + fn(ikey + __bsFromUtf8(data)));
  }

  // ============================ java ============================
  function __argString(args) {
    return Array.prototype.map.call(args, function (a) {
      if (typeof a === "string") return a;
      try { return JSON.stringify(a); } catch (e) { return String(a); }
    }).join(" ");
  }

  var java = {
    // 日志 / 提示
    log: function () { __state.logs.push(__argString(arguments)); },
    toast: function (msg) { var s = String(msg == null ? "" : msg); __state.toasts.push(s); __state.logs.push(s); },
    longToast: function (msg) { var s = String(msg == null ? "" : msg); __state.toasts.push(s); __state.logs.push(s); },

    // 网络
    ajax: function (url, options) {
      var p = __parseUrlOptions(url, options);
      return __doXhr(p.url, p.opt);
    },
    // get/post/head/put/delete：legado 返回 Jsoup Connection.Response
    // （.body() 为 String、.statusCode()/.headers()/.cookies()/.url()）
    get: function (url, headers) {
      // legado 语义：java.get(url, headers) 为网络方法（Jsoup Connection.Response）。
      // 旧书源兼容：单参调用且形态不像 URL 时按缓存读（如 java.get("book_id")）。
      var looksUrl = typeof url === "string" && (
        /^https?:\/\//i.test(url) || /^legado:\/\//.test(url) ||
        url.indexOf('/') >= 0 || url.indexOf('.') >= 0 || url.indexOf(':') >= 0);
      if (arguments.length <= 1 && !looksUrl) {
        var v = cache.get(url);
        return v === null ? "" : v;
      }
      return __jsoupResponse(url, __doXhr(url, { method: "GET", headers: headers || {} }));
    },
    post: function (url, body, headers) {
      return __jsoupResponse(url, __doXhr(url, { method: "POST", body: body, headers: headers || {} }));
    },
    put: function (url, body, headers) {
      return __jsoupResponse(url, __doXhr(url, { method: "PUT", body: body, headers: headers || {} }));
    },
    delete: function (url, headers) {
      return __jsoupResponse(url, __doXhr(url, { method: "DELETE", headers: headers || {} }));
    },
    head: function (url, headers) {
      return __jsoupResponse(url, __doXhr(url, { method: "HEAD", headers: headers || {} }));
    },
    connect: function (url) { return __connect(url); },
    newResponse: function (url) { return __connect(url); },
    getCookie: function (url) { return cookie.getCookie(url); },

    // 编码
    base64Encode: function (str) { return __b64Unicode(str); },
    base64Decode: function (str) {
      try { return __unb64Unicode(str); } catch (e) {
        try { return atob(str); } catch (e2) { return ""; }
      }
    },
    encodeBase64: function (str) { return __b64Unicode(str); },
    decodeBase64: function (str) { return this.base64Decode(str); },
    hexDecodeToString: function (hex) {
      // 书源对「明文 JSON / HTML」与「十六进制响应」都会调用本函数。
      // 仅当整串为合法、偶数长度、可解出 UTF-8 的十六进制时才解码，否则原样返回。
      var raw = String(hex == null ? "" : hex);
      var h = raw.replace(/\s+/g, "");
      if (h.length === 0 || (h.length % 2) !== 0 || /[^0-9a-fA-F]/.test(h)) return raw;
      try {
        var bytes = new Uint8Array(h.length / 2);
        for (var i = 0; i < bytes.length; i++) bytes[i] = parseInt(h.substr(i * 2, 2), 16);
        return new TextDecoder("utf-8", { fatal: true }).decode(bytes);
      } catch (e) { return raw; }
    },
    hexEncodeToString: function (str) { return __bytesToHex(new TextEncoder().encode(str)); },
    stringToHex: function (str) { return __bytesToHex(new TextEncoder().encode(str)); },
    base64DecodeToByteArray: function (str) {
      try { return Array.from(__b64ToBytes(String(str == null ? "" : str))); } catch (e) { return []; }
    },
    hexDecodeToByteArray: function (hex) {
      try { return Array.from(__hexToBytes(String(hex == null ? "" : hex))); } catch (e) { return []; }
    },
    md5Encode: function (str) { return __md5(String(str == null ? "" : str)); },
    md5Encode16: function (str) { return __md5(String(str == null ? "" : str)).substring(8, 24); },
    sha1Encode: function (str) { return __sha1(String(str == null ? "" : str)); },
    sha256Encode: function (str) { return __sha256(String(str == null ? "" : str)); },
    // 摘要：java.digestHex(str, "MD5"|"SHA-1"|"SHA-256") / digestBase64Str
    digestHex: function (data, algorithm) { return __bsToHex(__digestBs(data, algorithm)); },
    digestBase64Str: function (data, algorithm) { return btoa(__digestBs(data, algorithm)); },
    // HMAC：java.HMacHex(data, algorithm, key) / HMacBase64(data, algorithm, key)
    HMacHex: function (data, algorithm, key) { return __bsToHex(__hmacBs(data, algorithm, key)); },
    HMacBase64: function (data, algorithm, key) { return btoa(__hmacBs(data, algorithm, key)); },

    // AES 对称加解密（同步；对齐 legado JsExtensions）
    aesBase64DecodeToString: function (data, key, transformation, iv) {
      return __aesDecryptToString(data, key, transformation, iv);
    },
    aesBase64EncodeToString: function (text, key, transformation, iv) {
      return __aesEncryptToString(text, key, transformation, iv);
    },
    aesDecodeToString: function (data, key, transformation, iv) {
      return __aesDecryptToString(data, key, transformation, iv);
    },
    aesEncodeToString: function (text, key, transformation, iv) {
      return __aesEncryptToString(text, key, transformation, iv);
    },

    // 设备 / UA
    // deviceID 为 legado iOS 专属 API：安卓/本实现抛错，使书源的
    // try{java.deviceID()}catch{java.androidId()} 环境探测走「安卓」分支
    //（大灰狼等聚合源据此选择 book.type / 段落评论等平台适配逻辑）
    deviceID: function () { throw new Error("deviceID 不可用（非 iOS 环境）"); },
''';
