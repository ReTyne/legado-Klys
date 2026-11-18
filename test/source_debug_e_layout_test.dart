import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 书源调试界面「完全照搬 E 版布局」且「K 版增强功能一项不删」的源码契约。
///
/// E 版 BookSourceDebugActivity 的一页式形态：
///  * 标题栏内嵌调试搜索框（view_search）
///  * 帮助示例（我的 / 系统 / 系统::URL / 详情URL / ++目录URL / --正文URL）
///  * 单一日志列表（item_log：可选文本 + 自动链接）
///  * 36dp 加载圈（RotateLoading）
///  * 菜单：搜索源码 / 详情源码 / 目录源码 / 正文源码 / 刷新发现 / 帮助 / 扫码
///
/// K 版保留的增强能力（收进「高级调试」次级视图，不删）：
///  分步调试 / 发现分类 / 请求响应 / 变量 / 原始源码。
void main() {
  late String src;
  setUpAll(() {
    src = File('lib/ui/book/source/parts/source_debug_screen_state.dart')
        .readAsStringSync();
  });

  group('E 版一页式布局要素', () {
    test('标题栏内嵌调试搜索框（hint 提示默认词与地址形态）', () {
      expect(src, contains('调试地址 / 关键词（默认「我的」）'));
      expect(src, contains('prefixIcon: Icon(Icons.search)'));
    });

    test('帮助示例区含 E 版 6 类示例', () {
      expect(src, contains('_kHelpSamples'));
      for (final sample in const [
        "'我的'", "'系统'", "'系统::http://'", "'https://'",
        "'++https://'", "'--https://'",
      ]) {
        expect(src, contains(sample), reason: '缺少 E 版帮助示例 $sample');
      }
      expect(src, contains('ActionChip'), reason: '帮助示例应为可点击 chip');
    });

    test('单一日志列表：可选文本 + E 版 item_log 形态', () {
      expect(src, contains('_buildELogView'));
      expect(src, contains('SelectableText.rich'));
    });

    test('36dp 加载圈（对齐 E 版 rotate_loading 36dp）', () {
      expect(src, contains('width: 36'));
      expect(src, contains('height: 36'));
      expect(src, contains('CircularProgressIndicator(strokeWidth: 2)'));
    });
  });

  group('E 版菜单项', () {
    for (final item in const [
      '搜索源码', '详情源码', '目录源码', '正文源码',
      '刷新发现', '帮助',
    ]) {
      test('菜单含「$item」', () {
        expect(src, contains("Text('$item')"),
            reason: '菜单缺少 E 版项 $item');
      });
    }
    test('菜单动作统一分发', () {
      expect(src, contains('_onMenuAction'));
      expect(src, contains("_showSourceDialog('search'"));
      expect(src, contains("_showSourceDialog('book'"));
      expect(src, contains("_showSourceDialog('toc'"));
      expect(src, contains("_showSourceDialog('content'"));
    });
  });

  group('K 版增强功能一项不删', () {
    test('6 页签增强视图完整保留', () {
      expect(src, contains('_buildAdvancedView'));
      for (final t in const [
        '一键调试', '分步调试', '发现分类', '请求响应', '变量', '原始源码',
      ]) {
        expect(src, contains("Tab(text: '$t')"), reason: '缺少增强页签 $t');
      }
    });
    test('全部增强视图构建方法仍在且被调用', () {
      for (final m in const [
        '_buildStepView', '_buildExploreView', '_buildNetworkView',
        '_buildVariableView', '_buildSourceView',
      ]) {
        expect(src, contains('$m()'), reason: '增强视图 $m 丢失');
      }
    });
    test('增强模式可切换（高级调试 / 返回）', () {
      expect(src, contains('_advancedMode'));
      expect(src, contains('高级调试 / 返回'));
    });
  });

  group('默认搜索词与调试目标解析兼容 E 版示例', () {
    test('_parseDebugTarget 覆盖 E 版全部前缀语义', () {
      // E 版：搜索词 / 系统::URL（发现）/ 详情URL / ++目录 / --正文
      expect(src, contains("startsWith('++')"));
      expect(src, contains("startsWith('--')"));
      expect(src, contains("indexOf('::')"));
      expect(src, contains(r"RegExp(r'^https?://')"));
    });
  });
}
