/// JS 片段 6/8（按体积均匀切片，拼接顺序不可变）。
const String legadoBridgeJsPart06 = r'''    var b = bytes.slice();
    while (b.length > 1 && b[0] === 0) b.shift();
    if (b[0] & 0x80) b.unshift(0);
    return b;
  }
  function __nEToPem(key) {
    var parts = String(key).split(",");
    var n = __hexToBytes(parts[0] || "");
    var e = __hexToBytes(parts[1] || "010001");
    var inner = __der(0x02, __intBytes(n)).concat(__der(0x02, __intBytes(e)));
    var seq = __der(0x30, inner);
    var bitStr = [0].concat(seq);
    var algId = __der(0x30, [0x06, 9, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01].concat(__der(0x05, [])));
    var spki = __der(0x30, algId.concat(__der(0x03, bitStr)));
    var b64 = btoa(String.fromCharCode.apply(null, spki));
    var pem = "";
    for (var i = 0; i < b64.length; i += 64) pem += b64.substr(i, 64) + "\n";
    return "-----BEGIN PUBLIC KEY-----\n" + pem + "-----END PUBLIC KEY-----";
  }
  function __normalizePem(key) {
    var k = String(key || "").trim();
    if (k.indexOf("BEGIN") >= 0) return k;
    if (k.indexOf(",") >= 0) return __nEToPem(k);
    return k;
  }
  // book/chapter 对象包装：补齐 legado 原版 BookBean/ChapterBean 的 JS 方法
  // （大灰狼等书源直接调用 book.getVariable / book.setUseReplaceRule / book.readConfig.useReplaceRule）
  globalThis.__wrapBook = function (b) {
    if (!b || typeof b !== "object") return b;
    if (typeof b.getVariable !== "function") {
      b.getVariable = function (key) {
        if (key === undefined || key === null || key === "") return this.variable || "";
        try {
          var o = JSON.parse(this.variable || "{}");
          var v = o[key];
          return v === undefined ? "" : (typeof v === "string" ? v : JSON.stringify(v));
        } catch (e) { return ""; }
      };
      b.setVariable = function (v) { this.variable = (typeof v === "string") ? v : JSON.stringify(v); return true; };
      b.setUseReplaceRule = function (v) {
        this.useReplaceRule = !!v;
        if (!this.readConfig || typeof this.readConfig !== "object") this.readConfig = {};
        this.readConfig.useReplaceRule = !!v;
        return true;
      };
      b.getUseReplaceRule = function () {
        return !!(this.readConfig && this.readConfig.useReplaceRule) || !!this.useReplaceRule;
      };
      b.getName = function () { return this.name || ""; };
      b.getAuthor = function () { return this.author || ""; };
      b.getBookUrl = function () { return this.bookUrl || ""; };
      b.getOrigin = function () { return this.origin || ""; };
      b.getDurChapterIndex = function () { return this.durChapterIndex || 0; };
      b.getDurChapterPos = function () { return this.durChapterPos || 0; };
      b.getDurChapterTitle = function () { return this.durChapterTitle || ""; };
      b.getTotalChapterNum = function () { return this.totalChapterNum || 0; };
      b.getCoverUrl = function () { return this.customCoverUrl || this.coverUrl || ""; };
      b.getCustomCoverUrl = function () { return this.customCoverUrl || ""; };
      b.getIntro = function () { return this.intro || ""; };
      b.getKind = function () { return this.kind || ""; };
      b.getLastChapter = function () { return this.lastChapter || ""; };
      b.getTag = function () { return this.tag || ""; };
      b.getGroup = function () { return this.group || ""; };
      b.getVariableComment = function () { return this.variableComment || ""; };
      if (!b.readConfig || typeof b.readConfig !== "object") b.readConfig = {};
    }
    return b;
  };
  globalThis.__wrapChapter = function (c) {
    if (!c || typeof c !== "object") return c;
    if (typeof c.getChapterUrl !== "function") {
      c.getChapterUrl = function () { return this.url || ""; };
      c.getTitle = function () { return this.title || ""; };
      c.getIndex = function () { return this.index || 0; };
      c.getBookUrl = function () { return this.bookUrl || ""; };
      c.getIsVip = function () { return !!this.isVip; };
      c.getIsPay = function () { return !!this.isPay; };
      c.getIsVolume = function () { return !!this.isVolume; };
      c.getResourceUrl = function () { return this.resourceUrl || ""; };
    }
    return c;
  };

  globalThis.__pendings = {};

  // ---- Rhino（legado 安卓）Java 互操作垫片：V8 无 Java 虚拟机，
  // JavaImporter / importClass / importPackage 给空实现让 jsLib 顶部能安全加载。
  // Packages.* 不再在此处恒返回 null：真实「Java/工具包映射」由 js_packages.dart
  // 的 JsPackages.definition 在 IIFE 末尾注入（见 code 的拼接顺序），已实现的
  // 工具类按原类名映射为等价 JS 值，未实现的类取值为 undefined。----
  function JavaImporterShim() { this.importClass = function () {}; this.importPackage = function () {}; }
  globalThis.JavaImporter = JavaImporterShim;
  globalThis.importClass = function () {};
  globalThis.importPackage = function () {};

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
    remove: function (key) { delete __state.kv[key]; },
    // 内存态缓存（对齐 legado CacheManager.putMemory/getFromMemory，7632/7814 段评限流依赖）
    putMemory: function (key, value) { __state.memory[key] = value; return true; },
    getFromMemory: function (key) {
      return Object.prototype.hasOwnProperty.call(__state.memory, key) ? __state.memory[key] : null;
    },
    removeMemory: function (key) { delete __state.memory[key]; }
  };
  globalThis.cache = cache;

  // ============================ source ============================
  var source = {
    getBookSourceUrl: function () { return __state.meta.url; },
    getBookSourceName: function () { return __state.meta.name; },
    getKey: function () { return __state.meta.url; },
    getOrigin: function () {
      try { var u = new URL(__state.meta.httpUrl || __state.meta.url); return u.origin; } catch (e) { return ""; }
    },
    getBookSourceGroup: function () { return __state.meta.group || ""; },
    getBookSourceComment: function () { return __state.meta.comment || ""; },
    getBookSourceType: function () { return __state.meta.type || 0; },
    getConcurrentRate: function () { return __state.meta.concurrentRate || 0; },
    getEnabledExplore: function () { return !!__state.meta.enabledExplore; },
    getHeader: function () { return __state.meta.header || ""; },
    getLoginUrl: function () { return __state.meta.loginUrl || ""; },
    getJsLib: function () { return __state.meta.jsLib || ""; },
    getBookUrlPattern: function () { return __state.meta.bookUrlPattern || ""; },
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
    loginUi: function () { return ""; },
    // 登录头管理
    getLoginHeader: function () { return __state.loginHeader || ""; },
    putLoginHeader: function (header) { __state.loginHeader = header; return true; },
    removeLoginHeader: function () { __state.loginHeader = ""; return true; },
    // 变量管理（putVariable 是 setVariable 的别名）
    putVariable: function (v) { this.setVariable(v); return true; },
    removeLoginInfo: function () { __state.loginInfo = ""; return true; },
    // 源专属键值（v_{sourceKey}_{key} 命名空间，区别于全局 cache）
    put: function (key, value) {
      __state.kv["v_" + __state.meta.url + "_" + key] = (typeof value === "string") ? value : JSON.stringify(value);
      return value;
    },
    get: function (key) {
      var v = __state.kv["v_" + __state.meta.url + "_" + key];
      if (v === undefined || v === null) return "";
      try { return JSON.parse(v); } catch (e) { return v; }
    },
    // 刷新
    refreshJSLib: function () { return true; },
    putConcurrent: function (value) { __state.meta.concurrentRate = value; return true; },
    // 登录
    login: function () { return true; },
    getLoginJs: function () { return __state.meta.loginUrl || ""; },
    getHeaderMap: function (hasLoginHeader) {
      try {
        var h = __state.meta.header ? JSON.parse(__state.meta.header) : {};
        if (hasLoginHeader && __state.loginHeader) {
          try { Object.assign(h, JSON.parse(__state.loginHeader)); } catch (e) {}
        }
        return h;
      } catch (e) { return {}; }
    }
  };
  globalThis.source = source;
  // Legado 标准全局变量：sourceUrl / sourceName（loadSource/eval 时会覆盖为实际值）
  globalThis.sourceUrl = "";
  globalThis.sourceName = "";
  // Legado 标准全局函数 getKey()：返回书源地址
  globalThis.getKey = function () { return __state.meta.url; };
  // getBookSourceUrl / getBookSourceName 全局别名
  globalThis.getBookSourceUrl = function () { return __state.meta.url; };
  globalThis.getBookSourceName = function () { return __state.meta.name; };

  function putLoginInfo(info) {
    __state.loginInfo = (typeof info === "string") ? info : JSON.stringify(info);
    return true;
  }
  globalThis.putLoginInfo = putLoginInfo;
  globalThis.setLoginInfo = putLoginInfo;
  globalThis.getLoginInfo = function () { return __state.loginInfo || ""; };
  globalThis.removeLoginInfo = function () { __state.loginInfo = ""; return true; };
  // 全局变量函数
  globalThis.getVariable = function (key) { return source.getVariable(key); };
  globalThis.setVariable = function (v) { return source.setVariable(v); };
  globalThis.putVariable = function (v) { return source.putVariable(v); };
  // 全局登录头函数
  globalThis.getLoginHeader = function () { return source.getLoginHeader(); };
  globalThis.putLoginHeader = function (h) { return source.putLoginHeader(h); };
  globalThis.removeLoginHeader = function () { return source.removeLoginHeader(); };

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

  function __doXhr(url, opt, respType, cookieUrl) {
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
      if (!__hasHeader(headers, "Content-Type")) {
        // 对齐 legado AnalyzeUrl.executeStrRequest：body 为 JSON 时走 postJson
        // （application/json），否则按表单编码（postForm）
        var t = bodyStr.trim();
        headers["Content-Type"] = (t.indexOf("{") === 0 || t.indexOf("[") === 0)
            ? "application/json"
            : "application/x-www-form-urlencoded";
      }
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
    // 内部协议（legado://browser 等）需把 Cookie 归属到真实页面 URL，
    // 由调用方通过 cookieUrl 传入，否则回落请求 URL 自身。
    if (sc) __ingestSetCookie(cookieUrl || url, sc);
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

  // ---- StrResponse（对齐 legado io.legado.app.help.http.StrResponse）----
  // body()/url()/code()/message()/headers() 均为方法；toString() 返回正文。
  function __strResponse(url, body, code, message, headers) {
    var b = (body === null || body === undefined) ? "" : String(body);
    return {
      body: function () { return b; },
      url: function () { return String(url == null ? "" : url); },
      code: function () { return code || 200; },
      message: function () { return message || "OK"; },
      headers: function () { return headers || {}; },
      raw: function () { return b; },
      isSuccessful: function () { return (code || 200) < 400; },
      toString: function () { return b; }
    };
  }

  // ---- Jsoup Connection.Response（对齐 legado java.get/post/head/put/delete）----
  // body()/statusCode()/statusMessage()/headers()/cookies()/url()/charset()
''';
