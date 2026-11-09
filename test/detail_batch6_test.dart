// 批次 6 回归测试：Web 端点参数边界 / 基础层工具 / 原生服务边界契约。
// 定向运行：flutter test --no-pub test/detail_batch6_test.dart
import 'package:flutter_test/flutter_test.dart';

import 'package:legado_md3/help/device/web_service_contract.dart';
import 'package:legado_md3/help/exceptions/app_exceptions.dart';
import 'package:legado_md3/help/web/web_params.dart';
import 'package:legado_md3/utils/cookie_util.dart';
import 'package:legado_md3/utils/regex_timeout.dart';
import 'package:legado_md3/utils/url_edge.dart';

/// 测试用的书架条目（隔离 data/model/book.dart 的并行传递依赖）。
class _B {
  final String name;
  final int dur;
  final int latest;
  final int? order;
  _B(this.name, {this.dur = 0, this.latest = 0, this.order});
}

List<_B> _sorted(List<_B> books, int sortType) => sortBookshelf<_B>(
      books,
      sortType,
      latestChapterTime: (b) => b.latest,
      name: (b) => b.name,
      order: (b) => b.order,
      durChapterTime: (b) => b.dur,
    );

void main() {
  // ---- 19. Web 端点参数边界 ----
  group('端口 1024..65530（WebService.kt:185-191）', () {
    test('越界（<1024 / >65530）回退 1122', () {
      expect(validateWebPort(1023), webPortDefault);
      expect(validateWebPort(65531), webPortDefault);
      expect(validateWebPort(0), webPortDefault);
      expect(validateWebPort(-1), webPortDefault);
      expect(webPortMin, 1024);
      expect(webPortMax, 65530);
      expect(webPortDefault, 1122);
    });

    test('合法边界与默认值原样保留', () {
      expect(validateWebPort(1024), 1024);
      expect(validateWebPort(65530), 65530);
      expect(validateWebPort(1122), 1122);
      expect(validateWebPort(8080), 8080);
    });
  });

  group('width 默认 640（BookController.kt:105）', () {
    test('缺省 / 非法 / 非正 回退 640', () {
      expect(imageWidthDefault, 640);
      expect(parseImageWidth(null), 640);
      expect(parseImageWidth(''), 640);
      expect(parseImageWidth('abc'), 640);
      expect(parseImageWidth('0'), 640);
      expect(parseImageWidth('-5'), 640);
    });

    test('合法值透传', () {
      expect(parseImageWidth('800'), 800);
      expect(parseImageWidth(' 1024 '), 1024);
    });
  });

  group('bookshelfSort 四分支（BookController.kt:53-61）', () {
    test('1 = latestChapterTime 降序', () {
      final books = [
        _B('A', latest: 10),
        _B('B', latest: 30),
        _B('C', latest: 20),
      ];
      expect(_sorted(books,1).map((b) => b.name), ['B', 'C', 'A']);
    });

    test('2 = 书名中文/自然序（数字块按数值）', () {
      final books = [_B('书10'), _B('书2'), _B('书1')];
      expect(_sorted(books,2).map((b) => b.name),
          ['书1', '书2', '书10']);
    });

    test('3 = order 升序', () {
      final books = [
        _B('A', order: 3),
        _B('B', order: 1),
        _B('C', order: 2),
      ];
      expect(_sorted(books,3).map((b) => b.name), ['B', 'C', 'A']);
    });

    test('else = durChapterTime 降序（默认）', () {
      final books = [_B('A', dur: 5), _B('B', dur: 9), _B('C', dur: 7)];
      expect(_sorted(books,0).map((b) => b.name), ['B', 'C', 'A']);
      expect(_sorted(books,99).map((b) => b.name), ['B', 'C', 'A']);
    });

    test('本地 bs_sortType → 上游四分支映射', () {
      expect(mapLocalBookshelfSort(1), 2);
      expect(mapLocalBookshelfSort(4), 3);
      expect(mapLocalBookshelfSort(0), 0);
      expect(mapLocalBookshelfSort(3), 0);
    });
  });

  group('章节 30×1s 等待（BookController.kt:186-195）', () {
    test('常量对齐', () {
      expect(chapterWaitMaxAttempts, 30);
      expect(chapterWaitInterval, const Duration(seconds: 1));
    });

    test('第 3 次 probe 命中即返回，不再空等', () async {
      var calls = 0;
      final v = await pollForValue<int>(() async {
        calls++;
        return calls >= 3 ? 42 : null;
      }, maxAttempts: 5, interval: Duration.zero);
      expect(v, 42);
      expect(calls, 3);
    });

    test('始终为 null 时按上限尝试并返回 null', () async {
      var calls = 0;
      final v = await pollForValue<int>(() async {
        calls++;
        return null;
      }, maxAttempts: 30, interval: Duration.zero);
      expect(v, isNull);
      expect(calls, 30);
    });
  });

  group('封面 3s 超时 + 84×112（BookController.kt:69-94）', () {
    test('契约常量', () {
      expect(coverLoadTimeout, const Duration(seconds: 3));
      expect(coverWidth, 84);
      expect(coverHeight, 112);
    });
  });

  // ---- 20. 基础层 ----
  group('Cookie eTLD+1（NetworkUtils.kt:212-236）', () {
    test('多段公共后缀 / 普通域 / IP 特判', () {
      expect(getSubDomain('http://www.biquge.com.cn/x'), 'biquge.com.cn');
      expect(getSubDomain('https://www.content.example.com'), 'example.com');
      expect(getSubDomain('http://www.example.com/a'), 'example.com');
      expect(getSubDomain('http://a.b.github.io'), 'b.github.io');
      expect(getSubDomain('http://1.2.3.4:8080/x'), '1.2.3.4');
      expect(getDomain('http://www.example.com/x'), 'www.example.com');
    });

    test('失败回退 baseUrl / OrNull', () {
      expect(getSubDomain('ftp://x'), 'ftp://x');
      expect(getSubDomainOrNull('not-a-url'), isNull);
      expect(getSubDomainOrNull('http://www.biquge.com.cn'), 'biquge.com.cn');
    });
  });

  group('正则超时（RegexExtensions.kt / ReplaceRuleController.kt）', () {
    test('validTimeoutMillisecond：<=0 回退 3000', () {
      expect(validTimeoutMillisecond(0), 3000);
      expect(validTimeoutMillisecond(-5), 3000);
      expect(validTimeoutMillisecond(5000), 5000);
    });

    test('正常正则替换', () async {
      final r = await replaceRegexWithTimeout(
          input: 'a1b2c3', pattern: r'\d', replacement: '#');
      expect(r, 'a#b#c#');
    });

    test('isRegex=false 走字面替换', () async {
      final r = await replaceRegexWithTimeout(
          input: 'a.b.c', pattern: '.', replacement: '-', isRegex: false);
      expect(r, 'a-b-c');
    });

    test('非法正则 → FormatException', () async {
      await expectLater(
        replaceRegexWithTimeout(input: 'x', pattern: '[', replacement: ''),
        throwsA(isA<FormatException>()),
      );
    });

    test('灾难性回溯超时 → RegexTimeoutException（ReDoS 防护）', () async {
      await expectLater(
        replaceRegexWithTimeout(
          input: 'aaaaaaaaaaaaaaaaaaaaaaaa!',
          pattern: r'^(a+)+$',
          replacement: 'x',
          timeoutMillisecond: 1,
        ),
        throwsA(isA<RegexTimeoutException>()),
      );
    });
  });

  group('8 类异常层次 + ThrowableExtensions', () {
    test('8 类均为 NoStackTraceException 且堆栈为空', () {
      final all = <NoStackTraceException>[
        const NoStackTraceException('base'),
        const TocEmptyException(),
        const ContentEmptyException(),
        const EmptyFileException(),
        const InvalidBooksDirException(),
        const NoBooksDirException(),
        const RegexTimeoutException(),
        const ConcurrentException('限流', 1234),
      ];
      expect(all.length, 8);
      for (final e in all) {
        expect(e, isA<NoStackTraceException>());
        expect(e.stackTrace, StackTrace.empty);
      }
      expect((all.last as ConcurrentException).waitTime, 1234);
      expect(const NoBooksDirException().message, isNotEmpty);
    });

    test('stackTraceStr 与 asIOException（保留 cause）', () {
      expect(stackTraceStr(const ContentEmptyException('正文为空')), '正文为空');
      expect(stackTraceStr(StateError('boom'), StackTrace.current), isNotEmpty);
      final wrapped = asIOException(StateError('e'));
      expect(wrapped, isA<WrappedIOException>());
      expect(wrapped.cause, isA<StateError>());
    });
  });

  group('URL 边界（NetworkUtils.kt:59-190）', () {
    test('encodedQuery 保留集 / %XX 判定', () {
      expect(encodedQuery('abcABC012'), isTrue);
      expect(encodedQuery('a b'), isFalse);
      expect(encodedQuery('a%20b'), isTrue);
      expect(encodedQuery('a%ZZb'), isFalse);
      expect(encodedQuery(r'!$&()*+,-./:;=?@[\]^_`{|}~'), isTrue);
    });

    test('encodedForm 仅 *-._ 保留', () {
      expect(encodedForm('abc-._*'), isTrue);
      expect(encodedForm('a b'), isFalse);
      expect(encodedForm('a+b'), isFalse);
    });

    test('getAbsoluteURL 四类边界分支', () {
      expect(getAbsoluteURL(null, '  x  '), 'x');
      expect(getAbsoluteURL('', 'x'), 'x');
      expect(getAbsoluteURL('http://a.com/dir/page', '../img.png'),
          'http://a.com/img.png');
      expect(
          getAbsoluteURL('http://a.com', 'https://b.com/x'), 'https://b.com/x');
      expect(getAbsoluteURL('http://a.com', 'data:image/png;base64,xx'),
          'data:image/png;base64,xx');
      expect(getAbsoluteURL('http://a.com', 'javascript:void(0)'), '');
      // baseURL 逗号截断（data URL 选项场景）
      expect(getAbsoluteURL('http://a.com,{"k":1}', 'p'), 'http://a.com/p');
    });
  });

  // ---- 21. 原生侧边界（可等价实现的 Dart 部分）----
  group('多 IP 通知 / 严格 IPv4 / 渠道与通知 ID 常量', () {
    test('严格 IPv4 校验（首字符 1-9、3 点、每段 0..255）', () {
      expect(isStrictIPv4Address('192.168.1.5'), isTrue);
      expect(isStrictIPv4Address('0.1.2.3'), isFalse);
      expect(isStrictIPv4Address('256.1.1.1'), isFalse);
      expect(isStrictIPv4Address('1.2.3'), isFalse);
      expect(isStrictIPv4Address('1.2.3.4.5'), isFalse);
      expect(isStrictIPv4Address(null), isFalse);
    });

    test('多 IP 地址看板文本（全部网卡逐行 + 空列表占位）', () {
      expect(formatHostAddresses(['192.168.1.2', '10.0.0.3'], 1122),
          ['http://192.168.1.2:1122', 'http://10.0.0.3:1122']);
      expect(formatHostAddresses([], 1122), ['网络不可用']);
    });
  });

  group('原生契约常量（对齐 App.kt / NotificationId.kt / AppConst.kt）', () {
    test('三渠道 / 通知 ID 分段 / 复制与停止意图', () {
      expect(WebChannelIds.download, 'channel_download');
      expect(WebChannelIds.readAloud, 'channel_read_aloud');
      expect(WebChannelIds.web, 'channel_web');
      expect(WebNotificationIds.webService, 105);
      expect(WebNotificationIds.download, 10000);
      expect(WebNotificationIds.exportBook, 201);
      expect(WebServiceActions.copyHostAddress, 'copyHostAddress');
      expect(WebServiceActions.stop, 'stop');
      expect(WebServiceActions.serve, 'serve');
    });
  });
}
