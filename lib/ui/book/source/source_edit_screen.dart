import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:legado_md3/data/model/book_source.dart';
import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/db_models.dart';
import 'package:legado_md3/help/http/cookie_manager.dart';
import 'package:legado_md3/help/source/source_engine.dart';
import 'package:legado_md3/help/source/js/legado_js_runtime.dart';
import 'package:legado_md3/help/source/rule_auto_completer.dart';
import 'package:legado_md3/help/source/rule_complete.dart';
import 'package:legado_md3/ui/book/source/source_debug_screen.dart';
import 'package:legado_md3/ui/book/source/source_login_screen.dart';
import 'package:legado_md3/ui/book/search/search_screen.dart';
import 'package:legado_md3/ui/widgets/app_widgets.dart';

part 'parts/source_edit_screen_state.dart';
part 'parts/rule_field.dart';


/// 书源编辑页 —— -with-MD3：
/// 字段以“卡片预览 + 点击弹出底部多行编辑器”呈现，六个分页（基础/搜索/发现/详情/目录/正文），
/// 顶栏提供 调试 / 更多（登录、保存并搜索、清除 Cookie、规则补全、设置变量、复制、粘贴、分享、帮助）。
class SourceEditScreen extends StatefulWidget {
  final BookSource? source;
  const SourceEditScreen({super.key, this.source});

  @override
  State<SourceEditScreen> createState() => _SourceEditScreenState();
}
