import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/ui/book/detail/parts/intro_render.dart';
import 'package:legado_md3/ui/book/detail/parts/delete_book_helper.dart';
import 'package:legado_md3/ui/main/bookshelf/parts/update_error_store.dart';

String src(String p) => File(p).readAsStringSync();

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // ——— #13 详情富文本简介：前缀分派 ———
  group('parseIntro 三前缀分派', () {
    test('普通简介为 plain 且保留原文', () {
      final s = parseIntro('这是一段纯文本简介');
      expect(s.kind, IntroKind.plain);
      expect(s.content, '这是一段纯文本简介');
      expect(parseIntro(null).content, '');
      expect(parseIntro('').kind, IntroKind.plain);
    });

    test('<useweb> / <usehtml> / <md> 分派并截掉末尾闭合标签', () {
      final web = parseIntro('<useweb><p>Hi <b>x</b></p></useweb>');
      expect(web.kind, IntroKind.useweb);
      expect(web.content, '<p>Hi <b>x</b></p>');

      final html = parseIntro('<usehtml><b>bold</b></usehtml>');
      expect(html.kind, IntroKind.usehtml);
      expect(html.content, '<b>bold</b>');

      final md = parseIntro('<md># 标题</md>');
      expect(md.kind, IntroKind.markdown);
      expect(md.content, '# 标题');
    });

    test('无闭合标签时整段退化为纯文本（E: lastIndex < 前缀长度）', () {
      final s = parseIntro('<md>没有闭合');
      expect(s.kind, IntroKind.plain);
      expect(s.content, '<md>没有闭合');
    });

    test('usewebBaseUrl 仅取 http(s) 且截取逗号前第一段', () {
      expect(usewebBaseUrl('https://a.com/book,https://b.com'),
          'https://a.com/book');
      expect(usewebBaseUrl('local:///x/book.txt'), isNull);
      expect(usewebBaseUrl(null), isNull);
      expect(usewebBaseUrl('HTTP://a.com/x'), 'HTTP://a.com/x');
    });
  });

  // ——— #13 scheme 拦截 ———
  group('简介链接 scheme 分类', () {
    test('http/https 放行，legado/yuedu 在线导入，其余外部', () {
      expect(classifyIntroUri(Uri.parse('https://a.com')),
          IntroLinkAction.allow);
      expect(classifyIntroUri(Uri.parse('http://a.com')),
          IntroLinkAction.allow);
      expect(classifyIntroUri(Uri.parse('legado://import/x')),
          IntroLinkAction.onlineImport);
      expect(classifyIntroUri(Uri.parse('yuedu://import/x')),
          IntroLinkAction.onlineImport);
      expect(classifyIntroUri(Uri.parse('tel:123')),
          IntroLinkAction.external);
      expect(classifyIntroUri(Uri.parse('ftp://x')),
          IntroLinkAction.external);
    });

    test('onlineImportLink 把 yuedu 归一化为 legado 复用在线导入', () {
      expect(onlineImportLink(Uri.parse('yuedu://import/x?src=a')),
          startsWith('legado://'));
      expect(onlineImportLink(Uri.parse('legado://import?url=x')),
          'legado://import?url=x');
    });
  });

  // ——— #13 <md> Markdown→HTML 降级转换 ———
  group('markdownToHtml / buildIntroDocument', () {
    test('标题、粗斜体、链接、图片、列表、表格、代码块', () {
      final html = markdownToHtml('# 标题\n'
          '**粗体** 和 *斜体* 与 `码`\n'
          '[官网](https://a.com) ![图](https://a.com/i.png)\n'
          '- 甲\n- 乙\n'
          '| A | B |\n| --- | --- |\n| 1 | 2 |\n'
          '```\n<int>&\n```');
      expect(html, contains('<h1>标题</h1>'));
      expect(html, contains('<b>粗体</b>'));
      expect(html, contains('<i>斜体</i>'));
      expect(html, contains('<code>码</code>'));
      expect(html, contains('<a href="https://a.com">官网</a>'));
      expect(html, contains('<img src="https://a.com/i.png" alt="图"/>'));
      expect(html, contains('<ul>'));
      expect(html, contains('<li>甲</li>'));
      expect(html, contains('</ul>'));
      expect(html, contains('<table'));
      expect(html, contains('<th>A</th>'));
      expect(html, contains('<td>1</td>'));
      expect(html, contains('&lt;int&gt;&amp;')); // 代码块内容被转义
      expect(html, contains('<pre><code>'));
    });

    test('useweb 原样返回；其余包 viewport 与暗色 CSS', () {
      expect(buildIntroDocument('<p>x</p>', dark: true, useweb: true),
          '<p>x</p>');
      final doc = buildIntroDocument('<p>x</p>', dark: true, useweb: false);
      expect(doc, contains('name="viewport"'));
      expect(doc, contains('#121212'));
      expect(doc, contains('<p>x</p>'));
    });
  });

  // ——— #15 删除源文件纯函数 ———
  group('删除源文件助手', () {
    test('localBookSourcePath 优先 fileName，回退 local://', () {
      expect(
          localBookSourcePath(
              Book(name: 'n', author: 'a', fileName: '/path/book.txt')),
          '/path/book.txt');
      expect(
          localBookSourcePath(Book(
              name: 'n', author: 'a', bookUrl: 'local:///path/book.txt')),
          '/path/book.txt');
      expect(localBookSourcePath(Book(name: 'n', author: 'a')), isNull);
    });

    test('canDeleteSourceFile 拒绝 content:// 等系统 URI', () {
      expect(canDeleteSourceFile('/path/book.txt'), isTrue);
      expect(canDeleteSourceFile('content://media/1'), isFalse);
      expect(canDeleteSourceFile(null), isFalse);
    });

    test('applyDeleteBookChoice 未确认不删、确认才删 DB', () async {
      var calls = 0;
      final book = Book(name: 'n', author: 'a'); // 非本地，不触发文件 IO
      await applyDeleteBookChoice(
          book, const DeleteBookChoice(false, false), () async => calls++);
      expect(calls, 0);
      await applyDeleteBookChoice(
          book, const DeleteBookChoice(true, false), () async => calls++);
      expect(calls, 1);
    });
  });

  // ——— #14 updateError 标记存储（真实读写） ———
  group('updateError 标记幂等增删', () {
    test('mark/clear 幂等且 key 为 name::author', () {
      final book = Book(name: '斗破苍穹', author: '天蚕土豆');
      expect(updateErrorBookKey(book), '斗破苍穹::天蚕土豆');
    });

    test('SharedPreferences 集合读写幂等', () async {
      final book = Book(name: 'A', author: 'B');
      expect(await loadUpdateErrorBooks(), isEmpty);
      await markUpdateError(book);
      expect(await loadUpdateErrorBooks(), contains('A::B'));
      await markUpdateError(book);
      expect((await loadUpdateErrorBooks()).length, 1);
      await clearUpdateError(book);
      expect(await loadUpdateErrorBooks(), isEmpty);
    });
  });

  // ——— 源码契约（防止回归 / 防回退批次 1） ———
  group('搜索分页 #12 源码契约', () {
    test('按源 page + hasMore + 滚到底 + FAB + 焦点 + 生命周期全部落地', () {
      final s = src('lib/ui/book/search/search_screen.dart');
      expect(s, contains('_searchPage++'), reason: '续页自增页码');
      expect(s, contains('page: page'), reason: '按源把 page 传给引擎');
      expect(s, contains('_hasMore = pageHasMore'),
          reason: 'hasMore = 本页至少一个源有结果');
      expect(s, contains('_mergeResults(results)'),
          reason: '多页结果累积归并');
      expect(s, contains('floatingActionButton: _buildSearchFab()'));
      expect(s, contains('Icons.play_arrow'), reason: 'FAB 继续态');
      expect(s, contains('Icons.stop'), reason: 'FAB 停止态');
      expect(s, contains('_isManualStop'), reason: '手动停止后续搜');
      expect(s, contains('PopScope'), reason: 'finish 先清焦点');
      expect(s, contains('_searchFocus.unfocus()'));
      expect(s, contains('NotificationListener<ScrollNotification>'),
          reason: '滚到底自动续页');
      expect(s, contains('_scrollToBottom()'));
      expect(s, contains('didChangeAppLifecycleState'),
          reason: 'pause/resume 生命周期');
      expect(s, contains('precisionSearch'), reason: '精准搜索持久化');
      expect(s, contains('showAppConfirmDialog'), reason: '空结果建议弹窗');
    });

    test('搜索页结果为 单列横向列表', () {
      final s = src('lib/ui/book/search/search_screen.dart');
      expect(s, contains('ListView.separated'));
      expect(s.contains('GridView.builder'), isFalse,
          reason: '搜索页应为单列列表，不再是 3 列网格');
      expect(s, contains('const coverW = 80.0'));
      expect(s.contains('width: 50,'), isFalse);
    });

    test('批次 1 章节替换规则标题通道未被回退', () {
      final s = src('lib/ui/book/chapter/chapter_list_screen.dart');
      expect(s, contains('isTitle: true'));
    });
  });

  group('详情 #13/#15 源码契约', () {
    test('富文本简介、模糊背景、大图、点击搜索、删除源文件均已接线', () {
      final s = src('lib/ui/book/detail/book_detail_screen.dart');
      expect(s, contains('IntroRichView(spec: spec, bookUrl: book.bookUrl)'));
      expect(s, contains('parseIntro(book.intro)'));
      expect(s, contains('ImageFilter.blur'), reason: '封面高斯模糊背景');
      expect(s, contains('_eink'), reason: '墨水屏禁用模糊');
      expect(s, contains('IntroImagePreview(url: cover)'),
          reason: '封面长按大图');
      expect(s, contains('_searchKeyword(book.name)'));
      expect(s, contains('_searchKeyword(book.author)'));
      expect(s, contains('_searchableTag'), reason: '标签点击搜索');
      expect(s, contains('FileHelper.formatFileSize'),
          reason: '本地书标签追加文件大小');
      expect(s, contains('showDeleteBookConfirm'));
      expect(s, contains('applyDeleteBookChoice'));
      expect(s, contains('kDeleteBookOriginalPref'),
          reason: '删除提醒关闭时按偏好删源文件');
      expect(s, contains('clearUpdateError(widget.book)'),
          reason: '关允许更新清 updateError');
    });

    test('intro_render.dart 含 scheme 拦截与图片长按', () {
      final s = src('lib/ui/book/detail/parts/intro_render.dart');
      expect(s, contains('shouldOverrideUrlLoading'));
      expect(s, contains('onLongPressHitTestResult'));
      expect(s, contains('DeepLinkService.instance.handleLink'));
      expect(s, contains('canLaunchUrl'));
      expect(s, contains('InAppWebViewInitialData'));
    });

    test('delete_book_helper.dart 复选框有真实消费点', () {
      final s = src('lib/ui/book/detail/parts/delete_book_helper.dart');
      expect(s, contains("'deleteBookOriginal'"));
      expect(s, contains('tryDeleteLocalSource'));
      expect(s, contains('prefs.setBool(kDeleteBookOriginalPref'));
      expect(s, contains('Checkbox('));
      expect(s, contains('同时删除源文件'));
    });
  });

  group('书架更新目录容错 #14 源码契约', () {
    test('去重/onlyUpdateRead/updateError/预下载/并发池全部接入', () {
      final s =
          src('lib/ui/main/bookshelf/parts/bookshelf_screen_state.dart');
      expect(s, contains("only_update_read"));
      expect(s, contains('_waitUpTocBooks'), reason: '双集合去重 wait');
      expect(s, contains('_onUpTocBooks'), reason: '双集合去重 on');
      expect(s, contains('_unread(b) > 0'), reason: 'onlyUpdateRead 跳过未读完');
      expect(s, contains('markUpdateError(book)'));
      expect(s, contains('clearUpdateError(book)'));
      expect(s, contains('AppPrefs.threadCount'), reason: '并发池');
      expect(s, contains('AppPrefs.preDownloadNum'));
      expect(s, contains('_preDownload(t.book'), reason: '目录更新完才预下载');
      expect(s, contains('updateErrorBookKey(book)'),
          reason: 'updateError 封面角标消费');
      expect(s, contains('showDeleteBookConfirm'),
          reason: '书架长按删除接复选框');
    });
  });
}
