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

    // 书源相关：发现页控件改了分类依赖的变量后，通知原生失效分类缓存并重取分类
    refreshExplore: function () {
      try { __doXhr("legado://refreshexplore", { method: "GET" }); } catch (e) {}
      return true;
    },
    refreshBookToc: function () { return true; },
    refreshBook: function () { return true; },

    // 导航类
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
    startBrowserAwait: function (url, title, refetchAfterSuccess, html) {
      return __openBrowserAwaitHtml(url, title, refetchAfterSuccess, html);
    },
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

    // 字体替换（降级标注）：上游 JsExtensions.replaceFont(text,
    // errorQueryTTF, correctQueryTTF, filter) 用两个 QueryTTF 的字体轮廓
    // 反查「字形相同但码位错乱」的字符再替换，依赖 Android 的 TTF 解析与
    // 字形轮廓比对；Flutter/JS 桥无等价能力，无法复刻。
    // 这里保留「显式字符映射表」这一可等价子集：调用方传入 map（或 JSON
    // 字符串）时按字符逐一替换；传入 QueryTTF 句柄时原样返回文本。
    replaceFont: function (text, font) {
      try {
        var map = (typeof font === "string") ? JSON.parse(font) : font;
        if (!map || typeof map !== "object" || typeof map.length === "number") return text;
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
    // 保留 <img>（含懒加载 data-src）、块级标签转换行、段首两个全角空格缩进、
    // 去注释与空格实体。真实语义转交 Dart 侧 JsTextUtils.htmlFormat，避免
    // 过去「一刀切去所有标签」把正文图片也丢掉的假实现。
    htmlFormat: function (str) {
      try {
        return __doXhr("legado://charset?op=htmlFormat", {
          method: "POST", body: String(str == null ? "" : str)
        });
      } catch (e) {
        // 降级路径同样保留 <img>：只去注释与非 img 标签，不做缩进/实体
        // 处理（避免引入第二套与 Dart 侧不一致的完整语义），但不丢正文图片。
        return String(str == null ? "" : str)
          .replace(/<!--[\s\S]*?-->/g, "")
          .replace(/<\/?(?!img\b)[a-zA-Z][^>]*>/g, "");
      }
    },
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
    // `(第)(.+?)(章)` 命中时把中间数字
    // 用 StringUtils.stringToInt（全角转半角 + 中文数字）转成阿拉伯数字，
    // 其余原样；上游 `(第)(.+?)(章)` 无 ^$ 锚点，用 find() 取首个匹配。
    // 旧实现只做「去前导零」，不认「第一百零二章」。
    toNumChapter: function (s) {
      if (s === null || s === undefined) return null;
      try {
        return __doXhr("legado://charset?op=toNumChapter", {
          method: "POST", body: String(s)
        });
      } catch (e) { return s; }
    },
    // 按 Java charset 编码。
    // V8 的 TextEncoder 只支持 UTF-8，GBK/GB2312/Latin-1 等必须由 Dart 侧
    // enough_convert 完成；返回字节数组 JSON 由 __doXhr 封送。
    strToBytes: function (str, charset) {
      try {
        var res = __doXhr("legado://charset?op=encode&cs=" +
            encodeURIComponent(charset || "UTF-8"), {
          method: "POST", body: String(str == null ? "" : str)
        });
        return JSON.parse(res);
      } catch (e) {
        return Array.from(new TextEncoder().encode(String(str == null ? "" : str)));
      }
    },
    // 按 Java charset 解码。
    bytesToStr: function (bytes, charset) {
      try {
        var arr = [];
        var src = bytes || [];
        for (var i = 0; i < src.length; i++) arr.push(Number(src[i]) & 0xff);
        return __doXhr("legado://charset?op=decode&cs=" +
            encodeURIComponent(charset || "UTF-8"), {
          method: "POST", body: JSON.stringify(arr)
        });
      } catch (e) {
        try { return new TextDecoder(charset || "utf-8").decode(Uint8Array.from(bytes || [])); }
        catch (e2) { return ""; }
      }
    },

    // 脚本导入 / 文件缓存（走 legado://file 内部协议，原生文件系统实现）
    importScript: function (path) {
      var p = String(path == null ? "" : path);
      var result = "";
      try {
        //  JsExtensions.importScript：http 脚本走 cacheFile 下载并缓存，
        // 其余按本地文件读取。
        if (/^https?:\/\//i.test(p)) {
          result = __doXhr("legado://file?op=cache&url=" + encodeURIComponent(p), { method: "GET" });
        } else {
          result = __doXhr("legado://file?op=read&path=" + encodeURIComponent(p), { method: "GET" });
        }
      } catch (e) { result = ""; }
      // 空内容会抛 NoStackTraceException 让书源感知失败。
      if (!String(result || "").trim()) {
        throw new Error(p + " 内容获取失败或者为空");
      }
      return result;
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
    // 下载文件到缓存目录，返回相对路径。
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
    // WebView 重定向 / 资源嗅探：
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
    // 验证码识别：弹出人工输入界面，阻塞等待用户提交后同步返回输入字符。
    // 书源普遍写作 var code = java.getVerificationCode(url)，返回 Promise
    // 会让 code 变成对象而不是字符串，因此这里走同步 XHR 保持 String 语义。
    getVerificationCode: function (imageUrl) {
      try {
        var r = __doXhr("legado://verificationcode?url=" +
          encodeURIComponent(String(imageUrl == null ? "" : imageUrl)),
          { method: "GET" });
        return r == null ? "" : String(r);
      } catch (e) { return ""; }
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

    // ---- 字节版压缩包读取----
    // E 返回 ByteArray；WebView 里等价为 Uint8Array，供书源处理字体/图片/加密数据。
    getZipByteArrayContent: function (url, path) { return __archiveBytes(url, path, "zip"); },
    get7zByteArrayContent: function (url, path) { return __archiveBytes(url, path, "7z"); },
    getRarByteArrayContent: function (url, path) { return __archiveBytes(url, path, "rar"); },

    // ---- 本地文件----
    // E 返回 java.io.File；这里返回带 exists/length/readBytes/readText/
    // getAbsolutePath 的 File-like 对象，覆盖书源对 File 的常用调用。
    getFile: function (path) { return __makeFile(path); },
    readFile: function (path) {
      try {
        var b64 = __doXhr("legado://file?op=readbytes&path=" +
            encodeURIComponent(String(path == null ? "" : path)), { method: "GET" });
        return b64 ? __b64ToBytes(b64) : null;
      } catch (e) { return null; }
    },

    // E 已标记 @Deprecated 但老书源仍在调用，行为与 E 一致：直接委托 queryTTF。
    queryBase64TTF: function (data, useCache) { return this.queryTTF(data, useCache); },

    unzipFile: function (zipPath) {
      try {
        // 整包解压到 legado_files/unzip/<md5(名)>，返回相对目录
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

    // ===== 阅读/主题/媒体接口=====
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
      //  AppConfig.themeMode 是字符串；书源常写 `== "2"`，
      // 返回数字会让比较恒为 false。
      var m = __state.themeMode;
      if (m === 0 || m === 1 || m === 2) return String(m);
      return "0";
    },
    getReadBookConfigMap: function () {
      try { return JSON.parse(java.getReadBookConfig()); } catch (e) { return {}; }
    },
    getThemeConfigMap: function () {
      try { return JSON.parse(java.getThemeConfig()); } catch (e) { return {}; }
    },
    getTxtInFolder: function (path) {
      //  JsExtensions.getTxtInFolder 返回目录内全部文本以 \n 连接的
      // 单个字符串（读完即删除目录）。原生 op=list 返回内容数组，这里
      // 拼接成字符串，避免书源对返回值做 indexOf/正则时拿到数组。
      try {
        var resp = __doXhr("legado://file?op=list&path=" + encodeURIComponent(path || ""), { method: "GET" });
        var arr = JSON.parse(resp);
        if (!Array.isArray(arr)) return "";
        return arr.map(function (s) { return String(s == null ? "" : s); }).join("\n");
      } catch (e) { return ""; }
    },
    openVideoPlayer: function (url, title) {
      // 经 legado://video 内部协议转交 Dart handler → MethodChannel('legado/video')
      // → Kotlin 原生视频播放器。
      // 同步 XHR 返回 'true'/'false'，供书源判断是否成功拉起播放器。
      try {
        var ok = __doXhr("legado://video?url=" + encodeURIComponent(url || "") + "&title=" + encodeURIComponent(title || ""), { method: "GET" });
        return String(ok).indexOf("true") >= 0;
      } catch (e) { return false; }
    },

    // 对称加密： JsExtensions.createSymmetricCrypto(transformation, key, iv)
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

    // 非对称加密： JsExtensions.createAsymmetricCrypto(transformation)
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

    // 签名： JsExtensions.createSign(algorithm)
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
