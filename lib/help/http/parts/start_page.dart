/// 由 rss_service.dart 按「一类一文件」拆出的 _StartPage。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../rss_service.dart';


/// 取文章列表的起始页：待解析 HTML 及其实际地址（用于相对链接解析）
class _StartPage {
  _StartPage(this.html, this.url);
  final String html;
  final String url;
}
