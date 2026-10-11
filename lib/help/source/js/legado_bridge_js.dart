/// 注入到无头 WebView（V8）中的 legado 兼容桥。
///
/// 对齐 legado（legado/app/src/main/java/io/legado/app/help/JsExtensions.kt
/// 与 AnalyzeUrl / AnalyzeRule）在书源脚本里使用的运行时环境：
///
///   * 全局对象：java / cookie / source / book / cache / result / key / page / baseUrl
///   * java.ajax / get / post / connect —— 以「同步 XHR」实现，由原生
///     shouldInterceptRequest 接管发请求（绕过 CORS、统一 Cookie/编码）。
///   * source.getVariable/setVariable/getLoginInfo/putLoginInfo
///   * cookie.getCookie/setCookie/removeCookie/getKey
///   * cache / java.put / java.get 跨阶段键值
///   * 编码：base64、hex；时间格式化；deviceID/androidId；UA
///   * startBrowser* / showBrowser* / reLoginView —— 走原生可见 WebView 交互登录
///
/// 该脚本在每个书源的无头 WebView 创建后于「全局作用域」执行一次；
/// 书源的 jsLib / loginUrl 随后也在全局作用域执行（定义全局函数）。
class LegadoBridgeJs {
  static const String code = r'''
(function () {
  if (globalThis.__legadoBridgeReady) return;
  globalThis.__legadoBridgeReady = true;

  var __state = {
    meta: { url: "", name: "", httpUrl: "" },
    variable: "",
    variableComment: "",
    lastUpdateTime: 0,
    loginInfo: "",
    kv: {},
    cookies: {},
    logs: [],
    toasts: [],
    hosts: [],
    browser: [],
    deviceId: "",
    ua: (typeof navigator !== "undefined" && navigator.userAgent) ? navigator.userAgent :
        "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"
  };
  globalThis.__state = __state;
  globalThis.__pendings = {};

  // ---- Rhino（legado 安卓）Java 互操作垫片：V8 无 Java，
  // 让 jsLib 顶部的 JavaImporter/CompatibilityUtils 能安全加载；
  // 真正访问 Packages.xxx 的分支会抛错并被书源自身 try/catch 捕获后回退。----
  function JavaImporterShim() { this.importClass = function () {}; this.importPackage = function () {}; }
  globalThis.JavaImporter = JavaImporterShim;
  globalThis.importClass = function () {};
  globalThis.importPackage = function () {};
  // 任意 Packages.xxx 取值返回 null：hasJavaClass 判定为 false、new Packages.x() 抛错（被捕获）
  globalThis.Packages = new Proxy({}, { get: function () { return null; } });

  function __hostOf(url) {
    if (!url) return "";
    var s = String(url).trim();
    try {
      if (/^https?:\/\//i.test(s)) {
        return new URL(s).host.replace(/:\d+$/, "");
      }
      if (s.indexOf("/") < 0 && s.indexOf(".") >= 0) {
        return s.replace(/:\d+$/, "").replace(/^\/+/, "");
      }
    } catch (e) {}
    return s.replace(/^https?:\/\//i, "").replace(/^\/+/, "").split("/")[0].replace(/:\d+$/, "");
  }

  function __matchCookieHost(host) {
    if (!host) return "";
    if (__state.cookies[host]) return host;
    var keys = Object.keys(__state.cookies);
    for (var i = 0; i < keys.length; i++) {
      var k = keys[i];
      if (host === k || host.endsWith("." + k) || k.endsWith("." + host)) return k;
    }
    return "";
  }

  function __parseCookiePairs(str) {
    var out = {};
    String(str || "").split(/;|\n/).forEach(function (part) {
      var p = part.trim();
      if (!p) return;
      var idx = p.indexOf("=");
      if (idx <= 0) return;
      var name = p.substring(0, idx).trim();
      if (/^(path|domain|expires|max-age|secure|httponly|samesite)$/i.test(name)) return;
      out[name] = p.substring(idx + 1).trim();
    });
    return out;
  }

  function __ingestSetCookie(url, setCookieHeader) {
    if (!setCookieHeader) return;
    var host = __hostOf(url);
    var jar = __parseCookiePairs(__state.cookies[host] || "");
    var fresh = __parseCookiePairs(setCookieHeader);
    Object.keys(fresh).forEach(function (k) { jar[k] = fresh[k]; });
    __state.cookies[host] = Object.keys(jar).map(function (k) { return k + "=" + jar[k]; }).join("; ");
  }

  function __resolve(url, base) {
    var s = String(url == null ? "" : url).trim();
    if (!s) return s;
    if (/^https?:\/\//i.test(s) || s.indexOf("data:") === 0 || s.indexOf("javascript:") === 0) return s;
    if (s.indexOf("//") === 0) return "https:" + s;
    var b = base || __state.meta.httpUrl || "";
    try {
      if (b) return new URL(s, b).toString();
    } catch (e) {}
    return s;
  }

  function __b64Unicode(str) {
    var bytes = new TextEncoder().encode(String(str));
    var bin = "";
    for (var i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
    return btoa(bin);
  }
  function __unb64Unicode(str) {
    var bin = atob(String(str));
    var bytes = new Uint8Array(bin.length);
    for (var i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
    return new TextDecoder("utf-8").decode(bytes);
  }
  function __hexToBytes(hex) {
    var h = String(hex).replace(/[^0-9a-fA-F]/g, "");
    var out = new Uint8Array(Math.floor(h.length / 2));
    for (var i = 0; i < out.length; i++) out[i] = parseInt(h.substr(i * 2, 2), 16);
    return out;
  }
  function __bytesToHex(bytes) {
    var s = "";
    for (var i = 0; i < bytes.length; i++) s += ("0" + bytes[i].toString(16)).slice(-2);
    return s;
  }

  // ---- AES（基于注入的 aes-js；ECB/CBC + PKCS7，同步）----
  function __b64ToBytes(b64) {
    var bin = atob(String(b64));
    var out = new Uint8Array(bin.length);
    for (var i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out;
  }
  // 用标准 TextEncoder/Decoder（aes-js 自带 utf8 工具对 4 字节字符处理有缺陷）
  function __utf8ToBytes(s) {
    return new Uint8Array(new TextEncoder().encode(String(s)));
  }
  function __bytesToUtf8(b) {
    return new TextDecoder("utf-8").decode(b);
  }
  function __aesKeyBytes(key) {
    var kb = __utf8ToBytes(String(key));
    var sizes = [16, 24, 32];
    for (var i = 0; i < sizes.length; i++) {
      if (kb.length <= sizes[i]) {
        var out = new Uint8Array(sizes[i]);
        out.set(kb);
        return out;
      }
    }
    return Uint8Array.from(kb.slice(0, 32));
  }
  function __aesIv(iv) {
    var b = __utf8ToBytes(String(iv || ""));
    var out = new Uint8Array(16);
    out.set(b.slice(0, 16));
    return out;
  }
  function __unpadPkcs7(bytes) {
    try {
      var p = bytes[bytes.length - 1];
      if (p > 0 && p <= 16) {
        for (var i = bytes.length - p; i < bytes.length; i++) {
          if (bytes[i] !== p) return bytes;
        }
        return bytes.slice(0, bytes.length - p);
      }
    } catch (e) {}
    return bytes;
  }
  function __aesDecryptToString(data, key, transformation, iv) {
    var cipher = __b64ToBytes(data);
    var kb = __aesKeyBytes(key);
    var mode = String(transformation || "AES/ECB/PKCS7Padding").toUpperCase();
    var dec;
    if (mode.indexOf("CBC") >= 0) {
      dec = new aesjs.ModeOfOperation.cbc(kb, __aesIv(iv)).decrypt(cipher);
    } else {
      dec = new aesjs.ModeOfOperation.ecb(kb).decrypt(cipher);
    }
    dec = __unpadPkcs7(dec);
    return __bytesToUtf8(dec);
  }
  function __aesEncryptToString(text, key, transformation, iv) {
    var kb = __aesKeyBytes(key);
    var data = __utf8ToBytes(String(text));
    var pad = 16 - (data.length % 16);
    var padded = new Uint8Array(data.length + pad);
    padded.set(data);
    for (var i = data.length; i < padded.length; i++) padded[i] = pad;
    var mode = String(transformation || "AES/ECB/PKCS7Padding").toUpperCase();
    var enc;
    if (mode.indexOf("CBC") >= 0) {
      enc = new aesjs.ModeOfOperation.cbc(kb, __aesIv(iv)).encrypt(padded);
    } else {
      enc = new aesjs.ModeOfOperation.ecb(kb).encrypt(padded);
    }
    var bin = "";
    for (var j = 0; j < enc.length; j++) bin += String.fromCharCode(enc[j]);
    return btoa(bin);
  }

  // ============================ cookie ============================
  var cookie = {
    getCookie: function (url) {
      var host = __matchCookieHost(__hostOf(url));
      return host ? (__state.cookies[host] || "") : "";
    },
    setCookie: function (url, cookieStr) {
      var host = __hostOf(url);
      var jar = __parseCookiePairs(__state.cookies[host] || "");
      var add = __parseCookiePairs(cookieStr);
      Object.keys(add).forEach(function (k) { jar[k] = add[k]; });
      __state.cookies[host] = Object.keys(jar).map(function (k) { return k + "=" + jar[k]; }).join("; ");
      return true;
    },
    removeCookie: function (url) {
      var host = __hostOf(url);
      var k = __matchCookieHost(host);
      if (k) delete __state.cookies[k];
      return true;
    },
    getKey: function (url, name) {
      var c = this.getCookie(url);
      var m = String(c).match(new RegExp("(?:^|;\\s*)" + name + "=([^;]*)"));
      return m ? m[1] : "";
    },
    replaceCookie: function (url, c) { return this.setCookie(url, c); }
  };
  globalThis.cookie = cookie;

  // ============================ cache ============================
  var cache = {
    get: function (key) {
      var v = __state.kv[key];
      if (v === undefined || v === null) return null;
      try { return JSON.parse(v); } catch (e) { return v; }
    },
    put: function (key, value) {
      __state.kv[key] = (typeof value === "string") ? value : JSON.stringify(value);
      return true;
    },
    remove: function (key) { delete __state.kv[key]; }
  };
  globalThis.cache = cache;

  // ============================ source ============================
  var source = {
    getBookSourceUrl: function () { return __state.meta.url; },
    getBookSourceName: function () { return __state.meta.name; },
    getKey: function () { return __state.meta.url; },
    // 变量注释 / 更新时间（部分订阅源以属性方式访问）
    get variableComment() { return __state.variableComment || ""; },
    get lastUpdateTime() { return __state.lastUpdateTime || 0; },
    getVariable: function (key) {
      if (key === undefined || key === null || key === "") return __state.variable;
      try {
        var o = JSON.parse(__state.variable || "{}");
        var v = o[key];
        return v === undefined ? "" : (typeof v === "string" ? v : JSON.stringify(v));
      } catch (e) { return ""; }
    },
    setVariable: function (v) {
      __state.variable = (typeof v === "string") ? v : JSON.stringify(v);
      return __state.variable;
    },
    getLoginInfo: function () { return __state.loginInfo || ""; },
    getLoginInfoMap: function () {
      try { return JSON.parse(__state.loginInfo || "{}"); } catch (e) { return {}; }
    },
    setLoginInfo: function (v) {
      __state.loginInfo = (typeof v === "string") ? v : JSON.stringify(v);
      return true;
    },
    putLoginInfo: function (v) {
      __state.loginInfo = (typeof v === "string") ? v : JSON.stringify(v);
      return true;
    },
    getCookie: function (url) { return cookie.getCookie(url); },
    setCookie: function (url, c) { return cookie.setCookie(url, c); },
    removeCookie: function (url) { return cookie.removeCookie(url); },
    // 移除登录头（清空登录信息与由登录派生的状态）
    removeLoginHeader: function () {
      __state.loginInfo = "";
      return true;
    },
    getCookieStore: function () { return cookie; },
    // loginUi：legado 安卓版中为方法，书源常用 typeof source.loginUi == 'function' 判断平台
    loginUi: function () { return ""; }
  };
  globalThis.source = source;

  function putLoginInfo(info) {
    __state.loginInfo = (typeof info === "string") ? info : JSON.stringify(info);
    return true;
  }
  globalThis.putLoginInfo = putLoginInfo;
  globalThis.setLoginInfo = putLoginInfo;

  // 默认的 getArgument/setArgument（书源 jsLib 通常会自带；缺失时兜底）
  if (typeof globalThis.getArgument !== "function") {
    globalThis.getArgument = function (key) {
      var o = {};
      try { o = JSON.parse(__state.variable || "{}"); } catch (e) { o = {}; }
      return o[key];
    };
  }
  if (typeof globalThis.setArgument !== "function") {
    globalThis.setArgument = function (key, value) {
      var o = {};
      try { o = JSON.parse(__state.variable || "{}"); } catch (e) { o = {}; }
      o[key] = value;
      __state.variable = JSON.stringify(o);
      return __state.variable;
    };
  }
  // getArguments（复数）：从 JSON 字符串或对象中按键取值，jsLib 通常自带，此处兜底
  if (typeof globalThis.getArguments !== "function") {
    globalThis.getArguments = function (openArgument, key) {
      try {
        var o = (typeof openArgument === "string") ? JSON.parse(openArgument || "{}") : (openArgument || {});
        var v = o[key];
        if (v === undefined || v === null) return "";
        return (typeof v === "string") ? v : JSON.stringify(v);
      } catch (e) { return ""; }
    };
  }
  if (typeof globalThis.setArguments !== "function") {
    globalThis.setArguments = function (openArgument, key, value) {
      try {
        var o = (typeof openArgument === "string") ? JSON.parse(openArgument || "{}") : (openArgument || {});
        o[key] = value;
        return JSON.stringify(o);
      } catch (e) { return openArgument; }
    };
  }
  // 全局 host 兜底（jsLib 通常会定义 var host = [...]；若未定义则为空数组）
  if (typeof globalThis.host === "undefined") {
    globalThis.host = [];
  }

  // ============================ 网络（同步 XHR，原生拦截） ============================
  function __parseUrlOptions(arg, extra) {
    var url = arg, opt = { method: "GET", headers: {}, body: null };
    if (typeof arg === "object" && arg !== null) {
      url = arg.url;
      if (arg.method) opt.method = String(arg.method).toUpperCase();
      if (arg.headers) Object.assign(opt.headers, arg.headers);
      if (arg.body !== undefined && arg.body !== null) opt.body = arg.body;
      if (arg.data !== undefined && arg.data !== null) opt.body = arg.data;
      if (arg.webView) opt.webView = true;
    } else if (typeof arg === "string") {
      var comma = arg.indexOf(",{");
      if (comma >= 0) {
        url = arg.substring(0, comma);
        try {
          var o = JSON.parse(arg.substring(comma + 1));
          if (o.method) opt.method = String(o.method).toUpperCase();
          if (o.headers) Object.assign(opt.headers, o.headers);
          if (o.body !== undefined && o.body !== null) opt.body = o.body;
          if (o.charset) opt.charset = o.charset;
          if (o.webView) opt.webView = true;
        } catch (e) {}
      }
      var m = /,(POST|GET|PUT|DELETE)(?::([\s\S]*))?$/i.exec(url);
      if (m) { url = url.substring(0, m.index); opt.method = m[1].toUpperCase(); if (m[2]) opt.body = m[2]; }
    }
    if (extra && typeof extra === "object") {
      if (extra.method) opt.method = String(extra.method).toUpperCase();
      if (extra.headers) Object.assign(opt.headers, extra.headers);
      if (extra.body !== undefined && extra.body !== null) opt.body = extra.body;
    }
    return { url: url, opt: opt };
  }

  function __doXhr(url, opt, respType) {
    url = __resolve(url);
    var method = opt.method || "GET";
    var headers = {};
    Object.keys(opt.headers || {}).forEach(function (k) {
      if (opt.headers[k] !== undefined && opt.headers[k] !== null) headers[k] = String(opt.headers[k]);
    });
    var bodyStr = null;
    if (opt.body !== undefined && opt.body !== null) {
      bodyStr = (typeof opt.body === "string") ? opt.body : JSON.stringify(opt.body);
    }
    if (bodyStr !== null && method !== "GET" && method !== "HEAD") {
      headers["X-Legado-Body"] = __b64Unicode(bodyStr);
      if (!__hasHeader(headers, "Content-Type")) headers["Content-Type"] = "application/x-www-form-urlencoded";
    }
    if (!__hasHeader(headers, "Cookie") && !__hasHeader(headers, "cookie")) {
      var c = cookie.getCookie(url);
      if (c) headers["Cookie"] = c;
    }
    var x = new XMLHttpRequest();
    x.open(method, url, false);
    Object.keys(headers).forEach(function (k) {
      try { x.setRequestHeader(k, headers[k]); } catch (e) {}
    });
    if (respType === "arraybuffer") x.responseType = "arraybuffer";
    x.send(bodyStr);
    var sc = null;
    try { sc = x.getResponseHeader("X-Set-Cookie"); } catch (e) {}
    if (sc) __ingestSetCookie(url, sc);
    if (__state.hosts.indexOf(__hostOf(url)) < 0) __state.hosts.push(__hostOf(url));
    if (x.status === 0) throw new Error("网络请求失败: " + url);
    if (x.status >= 400) throw new Error("HTTP " + x.status + " " + url);
    if (respType === "arraybuffer") return x.response;
    return x.responseText;
  }
  function __hasHeader(headers, name) {
    var lk = name.toLowerCase();
    return Object.keys(headers).some(function (k) { return k.toLowerCase() === lk; });
  }

  function __connect(url) {
    var conn = {
      __url: url, __method: "GET", __headers: {}, __body: null,
      headers: function (h) { if (h) Object.keys(h).forEach((k) => { this.__headers[k] = h[k]; }); return this; },
      addHeader: function (k, v) { this.__headers[k] = v; return this; },
      header: function (k, v) { this.__headers[k] = v; return this; },
      method: function (m) { this.__method = String(m).toUpperCase(); return this; },
      setBody: function (b) { this.__body = b; return this; },
      body: function (b) { this.__body = b; this.__method = "POST"; return this; },
      get: function () { this.__method = "GET"; return this; },
      post: function (b) { this.__method = "POST"; if (b !== undefined) this.__body = b; return this; },
      followRedirects: function () { return this; },
      timeout: function () { return this; },
      execute: function () {
        var text = __doXhr(this.__url, { method: this.__method, headers: this.__headers, body: this.__body });
        return {
          code: 200,
          url: this.__url,
          body: function () { return { string: function () { return text; }, bytes: function () { return new TextEncoder().encode(text); }, text: function () { return text; } }; },
          headers: {},
          header: function () { return null; },
          raw: text
        };
      }
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

  // ============================ MD5（纯 JS 实现）============================
  function __md5(str) {
    function rotl(n, s) { return (n << s) | (n >>> (32 - s)); }
    function toHex(num) {
      var s = "";
      for (var j = 0; j < 4; j++) s += ((num >> (j * 8 + 4)) & 0x0F).toString(16) + ((num >> (j * 8)) & 0x0F).toString(16);
      return s;
    }
    var msg = unescape(encodeURIComponent(str));
    var len = msg.length;
    var wordCount = (((len + 8) >> 6) + 1) * 16;
    var words = new Array(wordCount - 1);
    for (var i = 0; i < len; i++) words[i >> 2] |= msg.charCodeAt(i) << ((i % 4) * 8);
    words[i >> 2] |= 0x80 << ((i % 4) * 8);
    words[wordCount - 2] = len * 8;
    var a = 1732584193, b = -271733879, c = -1732584194, d = 271733878;
    for (var i = 0; i < words.length; i += 16) {
      var oa = a, ob = b, oc = c, od = d;
      a = __md5ff(a, b, c, d, words[i + 0], 7, -680876936);
      d = __md5ff(d, a, b, c, words[i + 1], 12, -389564586);
      c = __md5ff(c, d, a, b, words[i + 2], 17, 606105819);
      b = __md5ff(b, c, d, a, words[i + 3], 22, -1044525330);
      a = __md5ff(a, b, c, d, words[i + 4], 7, -176418897);
      d = __md5ff(d, a, b, c, words[i + 5], 12, 1200080426);
      c = __md5ff(c, d, a, b, words[i + 6], 17, -1473231341);
      b = __md5ff(b, c, d, a, words[i + 7], 22, -45705983);
      a = __md5ff(a, b, c, d, words[i + 8], 7, 1770035416);
      d = __md5ff(d, a, b, c, words[i + 9], 12, -1958414417);
      c = __md5ff(c, d, a, b, words[i + 10], 17, -42063);
      b = __md5ff(b, c, d, a, words[i + 11], 22, -1990404162);
      a = __md5ff(a, b, c, d, words[i + 12], 7, 1804603682);
      d = __md5ff(d, a, b, c, words[i + 13], 12, -40341101);
      c = __md5ff(c, d, a, b, words[i + 14], 17, -1502002290);
      b = __md5ff(b, c, d, a, words[i + 15], 22, 1236535329);
      a = __md5gg(a, b, c, d, words[i + 1], 5, -165796510);
      d = __md5gg(d, a, b, c, words[i + 6], 9, -1069501632);
      c = __md5gg(c, d, a, b, words[i + 11], 14, 643717713);
      b = __md5gg(b, c, d, a, words[i + 0], 20, -373897302);
      a = __md5gg(a, b, c, d, words[i + 5], 5, -701558691);
      d = __md5gg(d, a, b, c, words[i + 10], 9, 38016083);
      c = __md5gg(c, d, a, b, words[i + 15], 14, -660478335);
      b = __md5gg(b, c, d, a, words[i + 4], 20, -405537848);
      a = __md5gg(a, b, c, d, words[i + 9], 5, 568446438);
      d = __md5gg(d, a, b, c, words[i + 14], 9, -1019803690);
      c = __md5gg(c, d, a, b, words[i + 3], 14, -187363961);
      b = __md5gg(b, c, d, a, words[i + 8], 20, 1163531501);
      a = __md5gg(a, b, c, d, words[i + 13], 5, -1444681467);
      d = __md5gg(d, a, b, c, words[i + 2], 9, -51403784);
      c = __md5gg(c, d, a, b, words[i + 7], 14, 1735328473);
      b = __md5gg(b, c, d, a, words[i + 12], 20, -1926607734);
      a = __md5hh(a, b, c, d, words[i + 5], 4, -378558);
      d = __md5hh(d, a, b, c, words[i + 8], 11, -2022574463);
      c = __md5hh(c, d, a, b, words[i + 11], 16, 1839030562);
      b = __md5hh(b, c, d, a, words[i + 14], 23, -35309556);
      a = __md5hh(a, b, c, d, words[i + 1], 4, -1530992060);
      d = __md5hh(d, a, b, c, words[i + 4], 11, 1272893353);
      c = __md5hh(c, d, a, b, words[i + 7], 16, -155497632);
      b = __md5hh(b, c, d, a, words[i + 10], 23, -1094730640);
      a = __md5hh(a, b, c, d, words[i + 13], 4, 681279174);
      d = __md5hh(d, a, b, c, words[i + 0], 11, -358537222);
      c = __md5hh(c, d, a, b, words[i + 3], 16, -722521979);
      b = __md5hh(b, c, d, a, words[i + 6], 23, 76029189);
      a = __md5hh(a, b, c, d, words[i + 9], 4, -640364487);
      d = __md5hh(d, a, b, c, words[i + 12], 11, -421815835);
      c = __md5hh(c, d, a, b, words[i + 15], 16, 530742525);
      b = __md5hh(b, c, d, a, words[i + 2], 23, -995338651);
      a = __md5ii(a, b, c, d, words[i + 0], 6, -198630844);
      d = __md5ii(d, a, b, c, words[i + 7], 10, 1126891415);
      c = __md5ii(c, d, a, b, words[i + 14], 15, -1416354905);
      b = __md5ii(b, c, d, a, words[i + 5], 21, -57434055);
      a = __md5ii(a, b, c, d, words[i + 12], 6, 1700485571);
      d = __md5ii(d, a, b, c, words[i + 3], 10, -1894986606);
      c = __md5ii(c, d, a, b, words[i + 10], 15, -1051523);
      b = __md5ii(b, c, d, a, words[i + 1], 21, -2054922799);
      a = __md5ii(a, b, c, d, words[i + 8], 6, 1873313359);
      d = __md5ii(d, a, b, c, words[i + 15], 10, -30611744);
      c = __md5ii(c, d, a, b, words[i + 6], 15, -1560198380);
      b = __md5ii(b, c, d, a, words[i + 13], 21, 1309151649);
      a = __md5ii(a, b, c, d, words[i + 4], 6, -145523070);
      d = __md5ii(d, a, b, c, words[i + 11], 10, -1120210379);
      c = __md5ii(c, d, a, b, words[i + 2], 15, 718787259);
      b = __md5ii(b, c, d, a, words[i + 9], 21, -343485551);
      a = (a + oa) | 0; b = (b + ob) | 0; c = (c + oc) | 0; d = (d + od) | 0;
    }
    return toHex(a) + toHex(b) + toHex(c) + toHex(d);
  }
  function __md5cmn(q, a, b, x, s, t) { return __md5add(rotl(__md5add(__md5add(a, q), __md5add(x, t)), s), b); }
  function __md5ff(a, b, c, d, x, s, t) { return __md5cmn((b & c) | ((~b) & d), a, b, x, s, t); }
  function __md5gg(a, b, c, d, x, s, t) { return __md5cmn((b & d) | (c & (~d)), a, b, x, s, t); }
  function __md5hh(a, b, c, d, x, s, t) { return __md5cmn(b ^ c ^ d, a, b, x, s, t); }
  function __md5ii(a, b, c, d, x, s, t) { return __md5cmn(c ^ (b | (~d)), a, b, x, s, t); }
  function __md5add(a, b) { var x = (a & 0xFFFF) + (b & 0xFFFF); var y = (a >> 16) + (b >> 16) + (x >> 16); return (y << 16) | (x & 0xFFFF); }

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
    get: function (url, headers) {
      return __doXhr(url, { method: "GET", headers: headers || {} });
    },
    post: function (url, body, headers) {
      return __doXhr(url, { method: "POST", body: body, headers: headers || {} });
    },
    put: function (url, body, headers) {
      return __doXhr(url, { method: "PUT", body: body, headers: headers || {} });
    },
    delete: function (url, headers) {
      return __doXhr(url, { method: "DELETE", headers: headers || {} });
    },
    head: function (url, headers) {
      return __doXhr(url, { method: "HEAD", headers: headers || {} });
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
    md5Encode: function (str) { return __md5(String(str == null ? "" : str)); },

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
    deviceID: function () { return __state.deviceId; },
    androidId: function () { return __state.deviceId; },
    getWebViewUA: function () { return __state.ua; },
    getAppVariant: function () { return "android"; },

    // 时间
    timeFormat: function (time, pattern) { return __timeFormat(time, pattern, false); },
    timeFormatUTC: function (time, pattern) { return __timeFormat(time, pattern, true); },

    // 跨阶段键值
    put: function (k, v) { cache.put(k, v); return true; },
    get: function (k) { var v = cache.get(k); return v === null ? "" : v; },
    contains: function (k) { return Object.prototype.hasOwnProperty.call(__state.kv, k); },
    remove: function (k) { cache.remove(k); },

    // 书源相关
    refreshExplore: function () { return true; },
    refreshBookToc: function () { return true; },
    refreshBook: function () { return true; },

    // 浏览器登录
    startBrowser: function (url, title) { return __openBrowser(url, title, false); },
    startBrowserDp: function (url, title) { return __openBrowser(url, title, false); },
    startBrowserAwait: function (url, title) { return __openBrowser(url, title, true); },
    showBrowser: function (url, title) { return __openBrowser(url, title, true); },
    showReadingBrowser: function (url, title) { return __openBrowser(url, title, true); },
    reLoginView: function (url) { return __openBrowser(url || "", "登录", true); },

    // 环境探测：轻阅读不可用，需抛错让书源走标准分支
    qread: function () { throw new Error("qread 不可用"); },

    // 对称加密：返回 encrypt/decrypt 对象（对齐 legado JsExtensions.createSymmetricCrypto）
    createSymmetricCrypto: function (transformation, key) {
      var kb = __aesKeyBytes(key);
      var mode = String(transformation || "AES").toUpperCase();
      var useCbc = mode.indexOf("CBC") >= 0;
      return {
        encrypt: function (data) {
          var text = (typeof data === "string") ? data : String(data);
          var dataBytes = __utf8ToBytes(text);
          var pad = 16 - (dataBytes.length % 16);
          var padded = new Uint8Array(dataBytes.length + pad);
          padded.set(dataBytes);
          for (var i = dataBytes.length; i < padded.length; i++) padded[i] = pad;
          var enc;
          if (useCbc) {
            enc = new aesjs.ModeOfOperation.cbc(kb, __aesIv(null)).encrypt(padded);
          } else {
            enc = new aesjs.ModeOfOperation.ecb(kb).encrypt(padded);
          }
          return Array.from(enc);
        },
        decrypt: function (bytes) {
          var data = (bytes instanceof Uint8Array) ? bytes : Uint8Array.from(bytes || []);
          var dec;
          if (useCbc) {
            dec = new aesjs.ModeOfOperation.cbc(kb, __aesIv(null)).decrypt(data);
          } else {
            dec = new aesjs.ModeOfOperation.ecb(kb).decrypt(data);
          }
          dec = __unpadPkcs7(dec);
          return __bytesToUtf8(dec);
        }
      };
    },

    // java.lang / java.net 常见静态调用
    lang: {
      Thread: { sleep: function () {} },
      System: { currentTimeMillis: function () { return Date.now(); }, nanoTime: function () { return Date.now() * 1000000; } },
      String: function (v) { return String(v); },
      Integer: { parseInt: function (v) { return parseInt(v, 10); } }
    },
    net: {
      URLEncoder: { encode: function (s) { return encodeURIComponent(String(s)).replace(/%20/g, "+"); } },
      URLDecoder: { decode: function (s) { return decodeURIComponent(String(s).replace(/\+/g, "%20")); } }
    }
  };
  globalThis.java = java;

  function __pad(n) { return n < 10 ? "0" + n : "" + n; }
  function __timeFormat(time, pattern, utc) {
    if (!time) return "";
    var d;
    if (typeof time === "number" || /^\d+$/.test(String(time))) {
      var n = Number(time);
      if (n < 1e12) n = n * 1000;
      d = new Date(n);
    } else {
      d = new Date(String(time).replace(/-/g, "/"));
    }
    if (isNaN(d.getTime())) return "";
    var p = pattern || "yyyy-MM-dd HH:mm:ss";
    var Y = utc ? d.getUTCFullYear() : d.getFullYear();
    var M = (utc ? d.getUTCMonth() : d.getMonth()) + 1;
    var D = utc ? d.getUTCDate() : d.getDate();
    var H = utc ? d.getUTCHours() : d.getHours();
    var m = utc ? d.getUTCMinutes() : d.getMinutes();
    var s = utc ? d.getUTCSeconds() : d.getSeconds();
    return p
      .replace(/yyyy/g, "" + Y)
      .replace(/yy/g, ("" + Y).slice(-2))
      .replace(/MM/g, __pad(M))
      .replace(/dd/g, __pad(D))
      .replace(/HH/g, __pad(H))
      .replace(/mm/g, __pad(m))
      .replace(/ss/g, __pad(s));
  }

  // 供原生每次求值前重置「瞬态」输出
  globalThis.__resetTransient = function () {
    __state.logs = [];
    __state.toasts = [];
    __state.hosts = [];
    __state.browser = [];
  };

  // 求值结束后汇总输出
  globalThis.__envelope = function (ret, err) {
    if (ret === undefined) {
      try { ret = globalThis.result; } catch (e) { ret = null; }
    }
    var safeRet;
    try { safeRet = (ret === undefined) ? null : ret; } catch (e) { safeRet = String(ret); }
    return JSON.stringify({
      ret: safeRet,
      variable: __state.variable,
      loginInfo: __state.loginInfo,
      kv: __state.kv,
      cookies: __state.cookies,
      logs: __state.logs,
      toasts: __state.toasts,
      hosts: __state.hosts,
      browser: __state.browser,
      error: err ? ((err && err.stack) ? String(err.stack) : String(err)) : null
    });
  };
})();
''';
}
