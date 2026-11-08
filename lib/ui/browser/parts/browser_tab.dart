/// 由 browser_screen.dart 按「一类一文件」拆出的 _BrowserTab。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../browser_screen.dart';


/// 一个标签页
class _BrowserTab {
  String url;
  String title;
  _BrowserTab(this.url, this.title);
}
