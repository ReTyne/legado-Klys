import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart' as iw;
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:archive/archive.dart';

import 'package:legado_md3/common/app_navigator.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/data/model/rss_source.dart';
import 'package:legado_md3/help/http/cookie_manager.dart';
import 'package:legado_md3/help/source/archive_native.dart';
import 'package:legado_md3/help/source/js_text_utils.dart';
import 'package:legado_md3/help/source/ttf_parser.dart';
import 'package:legado_md3/ui/book/search/search_screen.dart';
import 'package:legado_md3/ui/book/source/source_login_screen.dart';
import 'package:legado_md3/ui/book/source/verification_code_screen.dart';
import 'package:legado_md3/ui/browser/browser_screen.dart';
import 'package:legado_md3/help/source/source_network_log.dart';
import 'legado_bridge_js.dart';
import 'aes_js_lib.dart';
import 'headless_webview.dart';
import '../js_mini_eval.dart';

import 'js_source.dart';
export 'js_source.dart';

part 'parts/js_eval_result.dart';
part 'parts/legado_js.dart';
part 'parts/js_runtime_manager.dart';
part 'parts/mini_legado_js.dart';
part 'parts/web_view_legado_js.dart';


/// 一次 JS 求值的入参。
class JsEvalRequest {
  JsEvalRequest({
    required this.source,
    required this.script,
    this.result,
    this.key,
    this.page,
    this.baseUrl,
    this.book,
    this.chapter,
    this.rssArticle,
    this.infoMap,
    this.isUrlRule = false,
  });

  final JsSource source;
  final String script; // 纯 JS（不含 <js></js>）
  final dynamic result; // String（响应正文）或 Map/List（JSON 节点）
  final String? key;
  final int? page;
  final String? baseUrl;
  final Map<String, dynamic>? book;
  final Map<String, dynamic>? chapter;
  final Map<String, dynamic>? rssArticle; // RSS 当前文章（rssArticle）
  final Map<String, String>? infoMap; // 发现页控件状态（对齐 legado InfoMap）
  final bool isUrlRule;
}
