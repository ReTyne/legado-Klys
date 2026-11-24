import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/help/source/js/legado_js_runtime.dart';

/// 书源事件回调分发。
///
/// 书源声明 `eventListener` 且 `callBackJs` 非空时，交互/生命周期事件发生后
/// 由该源自己的 JS 运行时执行脚本；脚本通过全局 `event`、`result`、`book`、
/// `chapter` 拿到上下文。脚本返回真值表示「消费事件」、拦截默认操作，
/// 返回假值则继续默认操作（与阅读规则帮助文档一致）。因此分发方法返回
/// 「是否放行」：脚本真值取反。无回调/超时/异常一律返回 true 放行主流程。
class SourceEventCallback {
  SourceEventCallback._();

  static const String clickAuthor = 'clickAuthor';
  static const String clickBookName = 'clickBookName';
  static const String clickBookLabel = 'clickBookLabel';
  static const String clickButton = 'clickCustomButton';
  static const String longClickAuthor = 'longClickAuthor';
  static const String longClickBookName = 'longClickBookName';
  static const String longClickCustomButton = 'longClickCustomButton';
  static const String longClickBookLabel = 'longClickBookLabel';
  static const String share = 'clickShareBook';
  static const String clearCache = 'clickClearCache';
  static const String copyBookUrl = 'clickCopyBookUrl';
  static const String copyTocUrl = 'clickCopyTocUrl';
  static const String copyPlayUrl = 'clickCopyPlayUrl';
  static const String addBookshelf = 'addBookShelf';
  static const String removeBookshelf = 'delBookShelf';
  static const String saveRead = 'saveRead';
  static const String startRead = 'startRead';
  static const String endRead = 'endRead';
  static const String startRefreshBookshelf = 'startShelfRefresh';
  static const String endRefreshBookshelf = 'endShelfRefresh';

  static const List<String> allEvents = <String>[
    clickAuthor,
    clickBookName,
    clickBookLabel,
    clickButton,
    longClickAuthor,
    longClickBookName,
    longClickCustomButton,
    longClickBookLabel,
    share,
    clearCache,
    copyBookUrl,
    copyTocUrl,
    copyPlayUrl,
    addBookshelf,
    removeBookshelf,
    saveRead,
    startRead,
    endRead,
    startRefreshBookshelf,
    endRefreshBookshelf,
  ];

  /// 书本级事件回调最长执行时间。
  static Duration bookTimeout = const Duration(seconds: 60);

  /// 按钮 / 书源级事件回调最长执行时间。
  static Duration sourceTimeout = const Duration(seconds: 30);

  /// 按钮交互事件。
  static Future<bool> callBackBtn(
    BookSource source,
    String event, {
    Map<String, dynamic>? extra,
  }) =>
      _dispatch(source, event, sourceTimeout, extra: extra);

  /// 书本级事件：加入/移出书架、阅读开始/结束、保存阅读进度等。
  static Future<bool> callBackBook(
    BookSource source,
    String event, {
    Map<String, dynamic>? book,
    Map<String, dynamic>? chapter,
    Map<String, dynamic>? extra,
  }) =>
      _dispatch(source, event, bookTimeout,
          book: book, chapter: chapter, extra: extra);

  /// 书源级事件：刷新书架等。
  static Future<bool> callBackSource(
    BookSource source,
    String event, {
    Map<String, dynamic>? extra,
  }) =>
      _dispatch(source, event, sourceTimeout, extra: extra);

  static Future<bool> _dispatch(
    BookSource source,
    String event,
    Duration timeout, {
    Map<String, dynamic>? book,
    Map<String, dynamic>? chapter,
    Map<String, dynamic>? extra,
  }) async {
    // 没有声明回调的书源直接放行，不创建 JS 运行时、不做任何求值。
    if (!source.eventListener || source.callBackJs.trim().isEmpty) return true;

    final extraBook = extra?['book'];
    final extraChapter = extra?['chapter'];
    final ctxBook = book ?? (extraBook is Map<String, dynamic> ? extraBook : null);
    final ctxChapter =
        chapter ?? (extraChapter is Map<String, dynamic> ? extraChapter : null);
    // callBackJs 允许以 @js:/<js> 包裹，拼接前剥离前缀，
    // 否则顶层 @ 触发 SyntaxError，事件回调脚本整体失效。
    final callbackBody = stripJsRulePrefix(source.callBackJs);
    final script = 'var event = ${jsonEncode(event)};\n$callbackBody';

    try {
      final evaluation = () async {
        final rt = await JsRuntimeManager.instance.forSource(source);
        return rt.eval(JsEvalRequest(
          source: source,
          script: script,
          event: event,
          result: extra?['result'],
          book: ctxBook,
          chapter: ctxChapter,
          baseUrl: extra?['baseUrl']?.toString() ?? source.bookSourceUrl,
        ));
      }();
      final out = await evaluation.timeout(timeout, onTimeout: () {
        return JsEvalResult(error: '事件回调超时: $event');
      });

      if (out.error != null && out.error!.isNotEmpty) {
        debugPrint('[事件回调] $event 执行异常: ${out.error}');
        return true;
      }
      for (final l in out.logs) {
        if (l.trim().isNotEmpty) debugPrint('[事件回调] $event: $l');
      }
      // E 版语义：脚本返回 true 表示「消费事件」，默认操作不再执行；
      // 返回假值则继续默认操作。本方法返回「是否放行默认操作」，故取反。
      return !_jsTruthy(out.value);
    } catch (e) {
      debugPrint('[事件回调] $event 异常: $e');
      return true;
    }
  }

  /// 按 JS 语义判定真值：null/false/0/空串为假，其余（含空对象/空数组）为真。
  static bool _jsTruthy(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) return value.isNotEmpty;
    return true;
  }
}
