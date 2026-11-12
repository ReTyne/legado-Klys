import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart' as iw;
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/rss_article.dart';
import 'package:legado_md3/data/model/rss_read_record.dart';
import 'package:legado_md3/data/model/rss_source.dart';
import 'package:legado_md3/help/http/rss_service.dart';
import 'package:legado_md3/help/readaloud/tts_service.dart';
import 'package:legado_md3/ui/book/read/tts_player_screen.dart';
import 'package:legado_md3/ui/widgets/app_widgets.dart';

part 'parts/rss_read_screen_state.dart';
part 'parts/html_body.dart';
part 'parts/text_body.dart';


/// RSS文章阅读页面 - RssReadScreen
/// * ruleContent 为空：以文本展示描述。
/// * ruleContent 产出 HTML：用 WebView 渲染（适配 articleStyle=2 等特殊源）。
class RssReadScreen extends StatefulWidget {
  const RssReadScreen({
    super.key,
    required this.article,
    this.source,
  });
  final RssArticle article;
  final RssSource? source;

  @override
  State<RssReadScreen> createState() => _RssReadScreenState();
}
