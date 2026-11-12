import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';

import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/help/device/native_bridge.dart';
import 'package:legado_md3/help/source/source_engine.dart';
import 'package:legado_md3/help/storage/import_book_service.dart';

import 'package:legado_md3/ui/theme/app_design.dart';
part 'parts/browser_tab.dart';
part 'parts/sniff_result.dart';
part 'parts/browser_screen_state.dart';


/// 内置浏览器 -  WebViewActivity：
/// 地址栏 + 前进后退刷新 + 多标签 + UA 切换 + 无图模式 +
/// 书源/书籍嗅探 + 保存网页为 txt + 快捷导航。
class BrowserScreen extends StatefulWidget {
  final String url;
  final String? title;

  /// 网页交互登录模式（java.startBrowserAwait 等阻塞式调用）：
  /// 退出时回传页面结果给调用方（书源据此取设置结果/验证后的正文），
  /// 同时由调用方回收 Cookie。
  final bool captureHtmlOnExit;

  /// 书源传入的自定义页面内容：非空时直接渲染它，不加载 url。
  final String? initialHtml;
  const BrowserScreen({
    super.key,
    required this.url,
    this.title,
    this.captureHtmlOnExit = false,
    this.initialHtml,
  });

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

/// 交互页面退出时回传给书源 JS 的结果。
/// 书源设置页会把用户选择写进页面 DOM 的 `<script id="...result">`、
/// `location.hash` 的 `#config=` 或 Cookie，因此必须回传「渲染后的 DOM」
/// 而不是原始 HTML，否则书源读到的一直是空结果。
class BrowserCaptureResult {
  /// 渲染后的整页 DOM（document.documentElement.outerHTML）。
  final String html;

  /// 页面最终地址，含运行期间变化的 hash（如 `#config=...`）。
  final String finalUrl;

  /// 页面写入的 Cookie 串。
  final String cookies;

  const BrowserCaptureResult({
    required this.html,
    required this.finalUrl,
    this.cookies = '',
  });
}
