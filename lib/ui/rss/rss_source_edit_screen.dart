import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../data/model/rss_source.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/help/http/rss_service.dart';
import 'package:legado_md3/help/source/rule_auto_completer.dart';
import 'package:legado_md3/help/source/rule_complete.dart';
import 'package:legado_md3/help/source/js/legado_js_runtime.dart';
import 'package:legado_md3/ui/widgets/app_widgets.dart';

part 'parts/f.dart';
part 'parts/rss_source_edit_screen_state.dart';


/// RSS源编辑页面 —— 与书源编辑页同款 MD3 卡片式交互（4 分页）。
/// 字段以“卡片预览 + 点击弹出底部多行编辑器”呈现；顶栏提供 测试 / 保存 / 更多
/// （规则补全、复制、粘贴、分享）。列表规则由 RssService 实际生效。
class RssSourceEditScreen extends StatefulWidget {
  final RssSource? source;
  const RssSourceEditScreen({super.key, this.source});

  @override
  State<RssSourceEditScreen> createState() => _RssSourceEditScreenState();
}
