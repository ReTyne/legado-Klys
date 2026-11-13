/// 由 legado_js_runtime.dart 按「一类一文件」拆出的 WebViewLegadoJs。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../legado_js_runtime.dart';

/// 无头 WebView 真 JS 运行时。
class WebViewLegadoJs implements LegadoJs {
  WebViewLegadoJs(this.source);

  JsSource source;
  iw.HeadlessInAppWebView? _headless;
  iw.InAppWebViewController? _controller;
  final Completer<void> _ready = Completer<void>();
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 40),
    followRedirects: true,
    validateStatus: (s) => s != null && s < 600,
    responseType: ResponseType.bytes,
  ));
  final DatabaseService _db = DatabaseService();

  String? _loadedSourceUrl;
  String? _deviceId;

  bool get _persistCookie => source.enabledCookieJar;

  static const Duration _ensureTimeout = Duration(seconds: 15);

  Future<void> _ensure() async {
    if (_headless != null) {
      // 已创建：等待就绪，同样带超时，避免 onLoadStop 永不到来导致整条链路挂死
      await _ready.future.timeout(_ensureTimeout);
      return;
    }
    final settings = iw.InAppWebViewSettings(
      javaScriptEnabled: true,
      domStorageEnabled: true,
      databaseEnabled: true,
      allowFileAccess: true,
      useShouldInterceptRequest: true,
      javaScriptCanOpenWindowsAutomatically: true,
      mixedContentMode: iw.MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
      userAgent:
          'Mozilla/5.0 (Linux; Android 13; Pixel 6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
    );
    _headless = iw.HeadlessInAppWebView(
      initialSettings: settings,
      initialUrlRequest: iw.URLRequest(url: iw.WebUri('about:blank')),
      onWebViewCreated: (controller) {
        _controller = controller;
        controller.addJavaScriptHandler(
            handlerName: 'legadoBrowser', callback: _onBrowserRequest);
        // 验证码识别：书源 JS 的 getVerificationCode(imageUrl) 返回 Promise，
        // 此处弹人工输入界面，用户提交后回传结果 resolve Promise。
        controller.addJavaScriptHandler(
            handlerName: 'legadoVerification', callback: _onVerificationRequest);
      },
      onLoadStop: (controller, url) async {
        try {
          await controller.evaluateJavascript(source: AesJsLib.code);
          await controller.evaluateJavascript(source: LegadoBridgeJs.code);
          if (!_ready.isCompleted) _ready.complete();
        } catch (e) {
          if (!_ready.isCompleted) _ready.completeError(e);
        }
      },
      shouldInterceptRequest: (controller, request) => _intercept(request),
    );
    await _headless!.run();
    // 关键兜底：WebView 就绪带超时。若无超时，onLoadStop 不触发时
    // await _ready.future 会永久挂起——这正是"书源调试卡死转圈"的根因。
    await _ready.future.timeout(_ensureTimeout);
  }

  @override
  Future<void> loadSource(JsSource src) async {
    source = src;
    await _ensure();
    if (_loadedSourceUrl == src.jsUrl) return;
    final c = _controller!;
    final seed = '''
      __state.meta = {url: ${_js(src.jsUrl)}, name: ${_js(src.jsName)}, httpUrl: ${_js(src.jsHttpUrl)}};
      __state.variable = ${_js(src.variable ?? '')};
      __state.variableComment = ${_js(src.variableComment ?? '')};
      __state.lastUpdateTime = ${src.lastUpdateTime ?? 0};
      globalThis.result = {}; globalThis.key = ''; globalThis.page = 1; globalThis.baseUrl = '';
      globalThis.sourceUrl = ${_js(src.jsUrl)};
      globalThis.sourceName = ${_js(src.jsName)};
      // 注意：不要覆盖 globalThis.source —— bridge 已定义带 getVariable/putLoginInfo
      // 等完整方法的 source 对象（数据全部从 __state.meta 读取），这里只需更新 meta。
      globalThis.book = __wrapBook({}); globalThis.chapter = __wrapChapter({}); globalThis.rssArticle = {}; globalThis.\$ = globalThis.result;
    ''';
    await c.evaluateJavascript(source: seed);
    // eventListener：开启后把书源 JS 的 console 输出桥接进引擎调试日志，
    // 使「调试」页能看到脚本内的 console.log/warn/error（对齐脚本日志排查需求）。
    if (src is BookSource && (src).eventListener) {
      try {
        await c.evaluateJavascript(source: '''
          (function(){
            function hook(level, orig){
              return function(){
                try {
                  var s = Array.prototype.map.call(arguments, function(a){ return String(a); }).join(' ');
                  __state.logs.push(level + s);
                } catch (e) {}
                try { orig.apply(console, arguments); } catch (e2) {}
              };
            }
            console.log = hook('', console.log.bind(console));
            console.warn = hook('[warn] ', console.warn.bind(console));
            console.error = hook('[err] ', console.error.bind(console));
          })()
        ''');
      } catch (e) {
        debugPrint('eventListener console 桥接失败: $e');
      }
    }
    final lib = (src.jsLib ?? '').trim();
    if (lib.isNotEmpty) {
      try {
        await c.evaluateJavascript(source: lib);
      } catch (e) {
        debugPrint('jsLib 求值失败: $e');
        SourceNetworkLog.instance
            .addScriptError('jsLib 加载失败: $e');
      }
    }
    final login = (src.loginUrl ?? '').trim();
    if (login.isNotEmpty) {
      try {
        await c.evaluateJavascript(source: login);
      } catch (e) {
        debugPrint('loginUrl 初始化失败: $e');
        SourceNetworkLog.instance
            .addScriptError('loginUrl（登录脚本）加载失败: $e');
      }
    }
    _loadedSourceUrl = src.jsUrl;
  }

  /// JS→原生：网页登录请求（startBrowserAwait 等）。
  Future<dynamic> _onBrowserRequest(List<dynamic> args) async {
    try {
      final m = jsonDecode(args.first.toString()) as Map<String, dynamic>;
      final id = m['id']?.toString() ?? '';
      final url = m['url']?.toString() ?? '';
      final title = m['title']?.toString() ?? '登录';
      final nav = appNavigatorKey.currentState;
      String cookieStr = '';
      final finalUrl = url;
      if (nav != null && url.isNotEmpty) {
        await nav.push(MaterialPageRoute(
            builder: (_) => BrowserScreen(url: url, title: title)));
        try {
          final cookies =
              await iw.CookieManager.instance().getCookies(url: iw.WebUri(url));
          cookieStr = cookies
              .where((ck) => ck.name.isNotEmpty && ck.value != null)
              .map((ck) => '${ck.name}=${ck.value}')
              .join('; ');
          if (cookieStr.isNotEmpty) {
            CookieManager().saveFromResponse(url, [cookieStr]);
            final host = Uri.tryParse(url)?.host ?? '';
            if (_persistCookie && host.isNotEmpty) {
              await _db.saveCookie(host, cookieStr);
            }
          }
        } catch (_) {}
      }
      await _controller?.evaluateJavascript(
          source: '__resolveBrowser(${_js(id)}, ${_js(cookieStr)}, ${_js(finalUrl)});');
    } catch (_) {}
    return null;
  }

  /// 构造验证码图片请求头（
  /// `OkHttpModelLoader.sourceOriginOption`）：书源 header + 会话 Cookie +
  /// Referer，保证带登录态 / 防盗链的验证码图能正常加载。
  Future<Map<String, String>> _verificationHeaders(String imageUrl) async {
    final out = <String, String>{};
    final raw = source.header;
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final v = jsonDecode(raw);
        if (v is Map) {
          v.forEach((k, val) => out[k.toString()] = val?.toString() ?? '');
        }
      } catch (_) {}
    }
    try {
      final ck = CookieManager().cookieHeader(imageUrl);
      if (ck != null && ck.isNotEmpty && !out.containsKey('Cookie')) {
        out['Cookie'] = ck;
      }
      // 持久化 CookieJar 时内存可能为空，回退到 DB 中同域 Cookie
      if (!out.containsKey('Cookie') && _persistCookie) {
        final host = Uri.tryParse(imageUrl)?.host ?? '';
        if (host.isNotEmpty) {
          final saved = await _db.getCookie(host);
          if (saved != null && saved.isNotEmpty) out['Cookie'] = saved;
        }
      }
    } catch (_) {}
    final referer =
        source.jsHttpUrl.isNotEmpty ? source.jsHttpUrl : source.jsUrl;
    if (referer.startsWith('http')) out.putIfAbsent('Referer', () => referer);
    return out;
  }

  /// JS→原生：验证码识别请求（getVerificationCode）。
  /// 弹出人工输入界面，用户提交的字符回传给 JS resolve Promise；
  /// 取消/无 Navigator 时回传空串。
  Future<dynamic> _onVerificationRequest(List<dynamic> args) async {
    try {
      final m = jsonDecode(args.first.toString()) as Map<String, dynamic>;
      final id = m['id']?.toString() ?? '';
      final imageUrl = m['imageUrl']?.toString() ?? '';
      final nav = appNavigatorKey.currentState;
      String code = '';
      if (nav != null && imageUrl.isNotEmpty) {
        final headers = await _verificationHeaders(imageUrl);
        final result = await nav.push<String>(MaterialPageRoute(
            builder: (_) => VerificationCodeScreen(
                imageUrl: imageUrl,
                sourceName: source.jsName,
                headers: headers)));
        code = result ?? '';
      }
      await _controller?.evaluateJavascript(
          source: '__resolveVerification(${_js(id)}, ${_js(code)});');
    } catch (_) {
      // 异常时也要 resolve，避免 JS Promise 永久挂起
      try {
        final m = jsonDecode(args.first.toString()) as Map<String, dynamic>;
        final id = m['id']?.toString() ?? '';
        await _controller?.evaluateJavascript(
            source: '__resolveVerification(${_js(id)}, "");');
      } catch (_) {}
    }
    return null;
  }

  /// 原生接管书源 JS 发起的所有 XHR（绕过 CORS、统一 Cookie/编码）。
  Future<iw.WebResourceResponse?> _intercept(iw.WebResourceRequest request) async {
    final uri = request.url;
    final url = uri.toString();

    // 自定义 legado:// 协议上的同步 XHR（POST + X-Legado-Body 等自定义头）
    // 可能触发 CORS 预检 OPTIONS：统一放行，避免预检落进具体 handler 导致
    // 真正的 POST 请求被浏览器拦下（与下方 http 分支的 OPTIONS 处理同义）。
    if (url.startsWith('legado://') &&
        (request.method ?? 'GET').toUpperCase() == 'OPTIONS') {
      return iw.WebResourceResponse(
        statusCode: 200,
        reasonPhrase: 'OK',
        contentType: 'text/plain',
        contentEncoding: 'utf-8',
        data: Uint8List(0),
        headers: _corsHeaders(),
      );
    }

    // 内部协议：zip 解压 / TTF 字体反爬 / 下载 / 分享（书源 JS 通过同步 XHR 调用）
    if (url.startsWith('legado://zip')) return await _handleZip(uri);
    // java.strToBytes / bytesToStr / htmlFormat / toNumChapter 转交 Dart 侧
    // JsTextUtils（Flutter 侧无 Java Charset.forName 全字符集能力，由
    // enough_convert + 纯 Dart 正则提供唯一权威语义，避免 JS/Dart 两套漂移）。
    if (url.startsWith('legado://charset')) {
      return await _handleCharset(request, uri);
    }
    if (url.startsWith('legado://crypto')) {
      return await _handleCrypto(request);
    }
    if (url.startsWith('legado://ttf')) return await _handleTtf(request);
    if (url.startsWith('legado://download')) return await _handleDownload(uri);
    if (url.startsWith('legado://share')) return await _handleShare(request);
    if (url.startsWith('legado://file')) return await _handleFile(uri);
    if (url.startsWith('legado://webview')) return await _handleWebView(uri);
    if (url.startsWith('legado://browser')) {
      return await _handleBrowser(request, uri);
    }
    if (url.startsWith('legado://searchbook')) return await _handleSearchBook(uri);
    if (url.startsWith('legado://openlogin')) return await _handleOpenLogin(uri);
    if (url.startsWith('legado://refreshexplore')) return await _handleRefreshExplore();
    if (url.startsWith('legado://verificationcode')) {
      return await _handleVerificationCode(uri);
    }
    // 书源脚本发同步 XHR 到该协议，转交
    // MethodChannel('legado/video') 由 Kotlin 原生播放器打开（互相联系）。
    if (url.startsWith('legado://video')) return await _handleVideo(uri);
    // java.ajaxAll 批量并发 / java.webViewGetOverrideUrl 重定向嗅探
    if (url.startsWith('legado://ajaxall')) return await _handleAjaxAll(request);
    if (url.startsWith('legado://overrideurl')) {
      return await _handleWebViewOverride(request);
    }

    if (!url.startsWith('http')) return null;
    final method = (request.method ?? 'GET').toUpperCase();

    if (method == 'OPTIONS') {
      return iw.WebResourceResponse(
        statusCode: 200,
        reasonPhrase: 'OK',
        contentType: 'text/plain',
        contentEncoding: 'utf-8',
        data: Uint8List(0),
        headers: _corsHeaders(),
      );
    }

    final headers = <String, String>{};
    (request.headers ?? <String, String>{}).forEach((k, v) {
      headers[k] = v;
    });

    // POST body 通过自定义请求头携带（WebResourceRequest 不暴露 body）
    Uint8List? bodyBytes;
    final b64body = headers.remove('X-Legado-Body');
    if (b64body != null && b64body.isNotEmpty) {
      try {
        bodyBytes = base64Decode(b64body);
      } catch (_) {}
    }

    final hasCookie =
        headers.keys.any((k) => k.toLowerCase() == 'cookie');
    if (!hasCookie) {
      final ck = CookieManager().cookieHeader(url);
      if (ck != null && ck.isNotEmpty) headers['Cookie'] = ck;
    }

    // 书源 JS 可通过自定义头单次指定请求选项：超时、是否跟随重定向、
    // 是否用 WebView 渲染。这些头不转发给目标站，取出后即从 headers 移除。
    int? optTimeoutMs;
    var optFollowRedirects = true;
    var optWebView = false;
    final tRaw = headers.remove('X-Legado-Timeout');
    if (tRaw != null) optTimeoutMs = int.tryParse(tRaw);
    final frRaw = headers.remove('X-Legado-FollowRedirects');
    if (frRaw != null) {
      optFollowRedirects = frRaw != '0' && frRaw.toLowerCase() != 'false';
    }
    final wvRaw = headers.remove('X-Legado-WebView');
    if (wvRaw != null) {
      optWebView = wvRaw == '1' || wvRaw.toLowerCase() == 'true';
    }
    final reqHeaders = Map<String, String>.from(headers);

    final sw = Stopwatch()..start();
    // webView 选项：先尝试无头 WebView 渲染（JS 动态填充的页面），
    // 失败/为空时降级为普通 HTTP 请求。
    if (optWebView) {
      try {
        final rendered = await HeadlessWebViewFetcher.fetch(
          url: url,
          headers: headers,
          timeoutMs: optTimeoutMs ?? 15000,
        );
        if (rendered.isNotEmpty) {
          SourceNetworkLog.instance.record(
            url: url,
            method: method,
            origin: 'js-webview',
            statusCode: 200,
            durationMs: sw.elapsedMilliseconds,
            text: rendered,
            requestHeaders: reqHeaders,
            responseHeaders: const {'content-type': 'text/html; charset=utf-8'},
            finalUrl: url,
          );
          final outHeaders = _corsHeaders();
          outHeaders['Content-Type'] = 'text/html; charset=utf-8';
          return iw.WebResourceResponse(
            statusCode: 200,
            reasonPhrase: 'OK',
            contentType: 'text/html; charset=utf-8',
            contentEncoding: 'utf-8',
            data: Uint8List.fromList(utf8.encode(rendered)),
            headers: outHeaders,
          );
        }
      } catch (_) {}
    }

    try {
      final resp = await _dio.request<List<int>>(
        url,
        data: bodyBytes,
        options: Options(
          method: method,
          headers: headers,
          responseType: ResponseType.bytes,
          followRedirects: optFollowRedirects,
          sendTimeout: optTimeoutMs != null
              ? Duration(milliseconds: optTimeoutMs)
              : null,
          receiveTimeout: optTimeoutMs != null
              ? Duration(milliseconds: optTimeoutMs)
              : null,
        ),
      );
      final status = resp.statusCode ?? 200;
      // 重定向链与最终地址（dio 自动跟随重定向时 resp.redirects 记录每跳）。
      final redirects = <String>[url];
      for (final r in resp.redirects) {
        redirects.add(r.location.toString());
      }
      var finalUrl = resp.realUri.toString();
      if (finalUrl.isEmpty) finalUrl = url;
      if (optFollowRedirects && redirects.length == 1 && finalUrl != url) {
        redirects.add(finalUrl);
      }
      final respHeaders = <String, String>{};
      resp.headers.map.forEach((k, vals) {
        respHeaders[k] = vals.join('; ');
      });
      // 书源 JS 的 java.ajax 走这条拦截通道，不经 BookSourceEngine._fetch。
      // 记入全局网络日志，调试页/登录页才能看到真实的请求与响应。
      SourceNetworkLog.instance.record(
        url: url,
        method: method,
        origin: 'js-ajax',
        statusCode: status,
        durationMs: sw.elapsedMilliseconds,
        body: resp.data,
        error: status >= 400 ? 'HTTP $status' : null,
        requestHeaders: reqHeaders,
        responseHeaders: respHeaders,
        finalUrl: finalUrl,
        redirects: redirects,
      );
      final setCookies = resp.headers.map['set-cookie'] ?? const <String>[];
      CookieManager().saveFromResponse(url, setCookies);
      if (_persistCookie) {
        final ck = CookieManager().cookieHeader(url);
        if (ck != null && ck.isNotEmpty) {
          await _db.saveCookie(uri.host, ck);
        }
      }
      final outHeaders = _corsHeaders();
      var contentType = 'text/plain; charset=utf-8';
      resp.headers.map.forEach((k, vals) {
        if (k.toLowerCase() == 'content-type') contentType = vals.join(';');
      });
      if (setCookies.isNotEmpty) {
        outHeaders['X-Set-Cookie'] = setCookies.join('\n');
      }
      outHeaders['Content-Type'] = contentType;
      return iw.WebResourceResponse(
        statusCode: status,
        reasonPhrase: _reason(status),
        contentType: contentType,
        contentEncoding: 'utf-8',
        data: Uint8List.fromList(resp.data ?? const <int>[]),
        headers: outHeaders,
      );
    } catch (e) {
      // 客户端侧的 DNS / 连接 / 超时失败此前一律伪装成 502，用户无从判断
      // 是服务器挂了还是本机网络问题。保留 502 兼容书源逻辑，但把原始错误
      // 写进日志与响应头，并在响应体给出可操作说明。
      final reason = '请求失败: $e';
      SourceNetworkLog.instance.record(
        url: url,
        method: method,
        origin: 'js-ajax',
        statusCode: 502,
        durationMs: sw.elapsedMilliseconds,
        error: reason,
      );
      final outHeaders = _corsHeaders();
      outHeaders['X-Legado-Error'] = Uri.encodeComponent(reason);
      return iw.WebResourceResponse(
        statusCode: 502,
        reasonPhrase: 'Bad Gateway',
        contentType: 'text/plain; charset=utf-8',
        contentEncoding: 'utf-8',
        data: Uint8List.fromList(utf8.encode(reason)),
        headers: outHeaders,
      );
    }
  }

  /// legado://zip 协议：zip 内取文件内容 / 整包解压（书源 java.getZipStringContent/unzipFile）。
  /// kind=7z|rar 时转交 Android 原生解压（commons-compress / junrar），见 ArchiveNative。
  Future<iw.WebResourceResponse> _handleZip(iw.WebUri uri) async {
    try {
      final kind = (uri.queryParameters['kind'] ?? 'zip').toLowerCase();
      final op = uri.queryParameters['op'] ?? '';
      final zipUrl = uri.queryParameters['url'] ?? '';
      final path = uri.queryParameters['path'] ?? '';
      if (zipUrl.isEmpty) return _textResponse('zip url 为空', 400);
      final bytes = await _fetchBytes(zipUrl);
      if (bytes.isEmpty) return _textResponse('压缩包下载为空', 502);

      // 7z / rar：原生解压通道（Dart 无 7z/rar 解码器）
      if (kind == '7z' || kind == 'rar') {
        if (op == 'unarchive') {
          final dir = await ArchiveNative.extractAll(bytes, kind);
          if (dir == null) return _textResponse('$kind 解压失败（原生通道不可用）', 502);
          return _textResponse(dir, 200);
        }
        // op=bytes： get7z/getRarByteArrayContent，返回原始字节的 base64，
        // 由 JS 侧 __b64ToBytes 还原为 Uint8Array，避免 utf8 解码破坏二进制。
        if (op == 'bytes') {
          final raw = await ArchiveNative.extractEntryBytes(bytes, kind, path);
          if (raw == null) return _textResponse('$kind 内未找到文件: $path', 404);
          return _textResponse(base64Encode(raw), 200);
        }
        final content = await ArchiveNative.extractEntry(bytes, kind, path);
        if (content == null) return _textResponse('$kind 内未找到文件: $path', 404);
        return _textResponse(content, 200);
      }

      final archive = ZipDecoder().decodeBytes(bytes);
      if (op == 'unarchive') {
        // 整包解压到 legado_files/unzip/<md5(名)>，返回相对目录
        final dir = await _unzipDir(zipUrl);
        for (final f in archive.files) {
          if (!f.isFile) continue;
          final name = f.name.split('/').last;
          if (name.isEmpty) continue;
          final out = File('$dir/$name');
          if (!out.parent.existsSync()) out.parent.createSync(recursive: true);
          final data = f.content;
          await out.writeAsBytes(data is List<int> ? data : const <int>[]);
        }
        return _textResponse(p.relative(dir, from: (await _filesBase()).path), 200);
      }
      for (final f in archive.files) {
        if (!f.isFile) continue;
        if (path.isNotEmpty && f.name != path && !f.name.endsWith('/$path')) {
          continue;
        }
        final data = f.content;
        // op=bytes： getZipByteArrayContent，返回条目的原始字节 base64。
        if (op == 'bytes') {
          final raw = data is String ? utf8.encode(data) : List<int>.from(data as List<int>);
          return _textResponse(base64Encode(raw), 200);
        }
        final String content;
        if (data is String) {
          content = data;
        } else if (data is List<int>) {
          content = utf8.decode(data);
        } else {
          content = utf8.decode(f.content as List<int>);
        }
        return iw.WebResourceResponse(
          statusCode: 200,
          reasonPhrase: 'OK',
          contentType: 'text/plain; charset=utf-8',
          contentEncoding: 'utf-8',
          data: Uint8List.fromList(utf8.encode(content)),
        );
      }
      return _textResponse('zip 内未找到文件: $path', 404);
    } catch (e) {
      return _textResponse('zip 解压失败: $e', 502);
    }
  }

  /// 下载 URL / 读取 legado://file 相对路径对应字节（zip 协议的数据来源）。
  Future<Uint8List> _fetchBytes(String urlOrPath) async {
    if (urlOrPath.startsWith('http')) {
      final resp = await _dio.get<List<int>>(urlOrPath,
          options: Options(responseType: ResponseType.bytes));
      return resp.data == null ? Uint8List(0) : Uint8List.fromList(resp.data!);
    }
    final base = await _filesBase();
    final f = File('${base.path}/$urlOrPath');
    if (!f.existsSync()) return Uint8List(0);
    return f.readAsBytesSync();
  }

  Future<Directory> _filesBase() async {
    final dir = await getApplicationDocumentsDirectory();
    final base = Directory('${dir.path}/legado_files');
    if (!base.existsSync()) base.createSync(recursive: true);
    return base;
  }

  Future<String> _unzipDir(String zipUrl) async {
    final base = await _filesBase();
    final key = md5.convert(utf8.encode(zipUrl)).toString();
    final dir = Directory('${base.path}/unzip/$key');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir.path;
  }

  /// legado://ttf 协议：解析字体反爬映射（java.queryTTF）。请求体为 base64 字体数据。
  Future<iw.WebResourceResponse> _handleTtf(iw.WebResourceRequest request) async {
    try {
      final b64 = (request.headers ?? const <String, String>{})['X-Legado-Body'] ?? '';
      if (b64.isEmpty) return _textResponse('ttf 数据为空', 400);
      // X-Legado-Body 由 __b64Unicode(bodyStr) 生成，bodyStr 是字体数据的 base64 文本，
      // 故需两层解码：先还原 bodyStr，再解码出字体字节。
      final bodyStrBytes = base64Decode(b64);
      final bodyStr = utf8.decode(bodyStrBytes);
      final bytes = base64Decode(bodyStr);
      final data = TtfParser.fromBytes(bytes).buildQueryData();
      final json = jsonEncode(data);
      return iw.WebResourceResponse(
        statusCode: 200,
        reasonPhrase: 'OK',
        contentType: 'application/json; charset=utf-8',
        contentEncoding: 'utf-8',
        data: Uint8List.fromList(utf8.encode(json)),
        headers: _corsHeaders(),
      );
    } catch (e) {
      return _textResponse('ttf 解析失败: $e', 502);
    }
  }

  /// legado://download 协议：下载文件到应用文档目录，返回本地路径（java.download）。
  Future<iw.WebResourceResponse> _handleDownload(iw.WebUri uri) async {
    try {
      final url = uri.queryParameters['url'] ?? '';
      if (url.isEmpty) return _textResponse('download url 为空', 400);
      final resp = await _dio.get<List<int>>(url,
          options: Options(responseType: ResponseType.bytes));
      final bytes = resp.data ?? const <int>[];
      final dir = await getApplicationDocumentsDirectory();
      final dlDir = Directory('${dir.path}/downloads');
      if (!dlDir.existsSync()) dlDir.createSync(recursive: true);
      var name = url.split('/').last.split('?').first;
      if (name.isEmpty) name = 'download_${DateTime.now().millisecondsSinceEpoch}';
      final file = File('${dlDir.path}/$name');
      await file.writeAsBytes(bytes);
      return _textResponse(file.path, 200);
    } catch (e) {
      return _textResponse('download 失败: $e', 502);
    }
  }

  /// legado://share 协议：分享文本（java.share）。请求体为文本。
  Future<iw.WebResourceResponse> _handleShare(iw.WebResourceRequest request) async {
    try {
      final b64 = (request.headers ?? const <String, String>{})['X-Legado-Body'] ?? '';
      String text = '';
      if (b64.isNotEmpty) {
        text = utf8.decode(base64Decode(b64));
      }
      if (text.isEmpty) return _textResponse('false', 200);
      final ctx = appNavigatorKey.currentState?.context;
      if (ctx != null) {
        await Share.share(text);
        return _textResponse('true', 200);
      }
      return _textResponse('false', 200);
    } catch (e) {
      return _textResponse('false', 200);
    }
  }

  /// legado://charset 协议：把书源脚本的 4 个文本/编码扩展函数转交 Dart 侧
  /// [JsTextUtils]，使上游 JsExtensions.kt / StringUtils.kt / HtmlFormatter.kt
  /// 的语义只有一份权威实现（JS 桥只做参数封送，不再各写一套简化正则）。
  ///
  /// 请求体沿用 `__doXhr` 的 `X-Legado-Body`（`__b64Unicode`：UTF-8 base64）；
  /// 返回体为 `text/plain`：
  ///  * `op=encode`       body=原串，返回字节数组的 JSON（`[214,208,...]`）
  ///  * `op=decode`       body=字节数组 JSON，返回按 charset 解码的字符串
  ///  * `op=htmlFormat`   body=HTML，返回 formatKeepImg 结果
  ///  * `op=toNumChapter` body=章节名，返回数字归一化后的章节名
  /// `cs` 为 Java 风格 charset 名（GBK / GB_2312 / ISO-8859-1 / UTF-8 ...）。
  Future<iw.WebResourceResponse> _handleCharset(
      iw.WebResourceRequest request, iw.WebUri uri) async {
    try {
      final op = uri.queryParameters['op'] ?? '';
      final cs = uri.queryParameters['cs'];
      final b64 =
          (request.headers ?? const <String, String>{})['X-Legado-Body'] ?? '';
      final body = b64.isEmpty
          ? ''
          : utf8.decode(base64Decode(b64), allowMalformed: true);
      switch (op) {
        case 'encode':
          return _textResponse(
              jsonEncode(JsTextUtils.strToBytes(body, charset: cs)), 200);
        case 'decode':
          final arr = (jsonDecode(body) as List?) ?? const <dynamic>[];
          final bytes = arr
              .map((e) => (e is num ? e.toInt() : 0) & 0xff)
              .toList();
          return _textResponse(JsTextUtils.bytesToStr(bytes, charset: cs), 200);
        case 'htmlFormat':
          return _textResponse(JsTextUtils.htmlFormat(body), 200);
        case 'toNumChapter':
          return _textResponse(JsTextUtils.toNumChapter(body) ?? '', 200);
        default:
          return _textResponse('unknown op', 400);
      }
    } catch (e) {
      return _textResponse('charset 处理失败: $e', 502);
    }
  }

  /// legado://crypto 协议：对称加解密（DES / 3DES / DESede / AES / SM4 / RC4，
  /// 支持 ECB/CBC/PCBC/CFB/OFB/CTR 与 PKCS5/PKCS7/NoPadding）。
  /// 请求体为 base64(JSON)，字段：op / transformation / key / iv / data，
  /// 其中 key/iv/data 为字节的 base64。响应体为处理后字节的 base64。
  /// 书源 JS 侧由此得到与 createSymmetricCrypto 一致的字节结果，再按需转成
  /// 数组 / hex / base64 / 字符串。
  Future<iw.WebResourceResponse> _handleCrypto(
      iw.WebResourceRequest request) async {
    try {
      final b64 =
          (request.headers ?? const <String, String>{})['X-Legado-Body'] ?? '';
      if (b64.isEmpty) return _textResponse('crypto 参数为空', 400);
      final jsonStr = utf8.decode(base64Decode(b64), allowMalformed: true);
      final decoded = jsonDecode(jsonStr);
      if (decoded is! Map) return _textResponse('crypto 参数格式错误', 400);
      final m = decoded;
      final op = m['op']?.toString() ?? 'encrypt';
      final transformation =
          m['transformation']?.toString() ?? 'AES/ECB/PKCS5Padding';
      final keyBytes = Uint8List.fromList(
          base64Decode((m['key']?.toString() ?? '').trim()));
      final ivRaw = (m['iv']?.toString() ?? '').trim();
      Uint8List? ivBytes;
      if (ivRaw.isNotEmpty) {
        ivBytes = Uint8List.fromList(base64Decode(ivRaw));
      }
      final dataBytes = Uint8List.fromList(
          base64Decode((m['data']?.toString() ?? '').trim()));
      final cipher = SymmetricCrypto(transformation, keyBytes, iv: ivBytes);
      final Uint8List out;
      switch (op) {
        case 'decrypt':
        case 'decryptBytes':
          out = cipher.decryptBytes(dataBytes);
          break;
        case 'digestHex':
        case 'digestBase64':
        case 'hmacHex':
        case 'hmacBase64':
          // 摘要/HMAC 走纯 JS 实现即可，这里只保留对称加解密通道。
          return _textResponse('unsupported op: $op', 400);
        default:
          out = cipher.encrypt(dataBytes);
      }
      return _textResponse(base64.encode(out), 200);
    } catch (e) {
      return _textResponse('crypto 处理失败: $e', 502);
    }
  }

  /// legado://video 协议：java.openVideoPlayer(url, title)。
  /// 转交 MethodChannel('legado/video') 的 Kotlin 原生视频播放器；通道不可用时
  /// 返回 'false' 让书源脚本静默降级。
  Future<iw.WebResourceResponse> _handleVideo(iw.WebUri uri) async {
    final vUri = Uri.tryParse(uri.toString());
    final url = vUri?.queryParameters['url'] ?? '';
    final title = vUri?.queryParameters['title'] ?? '';
    if (url.isEmpty) return _textResponse('false', 200);
    try {
      final ok = await LegadoBridgeJs.openVideoPlayer(url, title);
      return _textResponse(ok ? 'true' : 'false', 200);
    } catch (e) {
      return _textResponse('false', 200);
    }
  }

  /// legado://ajaxall 协议：java.ajaxAll(urlList) 的真并发实现。
  /// 书源 JS 把整批请求作为 JSON POST 到这里；Dart 侧用 Future.wait 同时
  /// 发起所有 HTTP 请求，Future.wait 保证结果顺序与入参一致，最后按序
  /// 回传 JSON 数组（每项含 url/body/code/message/headers）。
  Future<iw.WebResourceResponse> _handleAjaxAll(
      iw.WebResourceRequest request) async {
    final b64 =
        (request.headers ?? const <String, String>{})['X-Legado-Body'] ?? '';
    List<dynamic> items;
    try {
      final decoded = jsonDecode(utf8.decode(base64Decode(b64)));
      items = decoded is List ? decoded : const <dynamic>[];
    } catch (_) {
      return _textResponse('[]', 400);
    }
    // 为每个 URL 建独立 Future；Future.wait 真并发，单项失败不影响整批。
    final futures = <Future<Map<String, dynamic>>>[
      for (final item in items) _fetchOneAjax(item),
    ];
    final results = await Future.wait(futures);
    // 带 CORS 头：POST + 自定义头场景下 XHR 才能读到响应体
    return iw.WebResourceResponse(
      statusCode: 200,
      reasonPhrase: 'OK',
      contentType: 'application/json; charset=utf-8',
      contentEncoding: 'utf-8',
      data: Uint8List.fromList(utf8.encode(jsonEncode(results))),
      headers: _corsHeaders(),
    );
  }

  /// 单个 ajaxAll 请求：复用与 _intercept 相同的 Dio / CookieJar / 持久 Cookie
  /// 逻辑，失败时返回 502 项。
  Future<Map<String, dynamic>> _fetchOneAjax(dynamic item) async {
    final map = item is Map ? item : const <String, dynamic>{};
    final url = map['url']?.toString() ?? '';
    final method = (map['method']?.toString() ?? 'GET').toUpperCase();
    if (url.isEmpty || !url.startsWith('http')) {
      return <String, dynamic>{
        'url': url,
        'body': '',
        'code': 502,
        'message': 'Error',
        'headers': <String, dynamic>{},
      };
    }
    final headers = <String, String>{};
    final h = map['headers'];
    if (h is Map) {
      h.forEach((k, v) => headers[k.toString()] = v?.toString() ?? '');
    }
    if (!headers.keys.any((k) => k.toLowerCase() == 'cookie')) {
      final ck = CookieManager().cookieHeader(url);
      if (ck != null && ck.isNotEmpty) headers['Cookie'] = ck;
    }
    dynamic bodyData;
    final rawBody = map['body'];
    if (rawBody != null && method != 'GET' && method != 'HEAD') {
      bodyData = rawBody is String ? rawBody : jsonEncode(rawBody);
    }
    try {
      final resp = await _dio.request<List<int>>(
        url,
        data: bodyData,
        options: Options(
          method: method,
          headers: headers,
          responseType: ResponseType.bytes,
        ),
      );
      final setCookies = resp.headers.map['set-cookie'] ?? const <String>[];
      CookieManager().saveFromResponse(url, setCookies);
      if (_persistCookie) {
        final ck = CookieManager().cookieHeader(url);
        if (ck != null && ck.isNotEmpty) {
          await _db.saveCookie(Uri.parse(url).host, ck);
        }
      }
      final code = resp.statusCode ?? 200;
      final outHeaders = <String, dynamic>{};
      resp.headers.map.forEach((k, vals) => outHeaders[k] = vals.join(', '));
      if (setCookies.isNotEmpty) {
        outHeaders['X-Set-Cookie'] = setCookies.join('\n');
      }
      return <String, dynamic>{
        'url': url,
        'body': utf8.decode(
            Uint8List.fromList(resp.data ?? const <int>[]),
            allowMalformed: true),
        'code': code,
        'message': _reason(code),
        'headers': outHeaders,
      };
    } catch (e) {
      return <String, dynamic>{
        'url': url,
        'body': '请求失败: $e',
        'code': 502,
        'message': 'Error',
        'headers': <String, dynamic>{},
      };
    }
  }

  /// legado://overrideurl 协议：java.webViewGetOverrideUrl 的真实实现。
  /// 复用 HeadlessWebViewFetcher 的无头 WebView 加载页面，捕获匹配正则的
  /// 请求 URL；无命中时返回页面最终落地 URL（重定向结果）。
  Future<iw.WebResourceResponse> _handleWebViewOverride(
      iw.WebResourceRequest request) async {
    try {
      final b64 =
          (request.headers ?? const <String, String>{})['X-Legado-Body'] ?? '';
      final m = jsonDecode(utf8.decode(base64Decode(b64)))
          as Map<String, dynamic>;
      final url = m['url']?.toString() ?? '';
      if (url.isEmpty) return _textResponse('', 400);
      final headers = <String, String>{};
      final raw = source.header;
      if (raw != null && raw.trim().isNotEmpty) {
        try {
          final v = jsonDecode(raw);
          if (v is Map) {
            v.forEach((k, val) => headers[k.toString()] = val?.toString() ?? '');
          }
        } catch (_) {}
      }
      final result = await HeadlessWebViewFetcher.fetchOverrideUrl(
        url: url,
        html: m['html']?.toString() ?? '',
        urlRegex: m['regex']?.toString() ?? '',
        injectJs: m['js']?.toString() ?? '',
        cacheFirst: m['cacheFirst'] == true,
        delayMs: (m['delayMs'] as num?)?.toInt() ?? 0,
        headers: headers.isEmpty ? null : headers,
      );
      return iw.WebResourceResponse(
        statusCode: 200,
        reasonPhrase: 'OK',
        contentType: 'text/plain; charset=utf-8',
        contentEncoding: 'utf-8',
        data: Uint8List.fromList(utf8.encode(result)),
        headers: _corsHeaders(),
      );
    } catch (_) {
      return _textResponse('', 502);
    }
  }

  /// 路径安全解析。
  /// 书源可通过 path 传入 `../` 试图越界读取应用私有数据，这里做归一化后
  /// 强制落在 legado_files 目录内，越界返回 null。
  File? _safeFile(Directory base, String path) {
    if (path.isEmpty) return null;
    final root = p.normalize(p.absolute(base.path));
    final target = p.normalize(p.absolute('${base.path}/$path'));
    if (target != root && !target.startsWith('$root${Platform.pathSeparator}')) {
      return null;
    }
    return File(target);
  }

  /// legado://file 协议：本地文件读写（java.readTxtFile/importScript/cacheFile/deleteFile/
  /// downloadFile/getTxtInFolder/readFile/getFile）。路径限定在应用文档目录
  /// legado_files 内，越界访问被 [_safeFile] 拒绝。
  Future<iw.WebResourceResponse> _handleFile(iw.WebUri uri) async {
    try {
      final op = uri.queryParameters['op'] ?? '';
      final path = uri.queryParameters['path'] ?? '';
      final url = uri.queryParameters['url'] ?? '';
      final dir = await getApplicationDocumentsDirectory();
      final base = Directory('${dir.path}/legado_files');
      if (!base.existsSync()) base.createSync(recursive: true);
      // 字节读 / 文件信息： JsExtensions.readFile / getFile。
      // 返回 base64（字节）或 JSON（元信息），JS 侧还原成 Uint8Array / File 对象。
      if (op == 'readbytes' || op == 'stat') {
        final f = _safeFile(base, path);
        if (f == null) return _textResponse('非法路径', 400);
        if (op == 'readbytes') {
          if (!f.existsSync()) return _textResponse('', 200);
          return _textResponse(base64Encode(f.readAsBytesSync()), 200);
        }
        final exists = f.existsSync();
        return _textResponse(jsonEncode({
          'path': path,
          'name': p.basename(path),
          'absolutePath': f.path,
          'exists': exists,
          'length': exists ? f.lengthSync() : 0,
        }), 200);
      }
      if (op == 'read') {
        final f = _safeFile(base, path);
        if (f == null || !f.existsSync()) return _textResponse('', 200);
        return _textResponse(f.readAsStringSync(), 200);
      }
      if (op == 'delete') {
        final f = _safeFile(base, path);
        if (f != null && f.existsSync()) f.deleteSync();
        return _textResponse('true', 200);
      }
      if (op == 'cache') {
        final resp = await _dio.get<List<int>>(url,
            options: Options(responseType: ResponseType.bytes));
        var name = url.split('/').last.split('?').first;
        if (name.isEmpty) name = 'cache_${DateTime.now().millisecondsSinceEpoch}';
        final f = File('${base.path}/$name');
        await f.writeAsBytes(resp.data ?? const <int>[]);
        return _textResponse(f.path, 200);
      }
      if (op == 'download' || op == 'writehex') {
        // java.downloadFile：下载/写入文件到 legado_files/<md5(url)>.<type>，
        // 返回相对文件名。
        Uint8List bytes;
        String nameKey;
        if (op == 'writehex') {
          final hex = uri.queryParameters['hex'] ?? '';
          bytes = _hexToBytes(hex);
          nameKey = url;
        } else {
          final resp = await _dio.get<List<int>>(url,
              options: Options(responseType: ResponseType.bytes));
          bytes = Uint8List.fromList(resp.data ?? const <int>[]);
          nameKey = url;
        }
        if (bytes.isEmpty) return _textResponse('', 200);
        var type = Uri.parse(nameKey).queryParameters['type'];
        if (type == null || type.isEmpty) {
          final seg = nameKey.split('/').last.split('?').first;
          type = seg.contains('.') ? seg.split('.').last : 'bin';
        }
        final name = '${md5.convert(utf8.encode(nameKey)).toString()}.$type';
        final f = File('${base.path}/$name');
        await f.writeAsBytes(bytes);
        return _textResponse(name, 200);
      }
      if (op == 'list') {
        // java.getTxtInFolder：拼接文件夹内全部文本内容
        final folder = Directory('${base.path}/$path');
        if (!folder.existsSync()) return _textResponse('[]', 200);
        final files = folder
            .listSync()
            .whereType<File>()
            .where((f) => f.path.toLowerCase().endsWith('.txt'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
        final contents = <String>[];
        for (final f in files) {
          try {
            contents.add(f.readAsStringSync());
          } catch (_) {}
        }
        try {
          folder.deleteSync(recursive: true);
        } catch (_) {}
        return _textResponse(jsonEncode(contents), 200);
      }
      return _textResponse('unknown op', 400);
    } catch (e) {
      return _textResponse('file 操作失败: $e', 502);
    }
  }

  static Uint8List _hexToBytes(String hex) {
    final clean = hex.replaceAll(RegExp(r'\s'), '');
    if (clean.length % 2 != 0) return Uint8List(0);
    final out = Uint8List(clean.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  /// legado://webview 协议：用第二个无头 WebView 加载网页、等 JS 渲染后取渲染 HTML
  /// （java.webViewGetSource）。带超时与失败回退，任何异常返回空串让书源降级。
  Future<iw.WebResourceResponse> _handleWebView(iw.WebUri uri) async {
    try {
      final url = uri.queryParameters['url'] ?? '';
      if (url.isEmpty) return _textResponse('', 400);
      final html = await _renderWithWebView(url).timeout(const Duration(seconds: 25));
      return _textResponse(html, 200);
    } catch (e) {
      return _textResponse('', 502);
    }
  }

  Future<String> _renderWithWebView(String url) async {
    final completer = Completer<String>();
    var disposed = false;
    Future<void> safeDispose(iw.HeadlessInAppWebView h) async {
      if (disposed) return;
      disposed = true;
      try {
        await h.dispose();
      } catch (_) {}
    }

    late final iw.HeadlessInAppWebView h;
    h = iw.HeadlessInAppWebView(
      initialSettings: iw.InAppWebViewSettings(
        javaScriptEnabled: true,
        domStorageEnabled: true,
        useShouldInterceptRequest: false,
        userAgent:
            'Mozilla/5.0 (Linux; Android 13; Pixel 6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
      ),
      initialUrlRequest: iw.URLRequest(url: iw.WebUri(url)),
      onLoadStop: (controller, loadedUrl) async {
        try {
          // 额外等待 JS 渲染
          await Future<void>.delayed(const Duration(seconds: 3));
          final res =
              await controller.evaluateJavascript(source: 'document.documentElement.outerHTML');
          final html = res?.toString() ?? '';
          if (!completer.isCompleted) completer.complete(html);
        } catch (e) {
          if (!completer.isCompleted) completer.complete('');
        } finally {
          await safeDispose(h);
        }
      },
      onReceivedError: (controller, request, error) async {
        if (!completer.isCompleted) completer.complete('');
        await safeDispose(h);
      },
    );
    await h.run();
    return completer.future.timeout(const Duration(seconds: 25), onTimeout: () {
      safeDispose(h);
      return '';
    });
  }

  /// legado://browser 协议：阻塞式网页交互（java.startBrowserAwait/showBrowser/
  /// reLoginView）。同步 XHR 会挂起书源 JS 直到用户关闭浏览器，与 legado 的
  /// 「等待验证结果」语义一致。关闭时回传页面 HTML 作为响应体，同时回收 Cookie。
  Future<iw.WebResourceResponse> _handleBrowser(
      iw.WebResourceRequest request, iw.WebUri uri) async {
    final url = uri.queryParameters['url'] ?? '';
    final title = uri.queryParameters['title'] ?? '登录';
    // refetchAfterSuccess：验证/交互完成后是否用通过验证的 Cookie 重新向原
    // 地址发起一次原生请求，把服务端正文作为响应体返回。书源传 false 或
    // 提供自定义页面内容时，直接回传浏览器里运行后的 DOM。
    final refetch = uri.queryParameters['refetch'] != '0';
    if (url.isEmpty) return _textResponse('', 400);
    final nav = appNavigatorKey.currentState;
    if (nav == null) return _textResponse('', 502);
    // 书源可在第 4 个参数里给出自定义页面内容，此时直接渲染该 HTML。
    String? initialHtml;
    try {
      final b64 =
          (request.headers ?? const <String, String>{})['X-Legado-Body'] ?? '';
      if (b64.isNotEmpty) {
        final decoded = utf8.decode(base64Decode(b64), allowMalformed: true);
        if (decoded.isNotEmpty) initialHtml = decoded;
      }
    } catch (_) {}
    try {
      final result = await nav.push<BrowserCaptureResult>(MaterialPageRoute(
          builder: (_) => BrowserScreen(
              url: url,
              title: title,
              captureHtmlOnExit: true,
              initialHtml: initialHtml)));
      // 渲染后的整页 DOM：书源设置中心等页面把结果写进 DOM/Cookie/hash，
      // 必须回传运行后的内容，否则书源读到原始空白页面。
      var html = result?.html ?? '';
      var finalUrl = result?.finalUrl ?? '';
      var cookieStr = result?.cookies ?? '';
      // 回收登录 Cookie（与 _onBrowserRequest 同逻辑）
      if (cookieStr.isEmpty) {
        try {
          final cookies =
              await iw.CookieManager.instance().getCookies(url: iw.WebUri(url));
          cookieStr = cookies
              .where((ck) => ck.name.isNotEmpty && ck.value != null)
              .map((ck) => '${ck.name}=${ck.value}')
              .join('; ');
        } catch (_) {}
      }
      if (cookieStr.isNotEmpty) {
        CookieManager().saveFromResponse(url, [cookieStr]);
        final host = Uri.tryParse(url)?.host ?? '';
        if (_persistCookie && host.isNotEmpty) {
          await _db.saveCookie(host, cookieStr);
        }
      }
      // 验证成功后重取：仅对真实 http(s) 地址、且未指定自定义页面内容、
      // 且书源未显式关闭 refetch 时生效。重取复用刚回收的 Cookie 与书源
      // 请求头，返回服务端正文；失败或空正文时保留浏览器 DOM 作为兜底。
      if (refetch &&
          initialHtml == null &&
          (url.startsWith('http://') || url.startsWith('https://'))) {
        final refetched = await _refetchAfterBrowser(url);
        if (refetched != null && refetched.isNotEmpty) {
          html = refetched;
        }
      }
      final headers = _corsHeaders();
      if (cookieStr.isNotEmpty) {
        headers['X-Set-Cookie'] = cookieStr;
      }
      // 页面最终地址（含 #config= 等运行期 hash）通过响应头回传，
      // 桥侧据此让 StrResponse.url() 返回真实地址，书源可从 URL 取结果。
      if (finalUrl.isEmpty && refetch) {
        finalUrl = url;
      }
      if (finalUrl.isNotEmpty) {
        headers['X-Final-Url'] = Uri.encodeComponent(finalUrl);
      }
      return iw.WebResourceResponse(
        statusCode: 200,
        reasonPhrase: 'OK',
        contentType: 'text/plain; charset=utf-8',
        contentEncoding: 'utf-8',
        data: Uint8List.fromList(utf8.encode(html)),
        headers: headers,
      );
    } catch (e) {
      return _textResponse('', 502);
    }
  }

  /// 浏览器交互完成后，用已通过验证的 Cookie 重新请求原地址取正文。
  /// 记录请求头 / 响应头 / 最终地址 / 重定向链到网络日志；失败返回 null，
  /// 由调用方保留浏览器 DOM 兜底。
  Future<String?> _refetchAfterBrowser(String url) async {
    final reqHeaders = <String, String>{};
    try {
      final h = await _sourceHeaders();
      reqHeaders.addAll(h);
    } catch (_) {}
    final ck = CookieManager().cookieHeader(url);
    if (ck != null && ck.isNotEmpty && !reqHeaders.containsKey('Cookie')) {
      reqHeaders['Cookie'] = ck;
    }
    final sw = Stopwatch()..start();
    try {
      final resp = await _dio.get<List<int>>(
        url,
        options: Options(
          method: 'GET',
          headers: reqHeaders,
          responseType: ResponseType.bytes,
        ),
      );
      final status = resp.statusCode ?? 200;
      final respHeaders = <String, String>{};
      resp.headers.map.forEach((k, vals) {
        respHeaders[k] = vals.join('; ');
      });
      final redirects = <String>[url];
      for (final r in resp.redirects) {
        redirects.add(r.location.toString());
      }
      final realUrl = resp.realUri.toString();
      if (realUrl.isNotEmpty && redirects.length == 1 && realUrl != url) {
        redirects.add(realUrl);
      }
      final bytes = resp.data ?? const <int>[];
      SourceNetworkLog.instance.record(
        url: url,
        method: 'GET',
        origin: 'engine',
        statusCode: status,
        durationMs: sw.elapsedMilliseconds,
        body: bytes,
        error: status >= 400 ? 'HTTP $status' : null,
        requestHeaders: reqHeaders,
        responseHeaders: respHeaders,
        finalUrl: realUrl.isEmpty ? url : realUrl,
        redirects: redirects,
      );
      final setCookies = resp.headers.map['set-cookie'] ?? const <String>[];
      if (setCookies.isNotEmpty) {
        CookieManager().saveFromResponse(url, setCookies);
      }
      if (status >= 400) return null;
      return utf8.decode(bytes, allowMalformed: true);
    } catch (e) {
      SourceNetworkLog.instance.record(
        url: url,
        method: 'GET',
        origin: 'engine',
        statusCode: 502,
        durationMs: sw.elapsedMilliseconds,
        error: '重取失败: $e',
        requestHeaders: reqHeaders,
      );
      return null;
    }
  }

  /// 取书源配置的请求头（含 loginHeader 与 header 字段），用于原生重取。
  Future<Map<String, String>> _sourceHeaders() async {
    final out = <String, String>{};
    try {
      final raw = source.header;
      if (raw != null && raw.trim().isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          decoded.forEach((k, v) {
            out[k.toString()] = v?.toString() ?? '';
          });
        }
      }
    } catch (_) {}
    return out;
  }

  /// legado://searchbook 协议：java.searchBook(key, scope)。
  /// scope 形如「分组::书源Url」或书源 Url，命中则限定该书源搜索。
  Future<iw.WebResourceResponse> _handleSearchBook(iw.WebUri uri) async {
    final key = uri.queryParameters['key'] ?? '';
    final scope = uri.queryParameters['scope'] ?? '';
    if (key.trim().isNotEmpty) {
      final nav = appNavigatorKey.currentState;
      if (nav != null) {
        nav.push(MaterialPageRoute(
            builder: (_) => SearchScreen(
                  initialKeyword: key,
                  searchScope: scope.isEmpty ? null : scope,
                )));
      }
    }
    return _textResponse('true', 200);
  }

  /// legado://openlogin 协议：java.open('login', ...)。
  /// origin 非空时按书源地址解析目标源，否则打开当前书源登录页。
  Future<iw.WebResourceResponse> _handleOpenLogin(iw.WebUri uri) async {
    final origin = uri.queryParameters['origin'] ?? '';
    final nav = appNavigatorKey.currentState;
    if (nav != null) {
      try {
        BookSource? target;
        if (origin.trim().isNotEmpty) {
          target = await _db.getSource(origin);
        }
        target ??= source is BookSource ? source as BookSource : null;
        if (target != null) {
          nav.push(MaterialPageRoute(
              builder: (_) => SourceLoginScreen(source: target!)));
        }
      } catch (_) {}
    }
    return _textResponse('true', 200);
  }

  /// legado://verificationcode 协议：java.getVerificationCode(imageUrl)。
  /// 阻塞等待人工输入，完成后把识别结果作为响应体同步回传书源脚本。
  Future<iw.WebResourceResponse> _handleVerificationCode(iw.WebUri uri) async {
    final imageUrl = uri.queryParameters['url'] ?? '';
    var code = '';
    final nav = appNavigatorKey.currentState;
    if (nav != null && imageUrl.isNotEmpty) {
      try {
        final headers = await _verificationHeaders(imageUrl);
        code = await nav.push<String>(MaterialPageRoute(
                builder: (_) => VerificationCodeScreen(
                    imageUrl: imageUrl,
                    sourceName: source.jsName,
                    headers: headers))) ??
            '';
      } catch (_) {
        code = '';
      }
    }
    return _textResponse(code, 200);
  }

  /// legado://refreshexplore：书源调用 refreshExplore() 后失效发现分类缓存，
  /// 并通知发现页重新求值动态分类，使控件里改过的变量立即生效。
  Future<iw.WebResourceResponse> _handleRefreshExplore() async {
    final src = source;
    if (src is BookSource) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('exploreKinds_${src.bookSourceUrl}');
    }
    notifyExploreRefresh();
    return _textResponse('true', 200);
  }

  iw.WebResourceResponse _textResponse(String msg, int code) => iw.WebResourceResponse(
        statusCode: code,
        reasonPhrase: 'Error',
        contentType: 'text/plain; charset=utf-8',
        contentEncoding: 'utf-8',
        data: Uint8List.fromList(utf8.encode(msg)),
      );

  // 每次返回「新的可变 map」：调用方会在其上追加 Content-Type /
  // X-Set-Cookie / X-Legado-Error 等响应头。此处若用 const，赋值会抛
  // Unsupported operation: Cannot modify unmodifiable map，导致 java.ajax
  // 请求被伪装成 502「请求失败」，书源的 checkNet() 等按钮随之失效。
  Map<String, String> _corsHeaders() => <String, String>{
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Credentials': 'true',
        'Access-Control-Allow-Headers': '*',
        'Access-Control-Expose-Headers': '*',
        'Access-Control-Allow-Methods':
            'GET,POST,PUT,DELETE,HEAD,OPTIONS,PATCH'
      };

  String _reason(int code) {
    if (code < 300) return 'OK';
    if (code < 400) return 'Found';
    if (code < 500) return 'Bad Request';
    return 'Server Error';
  }

  @override
  Future<JsEvalResult> eval(JsEvalRequest req) async {
    source = req.source;
    await _ensure();
    await loadSource(req.source);
    final c = _controller!;

    final prefs = await SharedPreferences.getInstance();
    _deviceId ??= prefs.getString('legado_device_id');
    if (_deviceId == null || _deviceId!.isEmpty) {
      _deviceId = _genDeviceId();
      await prefs.setString('legado_device_id', _deviceId!);
    }
    final srcUrl = req.source.jsUrl;
    final loginInfo = prefs.getString('loginInfo_$srcUrl') ?? '';
    final loginHeader = prefs.getString('loginHeader_$srcUrl') ?? '';
    final kvJson = prefs.getString('jsKv_$srcUrl') ?? '{}';
    final cookies = await _collectCookies(req);
    // 发现页 infoMap
    final infoMap = req.infoMap ?? await _loadInfoMap(srcUrl);

    var script = req.script;
    if (req.isUrlRule) {
      script = _urlPlaceholders(script, req.key ?? '', req.page ?? 1);
    }
    final args = <String, dynamic>{
      'resultArg': req.result,
      'keyArg': req.key,
      'pageArg': req.page,
      'baseUrlArg': req.baseUrl ?? '',
      'bookArg': req.book ?? const <String, dynamic>{},
      'chapterArg': req.chapter ?? const <String, dynamic>{},
      'rssArticleArg': req.rssArticle ?? const <String, dynamic>{},
      'variableArg': req.source.variable ?? '',
      'variableCommentArg': req.source.variableComment ?? '',
      'lastUpdateTimeArg': req.source.lastUpdateTime ?? 0,
      'loginInfoArg': loginInfo,
      'loginHeaderArg': loginHeader,
      'cookiesArg': cookies,
      'kvArg': _tryJson(kvJson) ?? <String, dynamic>{},
      'infoMapArg': infoMap,
      'deviceIdArg': _deviceId!,
      'scriptArg': script,
      'sourceGroupArg': req.source.jsGroup,
      'sourceCommentArg': req.source.jsComment,
      'sourceTypeArg': req.source.jsType,
      'sourceConcurrentRateArg': req.source.jsConcurrentRate,
      'sourceEnabledExploreArg': req.source.jsEnabledExplore,
      'sourceHeaderArg': req.source.header ?? '',
      'sourceLoginUrlArg': req.source.loginUrl ?? '',
      'sourceLoginUiArg': req.source is BookSource
          ? ((req.source as BookSource).loginUi ?? '')
          : '',
      'sourceJsLibArg': req.source.jsLib ?? '',
      'sourceBookUrlPatternArg': req.source.jsBookUrlPattern,
    };

    final functionBody = '''
      __resetTransient();
      globalThis.result = resultArg;
      globalThis.\$ = resultArg;
      globalThis.key = keyArg;
      globalThis.page = pageArg;
      globalThis.baseUrl = baseUrlArg;
      globalThis.sourceUrl = baseUrlArg || ${_js(req.source.jsUrl)};
      globalThis.sourceName = ${_js(req.source.jsName)};
      // 更新 __state.meta，不覆盖 globalThis.source（保留 bridge 中的完整方法）
      __state.meta = {
        url: ${_js(req.source.jsUrl)},
        name: ${_js(req.source.jsName)},
        httpUrl: ${_js(req.source.jsHttpUrl)},
        group: sourceGroupArg,
        comment: sourceCommentArg,
        type: sourceTypeArg,
        concurrentRate: sourceConcurrentRateArg,
        enabledExplore: sourceEnabledExploreArg,
        header: sourceHeaderArg,
        loginUrl: sourceLoginUrlArg,
        loginUi: sourceLoginUiArg,
        jsLib: sourceJsLibArg,
        bookUrlPattern: sourceBookUrlPatternArg
      };
      __state.variableComment = variableCommentArg || '';
      __state.lastUpdateTime = lastUpdateTimeArg || 0;
      globalThis.book = __wrapBook(bookArg);
      globalThis.chapter = __wrapChapter(chapterArg);
      globalThis.rssArticle = rssArticleArg;
      // 发现页控件状态
      globalThis.infoMap = new Proxy(infoMapArg || {}, {
        get: function (t, k) { return t[k]; },
        set: function (t, k, v) { t[k] = (v === null || v === undefined) ? "" : String(v); __state.infoMap[k] = t[k]; return true; }
      });
      __state.variable = variableArg || '';
      __state.loginInfo = loginInfoArg || '';
      __state.loginHeader = loginHeaderArg || '';
      __state.cookies = cookiesArg || {};
      __state.kv = kvArg || {};
      __state.deviceId = deviceIdArg;
      var __ret, __err = null;
      // 优先用 eval：它会返回脚本「最后一个表达式的值」，正是
      // 书源末尾裸表达式（如 `data;`）产出结果的标准语义。
      // 只有当脚本含「顶层 return」时，eval 会在解析期抛 SyntaxError
      // （此时尚未执行任何副作用），才回退为「脚本当函数体」执行。
      // 注意：不能用正则 return 预判——嵌套函数里的 return 会被误判，
      // 导致末尾裸表达式脚本的返回值丢失（正文加载不出的根因）。
      try {
        __ret = await (async function() {
          return eval(scriptArg);
        }).call(globalThis);
      } catch (e) {
        __err = e;
        var __msg = String(e && e.message || e);
        if (/illegal return|return statement outside|return not in function|unexpected token.*return/i.test(__msg)) {
          __err = null;
          try {
            __ret = await (async function() {
              $script
            }).call(globalThis);
          } catch (e2) {
            __err = e2;
          }
        }
      }
      if (__ret === undefined) { try { __ret = globalThis.result; } catch (e1) { __ret = null; } }
      return __envelope(__ret, __err);
    ''';

    iw.CallAsyncJavaScriptResult? res;
    try {
      // 90 秒上限：防止书源 JS 死循环/长挂把整条抓取链路拖死
      res = await c.callAsyncJavaScript(
              functionBody: functionBody, arguments: args)
          .timeout(const Duration(seconds: 90));
    } catch (e) {
      return JsEvalResult(error: 'JS 执行异常: $e', variable: req.source.variable);
    }
    if (res?.error != null && res?.value == null) {
      return JsEvalResult(
          error: res!.error.toString(), variable: req.source.variable);
    }
    Map<String, dynamic> env;
    try {
      env =
          jsonDecode(res?.value?.toString() ?? '{}') as Map<String, dynamic>;
    } catch (e) {
      return JsEvalResult(
          value: res?.value?.toString(), variable: req.source.variable);
    }

    final newVar = env['variable']?.toString();
    if (newVar != null && newVar.isNotEmpty && newVar != req.source.variable) {
      req.source.variable = newVar;
      try {
        // 书源 / 订阅源分别落各自的表
        if (req.source is RssSource) {
          await _db.updateRssSourceVariable(req.source.jsUrl, newVar);
        } else {
          await _db.updateSourceVariable(req.source.jsUrl, newVar);
        }
      } catch (_) {}
    }
    final newLogin = env['loginInfo']?.toString() ?? '';
    if (newLogin.isNotEmpty && newLogin != loginInfo) {
      await prefs.setString('loginInfo_$srcUrl', newLogin);
    }
    final newLoginHeader = env['loginHeader']?.toString() ?? '';
    if (newLoginHeader.isNotEmpty) {
      await prefs.setString('loginHeader_$srcUrl', newLoginHeader);
    } else if (newLoginHeader.isEmpty && env.containsKey('loginHeader')) {
      await prefs.remove('loginHeader_$srcUrl');
    }
    final kv = env['kv'];
    if (kv is Map && kv.isNotEmpty) {
      await prefs.setString('jsKv_$srcUrl', jsonEncode(kv));
    }
    await _persistBridgeCookies(env['cookies'], srcUrl);
    // 发现页控件状态回写。
    // 桥只上报本次被写过的键，需与入参 infoMap 合并后再落盘，避免覆盖丢失。
    final envInfoMap = env['infoMap'];
    if (envInfoMap is Map && envInfoMap.isNotEmpty) {
      final merged = Map<String, String>.from(infoMap);
      envInfoMap.forEach((k, v) {
        merged[k.toString()] = v?.toString() ?? '';
      });
      await _saveInfoMap(srcUrl, merged);
    }

    return JsEvalResult(
      value: env['ret'],
      variable: newVar ?? req.source.variable,
      loginInfo: newLogin.isEmpty ? null : newLogin,
      cookies: env['cookies'] is Map
          ? Map<String, dynamic>.from(env['cookies'] as Map)
          : const {},
      kv: env['kv'] is Map
          ? Map<String, dynamic>.from(env['kv'] as Map)
          : const {},
      logs: (env['logs'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      toasts: (env['toasts'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      error: env['error']?.toString(),
    );
  }

  /// 按书源维度持久化的 cookie jar：书源 `cookie.setCookie(url, ...)` 里的
  /// url 是书源自己给出的任意字符串（可能是完整域名、自定义服务器甚至
  /// 非 URL 的逻辑名），无法只靠请求的 host 反推。因此把整个 jar 以书源
  /// key 落盘，下次求值时整体恢复，保证 login() 写入的 qttoken 等登录态
  /// 在跨按钮点击后仍然可读（否则「用户后台」会误判为未登录）。
  static const String _cookieJarPrefix = 'jsCookieJar_';

  Future<Map<String, dynamic>> _collectCookies(JsEvalRequest req) async {
    final out = <String, dynamic>{};
    final prefs = await SharedPreferences.getInstance();
    final srcUrl = req.source.jsUrl;
    // 1) 先恢复该书源上次持久化的完整 jar。
    final savedJar = prefs.getString('$_cookieJarPrefix$srcUrl');
    if (savedJar != null && savedJar.isNotEmpty) {
      final parsed = _tryJson(savedJar);
      if (parsed is Map) {
        parsed.forEach((k, v) {
          if (v != null && v.toString().isNotEmpty) {
            out[k.toString()] = v.toString();
          }
        });
      }
    }
    // 2) 再叠加按请求 host 从内存 CookieJar / DB 收集的实时值。
    //    同名 key 以实时值优先，避免过期快照覆盖刚登录写入的 Cookie。
    final hosts = <String>{};
    for (final u in [req.baseUrl, req.source.jsUrl].whereType<String>()) {
      final h = Uri.tryParse(u)?.host;
      if (h != null && h.isNotEmpty) hosts.add(h);
    }
    for (final h in hosts) {
      final ck = CookieManager().cookieHeader('https://$h/');
      if (ck != null && ck.isNotEmpty) out[h] = ck;
      if (_persistCookie) {
        final saved = await _db.getCookie(h);
        if (saved != null && saved.isNotEmpty && !out.containsKey(h)) {
          out[h] = saved;
        }
      }
    }
    return out;
  }

  Future<void> _persistBridgeCookies(dynamic cookies, String srcUrl) async {
    if (cookies is! Map) return;
    // 整体落盘：保留书源自定义 host 的 Cookie，且支持 removeCookie 的删除语义
    // （map 中不再出现的 key 会随整体覆盖被清掉）。
    final prefs = await SharedPreferences.getInstance();
    try {
      final jar = <String, String>{};
      cookies.forEach((k, v) {
        if (v != null && v.toString().isNotEmpty) {
          jar[k.toString()] = v.toString();
        }
      });
      await prefs.setString('$_cookieJarPrefix$srcUrl', jsonEncode(jar));
    } catch (_) {}
    for (final entry in cookies.entries) {
      final h = entry.key.toString();
      final v = entry.value.toString();
      if (v.isEmpty) continue;
      final url = h.startsWith('http') ? h : 'https://$h/';
      CookieManager().saveFromResponse(url, [v]);
      if (_persistCookie) {
        try {
          await _db.saveCookie(h, v);
        } catch (_) {}
      }
      try {
        for (final pair in v.split(';')) {
          final idx = pair.indexOf('=');
          if (idx > 0) {
            await iw.CookieManager.instance().setCookie(
                  url: iw.WebUri(url),
                  name: pair.substring(0, idx).trim(),
                  value: pair.substring(idx + 1).trim(),
                );
          }
        }
      } catch (_) {}
    }
  }

  /// 读取发现页 infoMap。
  /// key 与 source_engine 的 _infoMapKey 保持一致。
  Future<Map<String, String>> _loadInfoMap(String srcUrl) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('exploreInfoMap_$srcUrl');
      if (raw == null || raw.isEmpty) return {};
      final json = _tryJson(raw);
      if (json is Map) {
        return json
            .map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
      }
    } catch (_) {}
    return {};
  }

  /// 持久化发现页 infoMap。
  Future<void> _saveInfoMap(String srcUrl, Map<String, String> map) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (map.isEmpty) {
        await prefs.remove('exploreInfoMap_$srcUrl');
      } else {
        await prefs.setString('exploreInfoMap_$srcUrl', jsonEncode(map));
      }
    } catch (_) {}
  }

  @override
  Future<void> dispose() async {
    try {
      await _headless?.dispose();
    } catch (_) {}
    _headless = null;
    _controller = null;
  }

  static String _js(String? s) => jsonEncode(s ?? '');

  dynamic _tryJson(String s) {
    try {
      return jsonDecode(s);
    } catch (_) {
      return null;
    }
  }

  String _urlPlaceholders(String script, String key, int page) {
    var r = script.replaceAll('{{key}}', Uri.encodeComponent(key));
    r = r.replaceAll('{{searchKey}}', Uri.encodeComponent(key));
    r = r.replaceAll('{{page}}', page.toString());
    r = r.replaceAllMapped(RegExp(r'\{\{\(page-1\)\*(\d+)\}\}'),
        (m) => ((page - 1) * int.parse(m.group(1)!)).toString());
    return r;
  }

  String _genDeviceId() {
    const chars = '0123456789abcdef';
    final sb = StringBuffer();
    var seed = DateTime.now().microsecondsSinceEpoch;
    for (var i = 0; i < 16; i++) {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      sb.write(chars[seed % 16]);
    }
    return sb.toString();
  }
}
