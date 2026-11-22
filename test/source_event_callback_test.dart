import 'package:flutter_test/flutter_test.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/help/source/js/legado_js_runtime.dart';
import 'package:legado_md3/help/source/source_event_callback.dart';

class _FakeRuntime implements LegadoJs {
  _FakeRuntime(this.result);

  final JsEvalResult result;
  int calls = 0;
  JsEvalRequest? last;

  @override
  Future<void> loadSource(JsSource source) async {}

  @override
  Future<JsEvalResult> eval(JsEvalRequest req) async {
    calls++;
    last = req;
    return result;
  }

  @override
  Future<void> dispose() async {}
}

class _ThrowingRuntime implements LegadoJs {
  int calls = 0;

  @override
  Future<void> loadSource(JsSource source) async {}

  @override
  Future<JsEvalResult> eval(JsEvalRequest req) async {
    calls++;
    throw StateError('runtime exploded');
  }

  @override
  Future<void> dispose() async {}
}

class _SlowRuntime implements LegadoJs {
  @override
  Future<void> loadSource(JsSource source) async {}

  @override
  Future<JsEvalResult> eval(JsEvalRequest req) =>
      Future.delayed(const Duration(seconds: 2), () => JsEvalResult(value: true));

  @override
  Future<void> dispose() async {}
}

BookSource _source(String tag,
        {bool eventListener = true, String callBackJs = 'true'}) =>
    BookSource(
      bookSourceUrl: 'https://event.test/$tag',
      bookSourceName: '事件测试源',
      eventListener: eventListener,
      callBackJs: callBackJs,
    );

