import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:enough_convert/enough_convert.dart';
import 'package:legado_md3/data/model/rss_source.dart';
import 'package:legado_md3/data/model/rss_article.dart';
import 'package:legado_md3/help/http/cookie_manager.dart';
import 'package:legado_md3/help/source/rule_pipeline.dart';
import 'package:legado_md3/help/source/js/legado_js_runtime.dart';

part 'parts/start_page.dart';
part 'parts/rss_service.dart';


/// RSS 分类（sortUrl 解析结果）
class RssCategory {
  final String name;
  final String rawUrl;
  RssCategory(this.name, this.rawUrl);
}
