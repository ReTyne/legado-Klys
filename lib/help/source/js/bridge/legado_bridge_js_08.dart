/// JS 片段 8/8（按体积均匀切片，拼接顺序不可变）。
const String legadoBridgeJsPart08 =
    r'''    androidId: function () { return __state.deviceId; },
    getWebViewUA: function () { return __state.ua; },
    getAppVariant: function () { return "android"; },

    // 时间
    timeFormat: function (time, pattern) { return __timeFormat(time, pattern, false, 0); },
    timeFormatUTC: function (time, pattern, sh) { return __timeFormat(time, pattern, true, sh); },

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
    // url/webView/browser → 内置浏览器；sort/rss/search/explore 做数据准备与事件记录。
    open: function (name, url, title, origin) {
      var n = String(name == null ? "" : name).toLowerCase();
      var u = String(url == null ? "" : url);
      var t = String(title == null ? "" : title);
      var o = String(origin == null ? "" : origin);
      try {
        if (n === "login") {
          __doXhr("legado://openlogin?origin=" + encodeURIComponent(o), { method: "GET" });
        } else if (n === "url" || n === "webview" || n === "browser") {
          if (u) __openBrowser(u, t, false);
        } else if (n === "sort") {
          __state.sortData = { url: u, title: t, origin: o };
          __uiEvent("openSort", { url: u, title: t, origin: o });
        } else if (n === "rss") {
          globalThis.rssArticle = __wrapWriteMethods({ url: u, title: t, origin: o });
          __uiEvent("openRss", { url: u, title: t, origin: o });
        } else if (n === "search") {
          __uiEvent("openSearch", { key: u || t, origin: o });
          if (u || t) this.searchBook(u || t, o);
        } else if (n === "explore") {
          __uiEvent("openExplore", { url: u, title: t, origin: o });
          __doXhr("legado://refreshexplore", { method: "GET" });
        }
      } catch (e) {}
      return true;
    },

    // 浏览器登录
    // 非阻塞式：legado 语义为 Unit（发现页 url 型分类常写
    // `{{java.startBrowser(url,title)}}`，求值须为空串而非 Promise）。
    startBrowser: function (url, title, html) { __openBrowser(url, title, false, html); },
    startBrowserDp: function (url, title) { __openBrowser(url, title, false); },
    // 阻塞式：用户关闭网页后返回带 body() 的 StrResponse（正文为关闭时页面 HTML）
    startBrowserAwait: function (url, title, refetchAfterSuccess, html) {
      return __openBrowserAwaitHtml(url, title, refetchAfterSuccess, html);
    },
    showBrowser: function (url, html, preloadJs, config) {
      var custom = (typeof html === "string" && html.indexOf("<") >= 0) ? html : null;
      var title = (typeof html === "string" && html.indexOf("<") < 0) ? html : "";
      return __openBrowserAwaitHtml(url, title || "浏览", true, custom, preloadJs, config);
    },
    showReadingBrowser: function (url, title) { return __openBrowserAwaitHtml(url, title); },
    reLoginView: function (deltaUp) {
      __uiEvent("reUiView", { deltaUp: deltaUp === undefined ? true : !!deltaUp });
      if (typeof deltaUp === "string" && /^https?:\/\//i.test(deltaUp)) {
        return __openBrowserAwaitHtml(deltaUp, "登录");
      }
      return __strResponse("", "", 200, "OK", {});
    },

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

    // 字体替换：双参（text, 显式字符映射表）按表逐字替换；
    // 三/四参（text, errorQueryTTF, correctQueryTTF, filter）按字形轮廓
    // 签名反查「字形相同但码位错乱」的字符再替换，filter=true 删除无对应字符。
    replaceFont: function (text, errorQ, correctQ, filter) {
      // 双参：显式字符映射表（map 或 JSON 字符串）。
      if (arguments.length <= 2) {
        try {
          var font = errorQ;
          var map = (typeof font === "string") ? JSON.parse(font) : font;
          if (!map || typeof map !== "object" || typeof map.length === "number") return text;
          var s0 = String(text == null ? "" : text), out0 = "";
          for (var i0 = 0; i0 < s0.length; i0++) {
            var c0 = s0[i0];
            out0 += (map[c0] !== undefined && map[c0] !== null) ? map[c0] : c0;
          }
          return out0;
        } catch (e) { return text; }
      }
      // 三/四参：两个 QueryTTF 对象，按签名反查替换。
      try {
        var s = String(text == null ? "" : text);
        var errMap = __fontSignatureMap(errorQ);
        var corMap = __fontSignatureMap(correctQ);
        var out = "", del = !!filter;
        for (var i = 0; i < s.length; i++) {
          var ch = s[i];
          if (ch.length > 1) { out += ch; i++; continue; }
          var cp = s.codePointAt ? s.codePointAt(i) : s.charCodeAt(i);
          var sig = errMap.byUnicode[cp];
          if (sig === undefined) { if (!del) out += ch; continue; }
          var target = corMap.bySignature[sig];
          if (target === undefined || target === null) { if (!del) out += ch; continue; }
          out += (String.fromCodePoint ? String.fromCodePoint(target) : String.fromCharCode(target));
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
    openUrl: function (url, mimeType) {
      var u = String(url == null ? "" : url);
      var mt = String(mimeType == null ? "" : mimeType);
      // legado:// / yuedu:// 导入链接：记录事件交给原生导入流程。
      if (/^(legado|yuedu):\/\//i.test(u)) {
        __uiEvent("importSource", { url: u, mimeType: mt });
        return true;
      }
      __openBrowser(u, "", false, null, mt);
      return true;
    },

    // 编码 / 文本处理
    encodeURI: function (str, enc) {
      try {
        var s = String(str == null ? "" : str);
        if (enc && String(enc).trim()) {
          // V8 TextEncoder 仅支持 UTF-8；其它字符集交给 Dart 侧编码后逐字节转义。
          var bytes = this.strToBytes(s, String(enc));
          var out = "";
          for (var i = 0; i < bytes.length; i++) {
            var b = bytes[i] & 0xff;
            if ((b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A) ||
                (b >= 0x30 && b <= 0x39) || b === 0x2D || b === 0x2E ||
                b === 0x5F || b === 0x7E) {
              out += String.fromCharCode(b);
            } else if (b === 0x20) { out += "+"; }
            else { out += "%" + ("0" + b.toString(16).toUpperCase()).slice(-2); }
          }
          return out;
        }
        return encodeURIComponent(s).replace(/%20/g, "+");
      } catch (e) { return ""; }
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
    // 返回普通对象（非原生 URL），searchParams 为普通 Map。
    toURL: function (urlStr, baseUrl) {
      var u;
      try { u = new URL(urlStr, baseUrl || __state.meta.httpUrl); } catch (e) { return null; }
      var params = {};
      try { u.searchParams.forEach(function (v, k) { params[k] = v; }); } catch (e) {}
      return {
        href: u.href, protocol: u.protocol, host: u.host, hostname: u.hostname,
        port: u.port, pathname: u.pathname, search: u.search, hash: u.hash,
        origin: u.origin, searchParams: params,
        getQuery: function () { return u.search ? u.search.substring(1) : ""; },
        get: function (k) { return params[k] === undefined ? "" : params[k]; },
        set: function (k, v) { params[k] = String(v); return this; },
        addQueryParameter: function (k, v) { params[k] = String(v); return this; },
        toString: function () { return u.href; }
      };
    },
    // `(第)(.+?)(章)` 命中时把中间数字
    // 用 StringUtils.stringToInt（全角转半角 + 中文数字）转成阿拉伯数字，
 // 其余原样； `(第)(.+?)(章)` 无 ^$ 锚点，用 find 取首个匹配。
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
      var q = "&saveTime=" + encodeURIComponent(String(Number(saveTime) || 0));
      try { return __doXhr("legado://file?op=cache&url=" + encodeURIComponent(urlStr) + q, { method: "GET" }); }
      catch (e) { return ""; }
    },
    readTxtFile: function (path, charset) {
      var cs = (charset && String(charset).trim()) ? "&cs=" + encodeURIComponent(String(charset)) : "";
      try { return __doXhr("legado://file?op=read&path=" + encodeURIComponent(path) + cs, { method: "GET" }); }
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
    ajaxAll: function (urlList, skipRateLimit) {
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
        var payload = { list: urls, isTest: false,
          skipRateLimit: !!skipRateLimit, timeout: 0 };
        var raw = __doXhr("legado://ajaxall", { method: "POST", body: JSON.stringify(payload) });
        var arr = JSON.parse(raw);
        if (Array.isArray(arr)) {
          // Future.wait 已保证元素顺序与 urls 一致，逐个还原为 StrResponse
          return arr.map(function (r) {
            return __strResponse(r.url, r.body, r.code, r.message, r.headers || {},
              { callTime: r.callTime });
          });
        }
      } catch (e) {}
      // 内部协议异常时逐项如实回报 502（不假装成功，也不退回串行桩）
      return urls.map(function (o) {
        return __strResponse(o.url, "", 502, "Error", {});
      });
    },
    // isTest 模式：失败按错误类型归一到 -1~-7（超时/未知主机/连接拒绝/SSL/...）。
    ajaxTestAll: function (urlList, timeout, skipRateLimit) {
      var list = Array.isArray(urlList) ? urlList : [];
      if (list.length === 0) return [];
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
        var payload = { list: urls, isTest: true,
          skipRateLimit: !!skipRateLimit, timeout: Number(timeout) || 0 };
        var raw = __doXhr("legado://ajaxall", { method: "POST", body: JSON.stringify(payload) });
        var arr = JSON.parse(raw);
        if (Array.isArray(arr)) {
          return arr.map(function (r) {
            return __strResponse(r.url, r.body, __testErrorCode(r), r.message,
              r.headers || {}, { callTime: r.callTime });
          });
        }
      } catch (e) {}
      return urls.map(function (o) {
        return __strResponse(o.url, "", -1, "Error", {});
      });
    },

    // WebView 渲染：走 legado://webview 内部协议，用第二个无头 WebView 加载并等 JS 渲染后取源码
    // 把 html / url / js / sourceRegex / cacheFirst / delayMs / encode 全部封进
    // legado://webview 请求，由 Dart 侧调 HeadlessWebViewFetcher.fetch 渲染。
    webView: function (html, url, js, cacheFirst) {
      try {
        var target = url || "";
        if (!target) return html || "";
        var payload = {
          url: target,
          html: html == null ? "" : String(html),
          injectJs: js == null ? "" : String(js),
          sourceRegex: "",
          cacheFirst: !!cacheFirst,
          delayMs: 0,
          encode: "utf-8",
          tag: ""
        };
        var rendered = __doXhr("legado://webview", { method: "POST", body: JSON.stringify(payload) });
        return rendered || html || "";
      } catch (e) { return html || ""; }
    },
    webViewGetSource: function (html, url, js, sourceRegex, cacheFirst, delayTime) {
      try {
        var target = url || "";
        if (!target) return "";
        var payload = {
          url: target,
          html: html == null ? "" : String(html),
          injectJs: js == null ? "" : String(js),
          sourceRegex: String(sourceRegex == null ? "" : sourceRegex),
          cacheFirst: !!cacheFirst,
          delayMs: Number(delayTime) || 0,
          encode: "utf-8",
          tag: ""
        };
        return __doXhr("legado://webview", { method: "POST", body: JSON.stringify(payload) });
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

    // 字体反爬：返回带映射与方法（getGlyfByUnicode 等）的字体对象。
    queryTTF: function (data, useCache) {
      try {
        var b64 = "", rawStr = "", isPath = false;
        if (typeof data === "string") {
          rawStr = data;
          if (/^https?:\/\//i.test(rawStr)) {
            // http 链接：先下载字体文件字节。
            var bytes = __doXhr(rawStr, { method: "GET" }, "arraybuffer");
            var bin = new Uint8Array(bytes);
            var binStr = "";
            for (var i = 0; i < bin.length; i++) binStr += String.fromCharCode(bin[i]);
            b64 = btoa(binStr);
          } else if (/^[A-Za-z0-9+/=\s]+$/.test(rawStr) && rawStr.replace(/\s+/g, "").length > 64) {
            // 已是 base64 字体数据。
            b64 = rawStr.replace(/\s+/g, "");
          } else {
            isPath = true; // 本地文件路径
          }
        } else if (data && typeof data.length === "number") {
          // 字节数组（Array / Uint8Array）。
          var s2 = "";
          for (var j = 0; j < data.length; j++) s2 += String.fromCharCode(data[j] & 0xff);
          b64 = btoa(s2);
        }
        if (isPath) {
          var fb = __doXhr("legado://file?op=readbytes&path=" + encodeURIComponent(rawStr), { method: "GET" });
          b64 = String(fb || "");
        }
        if (!b64) return null;
        // useCache：按字体内容 SHA-256 缓存解析结果，避免重复解析。
        var cacheKey = "";
        if (useCache) {
          try { cacheKey = "ttf_" + __sha256(b64); } catch (e) { cacheKey = "ttf_" + b64.length; }
          var hit = cache.getFromMemory(cacheKey);
          if (hit && typeof hit === "object") return hit;
        }
        var resp = __doXhr("legado://ttf", { method: "POST", body: b64 });
        var obj = __makeQueryTTF(JSON.parse(resp));
        if (useCache && cacheKey) cache.putMemory(cacheKey, obj);
        return obj;
      } catch (e) { return null; }
    },
    getZipStringContent: function (url, path, charset) {
      var cs = (charset && String(charset).trim()) ? "&cs=" + encodeURIComponent(String(charset)) : "";
      try {
        return __doXhr("legado://zip?url=" + encodeURIComponent(url) + "&path=" + encodeURIComponent(path || "") + cs, { method: "GET" });
      } catch (e) { return ""; }
    },
    get7zStringContent: function (url, path, charset) {
      var cs = (charset && String(charset).trim()) ? "&cs=" + encodeURIComponent(String(charset)) : "";
      try {
        return __doXhr("legado://zip?kind=7z&url=" + encodeURIComponent(url) + "&path=" + encodeURIComponent(path || "") + cs, { method: "GET" });
      } catch (e) { return ""; }
    },
    getRarStringContent: function (url, path, charset) {
      var cs = (charset && String(charset).trim()) ? "&cs=" + encodeURIComponent(String(charset)) : "";
      try {
        return __doXhr("legado://zip?kind=rar&url=" + encodeURIComponent(url) + "&path=" + encodeURIComponent(path || "") + cs, { method: "GET" });
      } catch (e) { return ""; }
    },

    // ---- 字节版压缩包读取----
    // 返回 Uint8Array，供书源处理字体/图片/加密数据。
    getZipByteArrayContent: function (url, path) { return __archiveBytes(url, path, "zip"); },
    get7zByteArrayContent: function (url, path) { return __archiveBytes(url, path, "7z"); },
    getRarByteArrayContent: function (url, path) { return __archiveBytes(url, path, "rar"); },

    // ---- 本地文件----
    // 返回带 exists/length/readBytes/readText/getAbsolutePath 的 File-like 对象，
    // 覆盖书源对 File 的常用调用。
    getFile: function (path) { return __makeFile(path); },
    readFile: function (path) {
      try {
        var b64 = __doXhr("legado://file?op=readbytes&path=" +
            encodeURIComponent(String(path == null ? "" : path)), { method: "GET" });
        return b64 ? __b64ToBytes(b64) : null;
      } catch (e) { return null; }
    },

    // 兼容别名：直接委托 queryTTF。
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
    openVideoPlayer: function (url, title, isFloat) {
      // 经 legado://video 内部协议转交 Dart handler → MethodChannel('legado/video')
      // → Kotlin 原生视频播放器；isFloat 透传悬浮窗选项。
      // 同步 XHR 返回 'true'/'false'，供书源判断是否成功拉起播放器。
      try {
        var ok = __doXhr("legado://video?url=" + encodeURIComponent(url || "") +
          "&title=" + encodeURIComponent(title || "") +
          "&isFloat=" + (isFloat ? "1" : "0"), { method: "GET" });
        return String(ok).indexOf("true") >= 0;
      } catch (e) { return false; }
    },

    // 对称加密： JsExtensions.createSymmetricCrypto(transformation, key, iv)
    // 返回 {encrypt, encryptBase64, encryptHex, decrypt, decryptStr}
    createSymmetricCrypto: function (transformation, key, iv) {
      var t = String(transformation || "AES");
      var alg = t.split("/")[0].toUpperCase().replace(/[-\s]/g, "");
      var isAes = (alg === "AES" || alg === "" || alg === "RIJNDAEL");
      // 非 AES 算法（DES / 3DES / DESede / SM4 / RC4）委托原生实现，
      // 覆盖纯 JS 版不支持的分组长度与密钥编排；接口与 AES 版一致。
      if (!isAes && (alg === "DES" || alg === "DESEDE" || alg === "3DES" ||
          alg === "TRIPLEDES" || alg === "SM4" || alg === "SMS4" ||
          alg === "RC4" || alg === "ARCFOUR")) {
        var nkb = __symArgBytes(key);
        var nivb = __symArgBytes(iv);
        var nEnc = function (data) {
          return __nativeCrypto("encrypt", t, nkb, nivb, __symArgBytes(data));
        };
        var nDec = function (data) {
          return __nativeCrypto("decryptBytes", t, nkb, nivb, __symCipherBytes(data));
        };
        return {
          setIv: function (v) { nivb = __symArgBytes(v); return this; },
          encrypt: function (data) { return Array.from(nEnc(data)); },
          encryptBase64: function (data) { return __bytesToB64(nEnc(data)); },
          encryptHex: function (data) { return __bytesToHex(nEnc(data)); },
          decrypt: function (data) { return Array.from(nDec(data)); },
          decryptByteArray: function (data) { return Array.from(nDec(data)); },
          decryptStr: function (data) { return __bytesToUtf8(nDec(data)); }
        };
      }
      var kb = __aesKeyBytes(key);
      var ivb = __aesIv(iv);
      var mode = t.toUpperCase();
      var useCbc = mode.indexOf("CBC") >= 0;
      // ECB/CBC + PKCS5/PKCS7 之外的模式（PCBC/CFB/OFB/CTR、NoPadding）
      // 由原生 SymmetricCrypto 处理，避免纯 JS 版静默按 ECB 运算。
      var nativeOnly = !__aesFastPath(t);
      function encryptBytes(data) {
        if (nativeOnly) {
          return __nativeCrypto("encrypt", t, kb, ivb, __symArgBytes(data));
        }
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
        if (nativeOnly) {
          return __nativeCrypto("decryptBytes", t, kb, ivb, __symCipherBytes(bytes));
        }
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
        setIv: function (v) { ivb = __aesIv(v); return this; },
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

    // 非对称加密：createAsymmetricCrypto(transformation, usePublicKey)
    // encrypt/decrypt 返回字节数组，usePub 逐次指定（缺省沿用构造期值）；
    // transformation（含 OAEP 等）透传给原生门面，由 op=asym 分派。
    createAsymmetricCrypto: function (transformation, usePublicKey) {
      var t = String(transformation || "RSA");
      var pubKey = "", priKey = "";
      var defaultUsePub = (usePublicKey === undefined) ? true : !!usePublicKey;
      function call(sub, data, usePub) {
        var payload = {
          op: "asym", sub: sub, transformation: t,
          publicKey: pubKey, privateKey: priKey,
          data: String(data == null ? "" : data),
          usePublicKey: !!usePub
        };
        return String(__doXhr("legado://crypto", { method: "POST", body: payload }, null, null) || "");
      }
      function toBytes(b64) {
        try { return Array.from(__b64ToBytes(b64)); } catch (e) { return []; }
      }
      return {
        setPublicKey: function (key) { pubKey = __normalizePem(key); return this; },
        setPrivateKey: function (key) { priKey = __normalizePem(key); return this; },
        encrypt: function (data, usePub) {
          return toBytes(call("encryptBytes", data,
            usePub === undefined ? defaultUsePub : !!usePub));
        },
        encryptBase64: function (data, usePub) {
          return call("encryptBase64", data,
            usePub === undefined ? defaultUsePub : !!usePub);
        },
        encryptHex: function (data, usePub) {
          return call("encryptHex", data,
            usePub === undefined ? defaultUsePub : !!usePub);
        },
        decrypt: function (data, usePub) {
          return toBytes(call("decryptBytes", data,
            usePub === undefined ? false : !!usePub));
        },
        decryptByteArray: function (data, usePub) { return this.decrypt(data, usePub); },
        decryptStr: function (data, usePub) {
          return __bytesToUtf8(Uint8Array.from(this.decrypt(data, usePub)));
        },
        // 兼容把加解密结果当字符串使用的旧写法
        encryptToString: function (data, usePub) { return this.encryptBase64(data, usePub); },
        decryptToString: function (data, usePub) { return this.decryptStr(data, usePub); }
      };
    },

    // 签名：createSign(algorithm) 按 algorithm 选择 hash，走 legado://sign 通道。
    // 返回 {setPublicKey, setPrivateKey, sign, signBase64, signHex, verify}。
    createSign: function (algorithm) {
      var pubKey = "", priKey = "";
      var alg = String(algorithm || "SHA256withRSA");
      function hashOf() {
        var a = alg.toUpperCase();
        if (a.indexOf("MD5") >= 0) return "md5";
        if (a.indexOf("SHA1") >= 0 || a.indexOf("SHA-1") >= 0) return "sha1";
        if (a.indexOf("SHA224") >= 0) return "sha224";
        if (a.indexOf("SHA384") >= 0) return "sha384";
        if (a.indexOf("SHA512") >= 0) return "sha512";
        return "sha256";
      }
      function signCall(data, out) {
        try {
          var payload = { op: "sign", algorithm: alg, hash: hashOf(), key: priKey,
            data: String(data == null ? "" : data), out: out };
          return __doXhr("legado://sign", { method: "POST", body: payload }, null, null) || "";
        } catch (e) { return ""; }
      }
      return {
        setPublicKey: function (key) { pubKey = __normalizePem(key); return this; },
        setPrivateKey: function (key) { priKey = __normalizePem(key); return this; },
        sign: function (data) { return signCall(data, "base64"); },
        signBase64: function (data) { return signCall(data, "base64"); },
        signHex: function (data) { return signCall(data, "hex"); },
        verify: function (data, signature) {
          try {
            var payload = { op: "verify", algorithm: alg, hash: hashOf(), key: pubKey,
              data: String(data == null ? "" : data),
              signature: String(signature == null ? "" : signature) };
            var r = __doXhr("legado://sign", { method: "POST", body: payload }, null, null);
            return String(r).indexOf("true") >= 0;
          } catch (e) { return false; }
        }
      };
    },

    // ==================== 内容 / 规则上下文 ====================
    // 维护 __state.ruleContext，四个 setXxx 方法链式返回 java 自身。
    setContent: function (content, baseUrl) {
      var ctx = __state.ruleContext || (__state.ruleContext = {});
      ctx.content = String(content == null ? "" : content);
      if (baseUrl !== undefined && baseUrl !== null) ctx.baseUrl = String(baseUrl);
      __ruleCall("setContent", { content: ctx.content, baseUrl: ctx.baseUrl || "" });
      return java;
    },
    setBaseUrl: function (baseUrl) {
      var ctx = __state.ruleContext || (__state.ruleContext = {});
      ctx.baseUrl = String(baseUrl == null ? "" : baseUrl);
      __ruleCall("setBaseUrl", { baseUrl: ctx.baseUrl });
      return java;
    },
    setRedirectUrl: function (url) {
      var ctx = __state.ruleContext || (__state.ruleContext = {});
      ctx.redirectUrl = String(url == null ? "" : url);
      __ruleCall("setRedirectUrl", { url: ctx.redirectUrl });
      return java;
    },
    getString: function (rule, mContent, isUrl) {
      return __ruleCall("getString", { rule: rule, content: mContent, isUrl: !!isUrl });
    },
    getStringList: function (rule, mContent, isUrl) {
      var r = __ruleCall("getStringList", { rule: rule, content: mContent, isUrl: !!isUrl });
      try { var a = JSON.parse(r); return Array.isArray(a) ? a : []; } catch (e) { return []; }
    },
    getElement: function (rule) {
      return __makeElement(__ruleCall("getElement", { rule: rule }));
    },
    getElements: function (rule) {
      var r = __ruleCall("getElements", { rule: rule });
      try {
        var a = JSON.parse(r);
        return Array.isArray(a) ? a.map(__makeElement) : [];
      } catch (e) { return []; }
    },

    // ==================== UI 事件 / 登录与配置 ====================
    addBook: function (bookUrl) {
      __uiEvent("addBook", { url: String(bookUrl == null ? "" : bookUrl) });
      return true;
    },
    showPhoto: function (src) {
      __uiEvent("showPhoto", { src: String(src == null ? "" : src) });
      return true;
    },
    copyText: function (text) {
      var t = String(text == null ? "" : text);
      __state.clipboard = t;
      __uiEvent("copyText", { text: t });
      return true;
    },
    clearTtsCache: function () {
      __uiEvent("clearTtsCache", {});
      return true;
    },
    upLoginData: function (data) {
      var d = (typeof data === "string") ? data : JSON.stringify(data);
      __state.loginData = d;
      __uiEvent("upLoginData", { data: d });
      return true;
    },
    upUiData: function (data) {
      var d = (typeof data === "string") ? data : JSON.stringify(data);
      __state.uiData = d;
      __uiEvent("upUiData", { data: d });
      return true;
    },
    reUiView: function (deltaUp) {
      __uiEvent("reUiView", { deltaUp: deltaUp === undefined ? true : !!deltaUp });
      return true;
    },
    refreshBookInfo: function () {
      __uiEvent("refreshBookInfo", {});
      return true;
    },
    refreshContent: function () {
      __uiEvent("refreshContent", {});
      return true;
    },
    upConfig: function (config) {
      var c = config;
      if (typeof c === "string") {
        try { c = JSON.parse(c); } catch (e) { c = { value: c }; }
      }
      if (c && typeof c === "object") {
        __state.config = Object.assign(__state.config || {}, c);
      }
      __uiEvent("upConfig", { config: __state.config || {} });
      return true;
    },
    getRandomLetter: function () {
      return String.fromCharCode(97 + Math.floor(Math.random() * 26));
    },

    // ==================== Promise 桥的原生分派 ====================
    // funName 为 run / xxxAwait；同步执行对应能力后把结果写进
    // cache.putMemory(id, data)，回调 window.__legadoBridgeResult(id, success)，
    // 并返回 Promise，兼顾 await 与回调两种写法。
    request: function (funName, jsParam, id) {
      var data = null, success = false;
      try {
        var fn = String(funName || "");
        var p = jsParam;
        if (typeof p === "string") { try { p = JSON.parse(p); } catch (e) {} }
        var arg = (p && typeof p === "object" && !Array.isArray(p)) ? p : { value: p };
        var url = arg.url || arg.value || (typeof p === "string" ? p : "");
        var body = arg.body || arg.data || arg.post || null;
        var headers = arg.headers || {};
        switch (fn) {
          case "run":
            data = (typeof p === "string") ? eval(p) : null;
            break;
          case "ajaxAwait":
          case "getAwait":
          case "headAwait":
          case "postAwait":
          case "connectAwait":
          case "webViewAwait":
            data = java.__awaitDispatch(fn, url, body, headers, arg);
            break;
          case "decryptStrAwait":
            data = java.createSymmetricCrypto(arg.transformation || "AES", arg.key, arg.iv)
                .decryptStr(arg.data || body || "");
            break;
          case "encryptBase64Await":
            data = java.createSymmetricCrypto(arg.transformation || "AES", arg.key, arg.iv)
                .encryptBase64(arg.data || body || "");
            break;
          case "encryptHexAwait":
            data = java.createSymmetricCrypto(arg.transformation || "AES", arg.key, arg.iv)
                .encryptHex(arg.data || body || "");
            break;
          case "createSignHexAwait":
            data = java.createSign(arg.algorithm || "SHA256withRSA")
                .setPrivateKey(arg.key || arg.privateKey || "").signHex(arg.data || body || "");
            break;
          case "downloadFileAwait":
            data = java.downloadFile(arg.url || url);
            break;
          case "readTxtFileAwait":
            data = java.readTxtFile(arg.path || url, arg.charset);
            break;
          case "importScriptAwait":
            data = java.importScript(arg.path || url);
            break;
          case "getStringAwait":
            data = java.getString(arg.rule || "", arg.content, arg.isUrl);
            break;
          default:
            data = null;
        }
        success = true;
      } catch (e) {
        data = String(e && e.message || e);
        success = false;
      }
      try { cache.putMemory(id, data); } catch (e) {}
      try {
        if (typeof window !== "undefined" && typeof window.__legadoBridgeResult === "function") {
          window.__legadoBridgeResult(id, success);
        }
      } catch (e) {}
      return Promise.resolve(data);
    },
    __awaitDispatch: function (fn, url, body, headers, arg) {
      try {
        if (fn === "getAwait") return java.get(url, headers).body();
        if (fn === "headAwait") return java.head(url, headers).body();
        if (fn === "postAwait") return java.post(url, body, headers).body();
        if (fn === "connectAwait") return java.connect(url, headers).execute().body();
        if (fn === "webViewAwait") return java.webView(arg.html || "", url, arg.js || "", arg.cacheFirst);
        return java.ajax(url, { method: arg.method || "GET", headers: headers, body: body });
      } catch (e) { return ""; }
    },

    // ==================== AnalyzeUrl 场景 ====================
    getUserAgent: function () { return __state.ua; },
    getHeaderMap: function (hasLoginHeader) { return source.getHeaderMap(hasLoginHeader); },

    // java.lang / java.net 常见静态调用
    lang: {
      Thread: { sleep: __pkgSleep },
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

  // ---- UI 事件：JS 侧记录 + 原生 legado://loginui/<action> 回调 ----
  function __uiEvent(action, payload) {
    if (!__state.uiEvents) __state.uiEvents = [];
    __state.uiEvents.push({ action: action, data: payload, time: Date.now() });
    if (__state.uiEvents.length > 200) __state.uiEvents.shift();
    try {
      return __doXhr("legado://loginui/" + encodeURIComponent(action),
        { method: "POST", body: JSON.stringify({ action: action, data: payload }) });
    } catch (e) { return ""; }
  }

  // ---- 规则求值通道：把 rule/content/isUrl 封送 legado://rule ----
  function __ruleCall(op, extra) {
    var payload = extra || {};
    var ctx = __state.ruleContext || (__state.ruleContext = {});
    if (payload.content === undefined || payload.content === null) payload.content = ctx.content || "";
    if (payload.baseUrl === undefined || payload.baseUrl === null) payload.baseUrl = ctx.baseUrl || "";
    try {
      return __doXhr("legado://rule?op=" + encodeURIComponent(op),
        { method: "POST", body: JSON.stringify(payload) });
    } catch (e) { return ""; }
  }

  // ---- 把元素 HTML 包装成带 text/html/attr 方法的轻量对象 ----
  function __makeElement(html) {
    var h = String(html == null ? "" : html);
    return {
      html: function () { return h; },
      outerHtml: function () { return h; },
      text: function () { return h.replace(/<[^>]*>/g, ""); },
      attr: function (name) {
        var m = h.match(new RegExp(name + "\\s*=\\s*[\"']([^\"']*)[\"']", "i"));
        return m ? m[1] : "";
      },
      toString: function () { return h; }
    };
  }

  // ---- QueryTTF → 按码位/轮廓签名建立反查表 ----
  function __fontSignatureMap(q) {
    var out = { byUnicode: {}, bySignature: {} };
    if (!q || typeof q !== "object") return out;
    var u2g = q.unicodeToGlyph || {};
    if (!Object.keys(u2g).length && typeof q.getReplacementMap === "function") {
      u2g = q.getReplacementMap() || {};
    }
    Object.keys(u2g).forEach(function (u) {
      var g = u2g[u];
      var sig = (g && typeof g === "object") ? (g.signature || g.outline || g.name || g) : g;
      if (sig === null || sig === undefined) return;
      var key = (typeof sig === "object") ? JSON.stringify(sig) : String(sig);
      var cp = parseInt(u, 10);
      if (isNaN(cp)) return;
      out.byUnicode[cp] = key;
      if (out.bySignature[key] === undefined) out.bySignature[key] = cp;
    });
    Object.keys(q).forEach(function (k) {
      if (/^\d+$/.test(k)) {
        var cp2 = parseInt(k, 10);
        if (out.byUnicode[cp2] === undefined) out.byUnicode[cp2] = String(q[k]);
      }
    });
    return out;
  }

  // ---- isTest 错误码 -1~-7 ----
  function __testErrorCode(r) {
    var c = Number(r.code);
    if (c >= 200 && c < 400) return 0;
    var msg = (String(r.message || "") + " " + String(r.body || "")).toLowerCase();
    if (msg.indexOf("timeout") >= 0 || msg.indexOf("超时") >= 0) return -1;
    if (msg.indexOf("unknownhost") >= 0 || msg.indexOf("未知主机") >= 0) return -2;
    if (msg.indexOf("refused") >= 0 || msg.indexOf("连接拒绝") >= 0) return -3;
    if (msg.indexOf("ssl") >= 0 || msg.indexOf("handshake") >= 0 || msg.indexOf("证书") >= 0) return -4;
    if (msg.indexOf("reset") >= 0 || msg.indexOf("断开") >= 0) return -5;
    if (msg.indexOf("unreachable") >= 0 || msg.indexOf("不可达") >= 0) return -6;
    return -7;
  }

  // ---- xxxAwait 全局封装：经 java.request 执行并从内存缓存取回结果 ----
  function __awaitFn(name) {
    return function (jsParam) {
      var id = "r" + Date.now() + Math.floor(Math.random() * 100000);
      return java.request(name, jsParam, id).then(function (v) {
        var m = cache.getFromMemory(id);
        return m === null ? v : m;
      });
    };
  }
  ["ajaxAwait", "connectAwait", "getAwait", "headAwait", "postAwait", "webViewAwait",
   "decryptStrAwait", "encryptBase64Await", "encryptHexAwait", "createSignHexAwait",
   "downloadFileAwait", "readTxtFileAwait", "importScriptAwait", "getStringAwait"]
    .forEach(function (n) {
      if (typeof globalThis[n] !== "function") globalThis[n] = __awaitFn(n);
    });
  if (typeof window.__legadoBridgeResult !== "function") {
    window.__legadoBridgeResult = function () {};
  }

  // ---- 按场景暴露 java 的方法子集；未指定场景时返回完整 java ----
  var __sceneCore = [
    "log", "toast", "longToast", "ajax", "get", "post", "head", "put", "delete", "connect",
    "newResponse", "getCookie", "base64Encode", "base64Decode", "encodeBase64", "decodeBase64",
    "md5Encode", "md5Encode16", "sha1Encode", "sha256Encode", "digestHex", "digestBase64Str",
    "HMacHex", "HMacBase64", "hexDecodeToString", "hexEncodeToString", "stringToHex",
    "base64DecodeToByteArray", "hexDecodeToByteArray", "aesDecodeToString", "aesEncodeToString",
    "createSymmetricCrypto", "createAsymmetricCrypto", "createSign", "put", "remove", "contains",
    "getSource", "getTag", "getWebViewUA", "getUserAgent", "getHeaderMap", "getAbsoluteURL",
    "getRedirectUrl", "randomUUID", "logType", "toURL", "toNumChapter", "strToBytes", "bytesToStr",
    "htmlFormat", "t2s", "s2t", "importScript", "cacheFile", "readTxtFile", "deleteFile",
    "downloadFile", "download", "share", "openUrl", "getZipStringContent", "get7zStringContent",
    "getRarStringContent", "queryTTF", "queryBase64TTF", "getFile", "readFile", "getTxtInFolder",
    "timeFormat", "timeFormatUTC", "encodeURI", "gzipCompress", "gzipDecompress", "ajaxAll",
    "ajaxTestAll", "webView", "webViewGetSource", "startBrowser", "startBrowserAwait",
    "showBrowser", "reLoginView", "getVerificationCode", "refreshExplore", "searchBook", "open",
    "getReadBookConfig", "getThemeConfig", "getThemeMode", "openVideoPlayer", "lang", "net", "request"
  ];
  var __javaScenes = {
    rule: __sceneCore.concat(["getString", "getStringList", "getElement", "getElements",
      "setContent", "setBaseUrl", "setRedirectUrl"]),
    webview: __sceneCore.concat(["request", "upConfig", "webView", "webViewGetSource",
      "webViewGetOverrideUrl"]),
    web: __sceneCore.concat(["request", "upConfig"]),
    url: __sceneCore.concat(["getUserAgent", "getHeaderMap"]),
    login: __sceneCore.concat(["upLoginData", "upUiData", "reUiView", "addBook",
      "getLoginInfoMap", "getLoginInfo", "putLoginInfo", "setLoginInfo",
      "removeLoginInfo", "getLoginHeader", "putLoginHeader", "removeLoginHeader",
      "getLoginJs", "getHeaderMap", "startBrowser", "startBrowserAwait",
      "showBrowser", "reLoginView", "getVerificationCode", "toast", "longToast",
      "refreshBookInfo", "refreshBookToc", "refreshContent", "refreshExplore",
      "copyText", "clearTtsCache", "getCookie", "setCookie"]),
    rss: __sceneCore.concat(["getString", "getStringList"]),
    replace: __sceneCore.concat(["replaceFont", "queryTTF"])
  };
  function __javaForScene(scene) {
    var s = String(scene || "").toLowerCase();
    if (!s || !__javaScenes[s]) return java;
    var allow = __javaScenes[s];
    var view = {};
    allow.forEach(function (k) {
      if (typeof java[k] === "function") {
        view[k] = function () { return java[k].apply(java, arguments); };
      } else if (java[k] !== undefined) {
        view[k] = java[k];
      }
    });
    view.__scene = s;
    return view;
  }
  globalThis.__javaForScene = __javaForScene;

  function __pad(n) { return n < 10 ? "0" + n : "" + n; }
  // sh：时区偏移（小时）；叠加到时间戳后再按 utc 标志取值。
  function __timeFormat(time, pattern, utc, sh) {
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
    var off = Number(sh) || 0;
    if (off) d = new Date(d.getTime() + off * 3600000);
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
    __state.toastRecords = [];
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
      toastRecords: __state.toastRecords || [],
      hosts: __state.hosts,
      browser: __state.browser,
      uiEvents: __state.uiEvents || [],
      clipboard: __state.clipboard || "",
      config: __state.config || {},
      ruleContext: __state.ruleContext || {},
      error: err ? ((err && err.stack) ? String(err.stack) : String(err)) : null
    });
  };
''';