void main() {
  final manager = JsRuntimeManager.instance;
  final originalBookTimeout = SourceEventCallback.bookTimeout;
  final originalSourceTimeout = SourceEventCallback.sourceTimeout;

  tearDown(() async {
    manager.factoryOverride = null;
    await manager.disposeAll();
    SourceEventCallback.bookTimeout = originalBookTimeout;
    SourceEventCallback.sourceTimeout = originalSourceTimeout;
  });

  test('事件常量数量与取值', () {
    expect(SourceEventCallback.allEvents.length, 20);
    expect(SourceEventCallback.allEvents.toSet().length, 20);
    expect(SourceEventCallback.clickAuthor, 'clickAuthor');
    expect(SourceEventCallback.clickBookName, 'clickBookName');
    expect(SourceEventCallback.clickBookLabel, 'clickBookLabel');
    expect(SourceEventCallback.clickButton, 'clickCustomButton');
    expect(SourceEventCallback.longClickAuthor, 'longClickAuthor');
    expect(SourceEventCallback.longClickBookName, 'longClickBookName');
    expect(SourceEventCallback.longClickCustomButton, 'longClickCustomButton');
    expect(SourceEventCallback.longClickBookLabel, 'longClickBookLabel');
    expect(SourceEventCallback.share, 'clickShareBook');
    expect(SourceEventCallback.clearCache, 'clickClearCache');
    expect(SourceEventCallback.copyBookUrl, 'clickCopyBookUrl');
    expect(SourceEventCallback.copyTocUrl, 'clickCopyTocUrl');
    expect(SourceEventCallback.copyPlayUrl, 'clickCopyPlayUrl');
    expect(SourceEventCallback.addBookshelf, 'addBookShelf');
    expect(SourceEventCallback.removeBookshelf, 'delBookShelf');
    expect(SourceEventCallback.saveRead, 'saveRead');
    expect(SourceEventCallback.startRead, 'startRead');
    expect(SourceEventCallback.endRead, 'endRead');
    expect(SourceEventCallback.startRefreshBookshelf, 'startShelfRefresh');
    expect(SourceEventCallback.endRefreshBookshelf, 'endShelfRefresh');
  });

  test('未开启 eventListener 时直接放行且不创建运行时', () async {
    final fake = _FakeRuntime(JsEvalResult(value: false));
    manager.factoryOverride = (_) => fake;
    final source = _source('disabled',
        eventListener: false, callBackJs: 'false');

    expect(
        await SourceEventCallback.callBackBtn(
            source, SourceEventCallback.clickAuthor),
        isTrue);
    expect(fake.calls, 0);
  });

  test('callBackJs 为空时直接放行且不创建运行时', () async {
    final fake = _FakeRuntime(JsEvalResult(value: false));
    manager.factoryOverride = (_) => fake;
    final source = _source('empty', callBackJs: '   ');

    expect(
        await SourceEventCallback.callBackBook(
            source, SourceEventCallback.startRead),
        isTrue);
    expect(fake.calls, 0);
  });

  test('脚本返回假值时拦截，并注入 event/book/chapter 上下文', () async {
    final fake = _FakeRuntime(JsEvalResult(value: false));
    manager.factoryOverride = (_) => fake;
    final source = _source('falsy', callBackJs: 'false');
    final book = <String, dynamic>{'name': '书名'};
    final chapter = <String, dynamic>{'title': '第一章'};

    final allowed = await SourceEventCallback.callBackBook(
      source,
      SourceEventCallback.addBookshelf,
      book: book,
      chapter: chapter,
    );

    expect(allowed, isFalse);
    expect(fake.calls, 1);
    expect(fake.last!.event, SourceEventCallback.addBookshelf);
    expect(fake.last!.book, same(book));
    expect(fake.last!.chapter, same(chapter));
    expect(fake.last!.script, contains('var event = "addBookShelf"'));
  });

  test('脚本返回真值时放行', () async {
    final fake = _FakeRuntime(JsEvalResult(value: true));
    manager.factoryOverride = (_) => fake;
    final source = _source('truthy', callBackJs: 'true');

    expect(
        await SourceEventCallback.callBackBtn(
            source, SourceEventCallback.clickBookName),
        isTrue);
    expect(fake.calls, 1);
  });

  test('JS 语义的假值类型均拦截', () async {
    for (final value in <dynamic>[null, false, 0, '']) {
      final tag = 'falsy_${value.toString().replaceAll(RegExp(r'\W'), '')}';
      manager.factoryOverride = (_) => _FakeRuntime(JsEvalResult(value: value));
      final source = _source(tag, callBackJs: 'false');
      expect(await SourceEventCallback.callBackSource(source, 'any'), isFalse,
          reason: '$value 应视为假值');
    }
  });

  test('按钮与书源事件使用 30 秒超时，书本事件使用 60 秒超时', () async {
    expect(SourceEventCallback.bookTimeout, const Duration(seconds: 60));
    expect(SourceEventCallback.sourceTimeout, const Duration(seconds: 30));
  });

  test('运行时异常只记日志并放行', () async {
    final fake = _ThrowingRuntime();
    manager.factoryOverride = (_) => fake;
    final source = _source('throw', callBackJs: 'true');

    expect(
        await SourceEventCallback.callBackBook(
            source, SourceEventCallback.saveRead),
        isTrue);
    expect(fake.calls, 1);
  });

  test('脚本错误或超时只记日志并放行', () async {
    manager.factoryOverride = (_) => _FakeRuntime(JsEvalResult(error: 'boom'));
    expect(
        await SourceEventCallback.callBackBtn(
            _source('jserror'), SourceEventCallback.share),
        isTrue);

    SourceEventCallback.bookTimeout = const Duration(milliseconds: 30);
    manager.factoryOverride = (_) => _SlowRuntime();
    final stopwatch = Stopwatch()..start();
    final allowed = await SourceEventCallback.callBackBook(
        _source('timeout'), SourceEventCallback.endRead);
    stopwatch.stop();
    expect(allowed, isTrue);
    expect(stopwatch.elapsedMilliseconds, lessThan(1500));
  });

  test('callBackJs 字段序列化往返', () {
    const js = 'if (event == "addBookShelf") { return false; } true;';
    final source = _source('serialize', eventListener: true, callBackJs: js);

    final json = source.toJson();
    expect(json['callBackJs'], js);
    expect(BookSource.fromJson(json).callBackJs, js);

    final map = source.toMap();
    expect(map['callBackJs'], js);
    expect(BookSource.fromMap(map).callBackJs, js);
    expect(BookSource.fromDbMap(source.toDbMap()).callBackJs, js);
    expect(BookSource.fromJsonString(source.toJsonString()).callBackJs, js);
    expect(BookSource.fromMap(map).equal(source), isTrue);
  });
}
