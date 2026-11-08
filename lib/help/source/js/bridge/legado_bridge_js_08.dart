/// JS 片段 8/8（按体积均匀切片，拼接顺序不可变）。
const String legadoBridgeJsPart08 = r'''    androidId: function () { return __state.deviceId; },
    getWebViewUA: function () { return __state.ua; },
    getAppVariant: function () { return "android"; },

    // 时间
    timeFormat: function (time, pattern) { return __timeFormat(time, pattern, false); },
    timeFormatUTC: function (time, pattern) { return __timeFormat(time, pattern, true); },

    // 跨阶段键值
    put: function (k, v) { cache.put(k, v); return true; },
    remove: function (k) { cache.remove(k); },
    contains: function (k) { return Object.prototype.hasOwnProperty.call(__state.kv, k); },

    // 书源相关
    refreshExplore: function () { return true; },
    refreshBookToc: function () { return true; },
    refreshBook: function () { return true; },

    // 导航类（对齐 legado RssJsExtensions/SourceLoginJsExtensions，经内部协议转交原生）
    // searchBook(key, searchScope)：scope 形如「分组::书源Url」或书源 Url，
    // 用于限定在该书源内搜索（发现页搜索框即此用法）。
    searchBook: function (key, searchScope) {
      try {
        __doXhr("legado://searchbook?key=" + encodeURIComponent(key == null ? "" : key) +
          "&scope=" + encodeURIComponent(searchScope == null ? "" : searchScope), { method: "GET" });
      } catch (e) {}
      return true;
    },
    // open(name, url, title, origin)：login → 打开当前书源登录页；
    // url/webView → 内置浏览器打开；其余名称忽略。
    open: function (name, url, title, origin) {
      try {
        var n = String(name == null ? "" : name).toLowerCase();
        if (n === "login") {
          __doXhr("legado://openlogin?origin=" + encodeURIComponent(origin == null ? "" : origin), { method: "GET" });
        } else if (n === "url" || n === "webview" || n === "browser") {
          if (url) __openBrowser(url, title || "", false);
        }
      } catch (e) {}
      return true;
    },

    // 浏览器登录
    // 非阻塞式：legado 语义为 Unit（发现页 url 型分类常写
    // `{{java.startBrowser(url,title)}}`，求值须为空串而非 Promise）。
    startBrowser: function (url, title) { __openBrowser(url, title, false); },
    startBrowserDp: function (url, title) { __openBrowser(url, title, false); },
    // 阻塞式：用户关闭网页后返回带 body() 的 StrResponse（正文为关闭时页面 HTML）
    startBrowserAwait: function (url, title) { return __openBrowserAwaitHtml(url, title); },
    showBrowser: function (url, title) { return __openBrowserAwaitHtml(url, title); },
    showReadingBrowser: function (url, title) { return __openBrowserAwaitHtml(url, title); },
    reLoginView: function (url) { return __openBrowserAwaitHtml(url || "", "登录"); },

    // 环境探测：轻阅读不可用，需抛错让书源走标准分支
    qread: function () { throw new Error("qread 不可用"); },

    // URL 解析
    getAbsoluteURL: function (base, relative) { return __resolve(relative, base); },
    getRedirectUrl: function (url) { return __resolve(url); },

    // RSA（纯 JS 实现复杂，提供占位让书源 try/catch 回退）
    rsaEncodeToString: function (data, key, transformation) {
      try {
        var crypt = new JSEncrypt();
        crypt.setPublicKey(__normalizePem(key));
        return crypt.encrypt(String(data == null ? "" : data)) || "";
      } catch (e) { return ""; }
    },
    rsaDecodeToString: function (data, key, transformation) {
      try {
        var crypt = new JSEncrypt();
        crypt.setPrivateKey(__normalizePem(key));
        return crypt.decrypt(String(data == null ? "" : data)) || "";
      } catch (e) { return ""; }
    },

    // gzip（WebView 环境下提供占位）
    gzipCompress: function (data) {
      try {
        var bytes = (typeof data === "string") ? new TextEncoder().encode(data) : data;
        var gz = pako.gzip(bytes);
        return btoa(String.fromCharCode.apply(null, gz));
      } catch (e) { return data; }
    },
    gzipDecompress: function (data) {
      try {
        var bytes;
        if (typeof data === "string") {
          var s = data.trim();
          if (/^[0-9A-Za-z+/=]+$/.test(s) && s.length % 4 === 0) {
            var bin = atob(s); bytes = Uint8Array.from(bin, function (c) { return c.charCodeAt(0); });
          } else {
            bytes = new TextEncoder().encode(s);
          }
        } else { bytes = data; }
        var out = pako.ungzip(bytes);
        return new TextDecoder("utf-8").decode(out);
      } catch (e) { return data; }
    },

    // 字体替换（占位）
    replaceFont: function (text, font) {
      try {
        var map = (typeof font === "string") ? JSON.parse(font) : font;
        if (!map) return text;
        var s = String(text == null ? "" : text);
        var out = "";
        for (var i = 0; i < s.length; i++) {
          var c = s[i];
          out += (map[c] !== undefined && map[c] !== null) ? map[c] : c;
        }
        return out;
      } catch (e) { return text; }
    },

    // 下载/分享/打开（走 legado:// 内部协议，原生拦截实现）
    download: function (url) {
      try { return __doXhr("legado://download?url=" + encodeURIComponent(url), { method: "GET" }); }
      catch (e) { return ""; }
    },
    share: function (text) {
      try { return __doXhr("legado://share", { method: "POST", body: String(text == null ? "" : text) }); }
      catch (e) { return false; }
    },
    openUrl: function (url) { __openBrowser(url, "", false); },

    // 编码 / 文本处理
    encodeURI: function (str, enc) {
      try { return encodeURIComponent(String(str)).replace(/%20/g, "+"); } catch (e) { return ""; }
    },
    htmlFormat: function (str) { return String(str == null ? "" : str).replace(/<[^>]+>/g, ""); },
    t2s: function (text) { return __convert(text, __T2S); },
    s2t: function (text) { return __convert(text, __S2T); },

    // 工具
    randomUUID: function () {
      return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, function (c) {
        var r = Math.random() * 16 | 0, v = c === "x" ? r : (r & 0x3 | 0x8);
        return v.toString(16);
      });
    },
    logType: function (any) {
      if (any === null || any === undefined) { java.log("null"); }
      else { java.log(typeof any); }
    },
    toURL: function (urlStr, baseUrl) {
      try { return new URL(urlStr, baseUrl || __state.meta.httpUrl); } catch (e) { return null; }
    },
    toNumChapter: function (s) {
      if (!s) return s;
      var m = String(s).match(/^(\D*?)(\d+)(\D*)$/);
      if (m) return m[1] + parseInt(m[2], 10) + m[3];
      return s;
    },
    strToBytes: function (str, charset) {
      return Array.from(new TextEncoder().encode(String(str == null ? "" : str)));
    },
    bytesToStr: function (bytes, charset) {
      try { return new TextDecoder(charset || "utf-8").decode(Uint8Array.from(bytes || [])); } catch (e) { return ""; }
    },

    // 脚本导入 / 文件缓存（走 legado://file 内部协议，原生文件系统实现）
    importScript: function (path) {
      try { return __doXhr("legado://file?op=read&path=" + encodeURIComponent(path), { method: "GET" }); }
      catch (e) { return ""; }
    },
    cacheFile: function (urlStr, saveTime) {
      try { return __doXhr("legado://file?op=cache&url=" + encodeURIComponent(urlStr), { method: "GET" }); }
      catch (e) { return ""; }
    },
    readTxtFile: function (path, charset) {
      try { return __doXhr("legado://file?op=read&path=" + encodeURIComponent(path), { method: "GET" }); }
      catch (e) { return ""; }
    },
    deleteFile: function (path) {
      try { __doXhr("legado://file?op=delete&path=" + encodeURIComponent(path), { method: "GET" }); return true; }
      catch (e) { return false; }
    },
    // 下载文件到缓存目录，返回相对路径（对齐 legado-E JsExtensions.downloadFile）。
    // 兼容旧签名 downloadFile(hexContent, url)：第二参存在且首参为合法 hex 时按 hex 写入。
    downloadFile: function (url, url2) {
      try {
        if (url2 != null) {
          var hex = String(url == null ? "" : url);
          if (hex.length > 0 && hex.length % 2 === 0 && /^[0-9a-fA-F]+$/.test(hex)) {
            return __doXhr("legado://file?op=writehex&url=" + encodeURIComponent(url2) + "&hex=" + encodeURIComponent(hex), { method: "GET" });
          }
        }
        return __doXhr("legado://file?op=download&url=" + encodeURIComponent(url), { method: "GET" });
      } catch (e) { return ""; }
    },

    // 源信息
    getSource: function () { return source; },
    getTag: function () { return __state.meta.name; },

    // 并发请求（legado 返回 Array<StrResponse>，元素 .body() 取正文）。
    // 串行逐个同步 XHR 会让总耗时等于各请求之和；这里把整批 URL 一次性
    // POST 给原生，由 Dart 侧用 Future.wait 真并发发起，并按入参顺序回传，
    // 既保持返回顺序，又把总耗时压缩到「最慢的那个请求」。
    ajaxAll: function (urlList) {
      var list = Array.isArray(urlList) ? urlList : [];
      if (list.length === 0) return [];
      // 兼容字符串数组与 {url, method, headers, body} 对象数组两种书源写法
      var urls = list.map(function (u) {
        if (typeof u === "string") return { url: u, method: "GET" };
        if (u && typeof u === "object") {
          return {
            url: String(u.url == null ? "" : u.url),
            method: String(u.method || "GET"),
            headers: u.headers || {},
            body: u.body === undefined ? null : u.body
          };
        }
        return { url: String(u), method: "GET" };
      });
      try {
        var raw = __doXhr("legado://ajaxall", { method: "POST", body: JSON.stringify(urls) });
        var arr = JSON.parse(raw);
        if (Array.isArray(arr)) {
          // Future.wait 已保证元素顺序与 urls 一致，逐个还原为 StrResponse
          return arr.map(function (r) {
            return __strResponse(r.url, r.body, r.code, r.message, r.headers || {});
          });
        }
      } catch (e) {}
      // 内部协议异常时逐项如实回报 502（不假装成功，也不退回串行桩）
      return urls.map(function (o) {
        return __strResponse(o.url, "", 502, "Error", {});
      });
    },
    ajaxTestAll: function (urlList, timeout) { return this.ajaxAll(urlList); },

    // WebView 渲染：走 legado://webview 内部协议，用第二个无头 WebView 加载并等 JS 渲染后取源码
    webView: function (html, url, js, cacheFirst) {
      try {
        var target = url || "";
        if (!target) return html || "";
        var rendered = __doXhr("legado://webview?url=" + encodeURIComponent(target), { method: "GET" });
        return rendered || html || "";
      } catch (e) { return html || ""; }
    },
    webViewGetSource: function (html, url, js, sourceRegex, cacheFirst, delayTime) {
      try {
        var target = url || "";
        if (!target) return "";
        return __doXhr("legado://webview?url=" + encodeURIComponent(target), { method: "GET" });
      } catch (e) { return ""; }
    },
    // WebView 重定向 / 资源嗅探（对齐 legado java.webViewGetOverrideUrl）：
    // 交给真实无头 WebView 加载 url，捕获匹配 overrideUrlRegex 的请求地址，
    // 无命中时返回页面最终落地 URL；不再是「直接返回入参 url」的空实现。
    webViewGetOverrideUrl: function (html, url, js, overrideUrlRegex, cacheFirst, delayTime) {
      try {
        var target = url || "";
        if (!target) return html || "";
        var payload = JSON.stringify({
          url: target,
          html: html == null ? "" : String(html),
          js: js == null ? "" : String(js),
          regex: overrideUrlRegex == null ? "" : String(overrideUrlRegex),
          cacheFirst: !!cacheFirst,
          delayMs: Number(delayTime) || 0
        });
        var result = __doXhr("legado://overrideurl", { method: "POST", body: payload });
        return result || "";
      } catch (e) { return ""; }
    },
    // 验证码识别：弹出人工输入界面（对齐 E SourceVerificationHelp.getVerificationResult），
    // 返回 Promise，用户提交后 resolve 输入的字符；未提交/取消 resolve 空串。
    getVerificationCode: function (imageUrl) {
      return new Promise(function (resolve) {
        var id = "v" + Date.now() + Math.floor(Math.random() * 10000);
        __pendings[id] = resolve;
        try {
          if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
            window.flutter_inappwebview.callHandler("legadoVerification", JSON.stringify({
              id: id, imageUrl: String(imageUrl == null ? "" : imageUrl)
            }));
          } else {
            delete __pendings[id]; resolve("");
          }
        } catch (e) { delete __pendings[id]; resolve(""); }
        // 5 分钟无输入自动按空处理，避免 Promise 永久挂起
        setTimeout(function () {
          if (__pendings[id]) { delete __pendings[id]; resolve(""); }
        }, 300000);
      });
    },

    // 字体反爬（占位）
    queryTTF: function (data, useCache) {
      try {
        var b64 = String(data == null ? "" : data);
        // data 为 http 链接时先下载字体文件
        if (/^https?:\/\//i.test(b64)) {
          var bytes = __doXhr(b64, { method: "GET" }, "arraybuffer");
          var bin = new Uint8Array(bytes);
          var binStr = "";
          for (var i = 0; i < bin.length; i++) binStr += String.fromCharCode(bin[i]);
          b64 = btoa(binStr);
        }
        if (!b64) return null;
        var resp = __doXhr("legado://ttf", { method: "POST", body: b64 });
        return JSON.parse(resp);
      } catch (e) { return null; }
    },
    getZipStringContent: function (url, path, charset) {
      try {
        return __doXhr("legado://zip?url=" + encodeURIComponent(url) + "&path=" + encodeURIComponent(path || ""), { method: "GET" });
      } catch (e) { return ""; }
    },
    get7zStringContent: function (url, path, charset) {
      try {
        return __doXhr("legado://zip?kind=7z&url=" + encodeURIComponent(url) + "&path=" + encodeURIComponent(path || ""), { method: "GET" });
      } catch (e) { return ""; }
    },
    getRarStringContent: function (url, path, charset) {
      try {
        return __doXhr("legado://zip?kind=rar&url=" + encodeURIComponent(url) + "&path=" + encodeURIComponent(path || ""), { method: "GET" });
      } catch (e) { return ""; }
    },
    unzipFile: function (zipPath) {
      try {
        // 整包解压到 legado_files/unzip/<md5(名)>，返回相对目录（对齐 E：后续配 getTxtInFolder 使用）
        return __doXhr("legado://zip?op=unarchive&url=" + encodeURIComponent(zipPath), { method: "GET" });
      } catch (e) { return ""; }
    },
    unArchiveFile: function (zipPath) { return this.unzipFile(zipPath); },
    // 7z/rar 整包解压：Android 端走原生 libarchive 兼容实现（commons-compress/junrar），
    // 其余平台抛错让书源 try/catch 走回退分支。
    un7zFile: function (path) {
      try {
        return __doXhr("legado://zip?kind=7z&op=unarchive&url=" + encodeURIComponent(path), { method: "GET" });
      } catch (e) { throw new Error("un7zFile 失败: " + e); }
    },
    unrarFile: function (path) {
      try {
        return __doXhr("legado://zip?kind=rar&op=unarchive&url=" + encodeURIComponent(path), { method: "GET" });
      } catch (e) { throw new Error("unrarFile 失败: " + e); }
    },

    // ===== 阅读/主题/媒体接口（对齐 legado-E JsExtensions）=====
    // 无头 WebView 内无法直接读取 App 状态，原生在求值前种子注入
    // __state.readConfig / __state.theme / __state.themeMode；
    // 未注入时回退到与 lib/data/model/read_config.dart、lib/constant/app_theme.dart 一致的默认值。
    getReadBookConfig: function () {
      try {
        var rc = __state.readConfig;
        if (!rc || typeof rc !== "object") {
          rc = {
            textSize: 20, textColor: (0xFF333333 | 0), fontFamily: "", fontWeight: 400,
            textAlign: 2, lineSpacing: 2, paragraphSpacing: 1,
            paddingLeft: 16, paddingRight: 16, paddingTop: 8, paddingBottom: 8,
            bgColor: (0xFFFFF8E1 | 0), pageAnim: 0, chineseConverter: 0
          };
        }
        return JSON.stringify(rc);
      } catch (e) { return ""; }
    },
    getThemeConfig: function () {
      try {
        var t = __state.theme;
        if (!t || typeof t !== "object") {
          var dark = false;
          try { dark = !!(window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches); } catch (e2) {}
          t = {
            isDark: dark, themeMode: dark ? 2 : 1,
            seedColor: (0xFF3F5A72 | 0), fontFamily: "", fontScale: 1.0,
            dynamicColor: false, amoled: false, eink: false, foregroundOpacity: 0.18
          };
        }
        return JSON.stringify(t);
      } catch (e) { return ""; }
    },
    getThemeMode: function () {
      // 0: 跟随系统 1: 浅色 2: 深色（与 prefs theme_mode 存储一致）
      var m = __state.themeMode;
      if (m === 0 || m === 1 || m === 2) return m;
      return 0;
    },
    getReadBookConfigMap: function () {
      try { return JSON.parse(java.getReadBookConfig()); } catch (e) { return {}; }
    },
    getThemeConfigMap: function () {
      try { return JSON.parse(java.getThemeConfig()); } catch (e) { return {}; }
    },
    getTxtInFolder: function (path) {
      // 列目录内 .txt 文件；原生 legado://file 暂无 list 能力（未知 op 返回 400），
      // 失败返回 [] 让书源走回退分支，不抛异常。
      try {
        var resp = __doXhr("legado://file?op=list&path=" + encodeURIComponent(path || ""), { method: "GET" });
        var arr = JSON.parse(resp);
        return Array.isArray(arr) ? arr : [];
      } catch (e) { return []; }
    },
    openVideoPlayer: function (url, title) {
      // 经 legado://video 内部协议转交 Dart handler → MethodChannel('legado/video')
      // → Kotlin 原生视频播放器（对齐 E openVideoPlayer 的完整调用链）。
      // 同步 XHR 返回 'true'/'false'，供书源判断是否成功拉起播放器。
      try {
        var ok = __doXhr("legado://video?url=" + encodeURIComponent(url || "") + "&title=" + encodeURIComponent(title || ""), { method: "GET" });
        return String(ok).indexOf("true") >= 0;
      } catch (e) { return false; }
    },

    // 对称加密：对齐 legado JsExtensions.createSymmetricCrypto(transformation, key, iv)
    // 返回 {encrypt, encryptBase64, encryptHex, decrypt, decryptStr}
    createSymmetricCrypto: function (transformation, key, iv) {
      var kb = __aesKeyBytes(key);
      var ivb = __aesIv(iv);
      var mode = String(transformation || "AES").toUpperCase();
      var useCbc = mode.indexOf("CBC") >= 0;
      function encryptBytes(data) {
        var text = (typeof data === "string") ? data : String(data);
        var dataBytes = __utf8ToBytes(text);
        var pad = 16 - (dataBytes.length % 16);
        var padded = new Uint8Array(dataBytes.length + pad);
        padded.set(dataBytes);
        for (var i = dataBytes.length; i < padded.length; i++) padded[i] = pad;
        if (useCbc) {
          return new aesjs.ModeOfOperation.cbc(kb, ivb).encrypt(padded);
        }
        return new aesjs.ModeOfOperation.ecb(kb).encrypt(padded);
      }
      function decryptBytes(bytes) {
        var data = (bytes instanceof Uint8Array) ? bytes : Uint8Array.from(bytes || []);
        var dec;
        if (useCbc) {
          dec = new aesjs.ModeOfOperation.cbc(kb, ivb).decrypt(data);
        } else {
          dec = new aesjs.ModeOfOperation.ecb(kb).decrypt(data);
        }
        return __unpadPkcs7(dec);
      }
      function bytesToB64(b) {
        var s = "";
        for (var i = 0; i < b.length; i++) s += String.fromCharCode(b[i]);
        return btoa(s);
      }
      return {
        encrypt: function (data) { return Array.from(encryptBytes(data)); },
        encryptBase64: function (data) { return bytesToB64(encryptBytes(data)); },
        encryptHex: function (data) { return __bytesToHex(encryptBytes(data)); },
        decrypt: function (bytes) { return Array.from(decryptBytes(bytes)); },
        decryptStr: function (str) {
          var s = String(str == null ? "" : str);
          var bytes;
          if (/^[0-9a-fA-F]+$/.test(s) && s.length % 2 === 0) {
            bytes = __hexToBytes(s);
          } else {
            bytes = __b64ToBytes(s);
          }
          return __bytesToUtf8(decryptBytes(bytes));
        }
      };
    },

    // 非对称加密：对齐 legado JsExtensions.createAsymmetricCrypto(transformation)
    // 返回 {setPublicKey, setPrivateKey, encrypt, encryptBase64, decrypt, decryptStr}
    createAsymmetricCrypto: function (transformation) {
      var pubKey = "", priKey = "";
      return {
        setPublicKey: function (key) { pubKey = __normalizePem(key); return this; },
        setPrivateKey: function (key) { priKey = __normalizePem(key); return this; },
        encrypt: function (data) {
          try {
            var crypt = new JSEncrypt();
            crypt.setPublicKey(pubKey);
            return crypt.encrypt(String(data == null ? "" : data)) || "";
          } catch (e) { return ""; }
        },
        encryptBase64: function (data) { return this.encrypt(data); },
        decrypt: function (data) {
          try {
            var crypt = new JSEncrypt();
            crypt.setPrivateKey(priKey);
            return crypt.decrypt(String(data == null ? "" : data)) || "";
          } catch (e) { return ""; }
        },
        decryptStr: function (data) { return this.decrypt(data); }
      };
    },

    // 签名：对齐 legado JsExtensions.createSign(algorithm)
    // 返回 {setPublicKey, setPrivateKey, sign, signHex}
    createSign: function (algorithm) {
      var pubKey = "", priKey = "";
      return {
        setPublicKey: function (key) { pubKey = __normalizePem(key); return this; },
        setPrivateKey: function (key) { priKey = __normalizePem(key); return this; },
        sign: function (data) {
          try {
            var crypt = new JSEncrypt();
            crypt.setPrivateKey(priKey);
            return crypt.sign(String(data == null ? "" : data), function (s) { return s; }, "sha256") || "";
          } catch (e) { return ""; }
        },
        signHex: function (data) {
          try {
            var crypt = new JSEncrypt();
            crypt.setPrivateKey(priKey);
            return crypt.sign(String(data == null ? "" : data), function (s) { return s; }, "sha256") || "";
          } catch (e) { return ""; }
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
      loginHeader: __state.loginHeader,
      kv: __state.kv,
      infoMap: __state.infoMap,
      cookies: __state.cookies,
      logs: __state.logs,
      toasts: __state.toasts,
      hosts: __state.hosts,
      browser: __state.browser,
      error: err ? ((err && err.stack) ? String(err.stack) : String(err)) : null
    });
  };
''';
