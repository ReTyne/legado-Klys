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


/// 内置浏览器 - 对齐原版 WebViewActivity：
/// 地址栏 + 前进后退刷新 + 多标签 + UA 切换 + 无图模式 +
/// 书源/书籍嗅探 + 保存网页为 txt + 快捷导航。
class BrowserScreen extends StatefulWidget {
  final String url;
  final String? title;

  /// 网页交互登录模式（java.startBrowserAwait 等阻塞式调用）：
  /// 退出时回传当前页面 HTML 给调用方（书源据此取验证后的正文/结构），
  /// 同时由调用方回收 Cookie。
  final bool captureHtmlOnExit;
  const BrowserScreen(
      {super.key, required this.url, this.title, this.captureHtmlOnExit = false});

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}
