import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:legado_md3/data/local/app_database.dart';
import 'package:legado_md3/data/model/v14_models.dart';

/// 一次 Agent 回复：正文 + 本轮真实执行过的工具日志（供聊天页展示多轮过程）。
class AgentReply {
  final String text;
  final List<String> toolLog;
  const AgentReply(this.text, {this.toolLog = const []});
}

/// 内置工具处理器标识（与 `AiAgentTool.handler` 对应）。
abstract final class BuiltinToolHandlers {
  static const searchBooks = 'search_books';
  static const getToc = 'get_toc';
  static const getChapterContent = 'get_chapter_content';
  static const listBookSources = 'list_book_sources';
}

/// AI Agent 工具注册表：落库到 `ai_agent_tools`（v14），并提供 4 个真实可跑的内置工具。
///
/// 工具既能被 LLM 以 OpenAI `tool_calls` 协议调用，也能在离线模式下按用户意图
/// 直接执行，保证未配置 AI 接口时工具链依然可用（不是空壳）。
class AgentToolRegistry {
  AgentToolRegistry();
  final DatabaseService _db = DatabaseService();

  static const List<AiAgentTool> defaults = [
    AiAgentTool(
      name: 'search_books',
      description: '按书名或作者关键词搜索本地书架中的书籍，返回书名、作者、类型与最近章节。',
      schema:
          '{"type":"object","properties":{"keyword":{"type":"string","description":"书名或作者关键词"},"limit":{"type":"integer","description":"最多返回条数，默认10"}},"required":["keyword"]}',
      handler: BuiltinToolHandlers.searchBooks,
    ),
    AiAgentTool(
      name: 'get_toc',
      description: '查询指定书籍的目录（章节序号与标题）。',
      schema:
          '{"type":"object","properties":{"book":{"type":"string","description":"书名"},"author":{"type":"string","description":"作者，可为空"},"limit":{"type":"integer","description":"最多返回章节数，默认30"}},"required":["book"]}',
      handler: BuiltinToolHandlers.getToc,
    ),
    AiAgentTool(
      name: 'get_chapter_content',
      description: '读取指定书籍某一章的正文内容（已缓存的内容），可限制返回字数。',
      schema:
          '{"type":"object","properties":{"book":{"type":"string","description":"书名"},"author":{"type":"string","description":"作者，可为空"},"chapter":{"type":"integer","description":"章节下标，从0开始"},"maxChars":{"type":"integer","description":"最多返回字数，默认2000"}},"required":["book","chapter"]}',
      handler: BuiltinToolHandlers.getChapterContent,
    ),
    AiAgentTool(
      name: 'list_book_sources',
      description: '查询本地书源列表（名称 / 地址 / 类型 / 是否启用），可按关键词与类型过滤。',
      schema:
          '{"type":"object","properties":{"keyword":{"type":"string","description":"书源名关键词，可为空"},"type":{"type":"integer","description":"书源类型：0文本 1音频 2图片 3文件 4视频，-1表示全部"}},"required":[]}',
      handler: BuiltinToolHandlers.listBookSources,
    ),
  ];

  /// 首次运行写入 4 个内置工具（已存在则保留用户的启停状态）。
  Future<void> ensureDefaults() async {
    final existing = await _db.getAiAgentTools();
    final names = existing.map((e) => e.name).toSet();
    for (final d in defaults) {
      if (!names.contains(d.name)) await _db.upsertAiAgentTool(d);
    }
  }

  Future<List<AiAgentTool>> tools({bool onlyEnabled = false}) =>
      _db.getAiAgentTools(onlyEnabled: onlyEnabled);

  Future<void> setEnabled(AiAgentTool t, bool enabled) =>
      _db.upsertAiAgentTool(AiAgentTool(
        id: t.id,
        name: t.name,
        description: t.description,
        schema: t.schema,
        handler: t.handler,
        enabled: enabled ? 1 : 0,
      ));

  Future<void> remove(int id) => _db.deleteAiAgentTool(id);

  /// 分发执行一个工具，返回可回填给 LLM 的文本结果。
  Future<String> execute(String handler, Map<String, dynamic> args) async {
    switch (handler) {
      case BuiltinToolHandlers.searchBooks:
        return _searchBooks(args);
      case BuiltinToolHandlers.getToc:
        return _getToc(args);
      case BuiltinToolHandlers.getChapterContent:
        return _getChapterContent(args);
      case BuiltinToolHandlers.listBookSources:
        return _listBookSources(args);
      // 自定义工具：按名字再匹配一次内置注册表，未知则给出明确回执
      default:
        for (final d in defaults) {
          if (d.name == handler) return execute(d.handler, args);
        }
        return '未找到工具处理器「$handler」，请在工具管理页检查该工具的 handler 配置。';
    }
  }

  Future<String> _searchBooks(Map<String, dynamic> args) async {
    final keyword = (args['keyword'] ?? '').toString().trim().toLowerCase();
    final limit = (args['limit'] is num) ? (args['limit'] as num).toInt() : 10;
    final books = await _db.getAllBooks();
    final hits = books
        .where((b) =>
            keyword.isEmpty ||
            b.name.toLowerCase().contains(keyword) ||
            b.author.toLowerCase().contains(keyword))
        .take(limit.clamp(1, 50))
        .toList();
    if (hits.isEmpty) return '未找到匹配「$keyword」的书籍。';
    final sb = StringBuffer('找到 ${hits.length} 本书：\n');
    for (final b in hits) {
      sb.writeln('- ${b.name} / ${b.author} [类型${b.type}] 最近：${b.lastChapter ?? "无"}');
    }
    return sb.toString().trim();
  }

  Future<String> _getToc(Map<String, dynamic> args) async {
    final book = (args['book'] ?? '').toString().trim();
    if (book.isEmpty) return '缺少参数 book（书名）。';
    final author = (args['author'] ?? '').toString().trim();
    final limit = (args['limit'] is num) ? (args['limit'] as num).toInt() : 30;
    final chapters = await _db.getChapters(book, author);
    if (chapters.isEmpty) return '《$book》没有目录数据。';
    final sb = StringBuffer('《$book》共 ${chapters.length} 章：\n');
    for (final c in chapters.take(limit.clamp(1, 200))) {
      sb.writeln('${c.index}. ${c.title}');
    }
    if (chapters.length > limit) sb.writeln('…（其余 ${chapters.length - limit} 章已省略）');
    return sb.toString().trim();
  }

  Future<String> _getChapterContent(Map<String, dynamic> args) async {
    final book = (args['book'] ?? '').toString().trim();
    final author = (args['author'] ?? '').toString().trim();
    final chapter = (args['chapter'] is num) ? (args['chapter'] as num).toInt() : 0;
    final maxChars =
        (args['maxChars'] is num) ? (args['maxChars'] as num).toInt() : 2000;
    final chapters = await _db.getChapters(book, author);
    if (chapters.isEmpty) return '《$book》没有目录数据。';
    final hit = chapters.where((c) => c.index == chapter).toList();
    if (hit.isEmpty) return '《$book》没有第 $chapter 章。';
    var content = hit.first.content;
    if (content == null || content.trim().isEmpty) {
      // 缓存缺失时直接读表，保证工具返回真实数据
      final db = await _db.database;
      final rows = await db.query('book_chapters',
          columns: ['content'],
          where: 'bookName = ? AND bookAuthor = ? AND chapter_index = ?',
          whereArgs: [book, author, chapter],
          limit: 1);
      content = rows.isEmpty ? null : rows.first['content']?.toString();
    }
    if (content == null || content.trim().isEmpty) {
      return '《$book》第 $chapter 章「${hit.first.title}」正文尚未缓存，请先在阅读器中打开该章。';
    }
    final text = content.trim();
    final clipped = text.length > maxChars ? text.substring(0, maxChars) : text;
    return '《$book》第 $chapter 章「${hit.first.title}」正文（${text.length} 字）：\n$clipped';
  }

  Future<String> _listBookSources(Map<String, dynamic> args) async {
    final keyword = (args['keyword'] ?? '').toString().trim().toLowerCase();
    final type = (args['type'] is num) ? (args['type'] as num).toInt() : -1;
    final sources = await _db.getAllSources();
    final hits = sources
        .where((s) =>
            (keyword.isEmpty ||
                s.bookSourceName.toLowerCase().contains(keyword)) &&
            (type < 0 || s.bookSourceType == type))
        .toList();
    if (hits.isEmpty) return '没有匹配的书源。';
    final sb = StringBuffer('共 ${hits.length} 个书源：\n');
    for (final s in hits.take(40)) {
      sb.writeln(
          '- ${s.bookSourceName} [类型${s.bookSourceType}] ${s.enabled ? "启用" : "停用"} ${s.bookSourceUrl}');
    }
    return sb.toString().trim();
  }
}

/// Agent 对话运行时：保持与现有 `AiChatService` 相同的 OpenAI 兼容配置键
/// （`ai_base_url` / `ai_api_key` / `ai_model` / `ai_system_prompt`），
/// 在其上增加 `tools` 注册与 `tool_calls` 多轮回填。
class AgentToolRuntime {
  AgentToolRuntime(this.registry);
  final AgentToolRegistry registry;

  static const _maxRounds = 6;

  Future<AgentReply> chat(String userText, List<({String role, String content})> history) async {
    final p = await SharedPreferences.getInstance();
    final baseUrl = p.getString('ai_base_url') ?? '';
    final apiKey = p.getString('ai_api_key') ?? '';
    final model = p.getString('ai_model') ?? 'gpt-4o-mini';
    final system = p.getString('ai_system_prompt') ??
        '你是"阅读"内置的读书助手，可以调用工具检索书架、目录、章节正文与书源，回答简洁、有条理。';

    final tools = await registry.tools(onlyEnabled: true);
    if (baseUrl.trim().isEmpty) {
      return _offlineAgent(userText, tools);
    }

    final endpoint = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final url = endpoint.endsWith('/chat/completions')
        ? endpoint
        : '$endpoint/v1/chat/completions';
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 60),
      headers: {
        'Content-Type': 'application/json',
        if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
      },
    ));

    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': system},
      for (final m in history)
        if (m.role == 'user' || m.role == 'assistant')
          {'role': m.role, 'content': m.content},
      {'role': 'user', 'content': userText},
    ];
    final toolDefs = <Map<String, dynamic>>[
      for (final t in tools)
        {
          'type': 'function',
          'function': {
            'name': t.name,
            'description': t.description,
            'parameters': _safeSchema(t.schema),
          },
        },
    ];
    final log = <String>[];

    try {
      for (var round = 0; round < _maxRounds; round++) {
        final resp = await dio.post(url, data: {
          'model': model,
          'messages': messages,
          'temperature': 0.7,
          'stream': false,
          if (toolDefs.isNotEmpty) 'tools': toolDefs,
          if (toolDefs.isNotEmpty) 'tool_choice': 'auto',
        });
        final choices = resp.data['choices'];
        if (choices is! List || choices.isEmpty) {
          return AgentReply('（接口返回为空，请检查模型名或接口地址）', toolLog: log);
        }
        final msg = choices[0]['message'];
        if (msg is! Map) {
          return AgentReply('（接口返回格式异常）', toolLog: log);
        }
        final toolCalls = msg['tool_calls'];
        if (toolCalls is List && toolCalls.isNotEmpty) {
          messages.add(Map<String, dynamic>.from(msg));
          for (final call in toolCalls) {
            if (call is! Map) continue;
            final fn = call['function'];
            final name = fn is Map ? (fn['name'] ?? '').toString() : '';
            var rawArgs = fn is Map ? fn['arguments'] : null;
            Map<String, dynamic> args;
            try {
              args = rawArgs is String
                  ? Map<String, dynamic>.from(jsonDecode(rawArgs.isEmpty ? '{}' : rawArgs) as Map)
                  : Map<String, dynamic>.from((rawArgs as Map?) ?? {});
            } catch (_) {
              args = <String, dynamic>{};
            }
            AiAgentTool? tool;
            for (final t in tools) {
              if (t.name == name) {
                tool = t;
                break;
              }
            }
            final result = await registry.execute(tool?.handler ?? name, args);
            log.add('$name → ${result.length > 120 ? "${result.substring(0, 120)}…" : result}');
            messages.add({
              'role': 'tool',
              'tool_call_id': call['id'] ?? name,
              'content': result,
            });
          }
          continue; // 回填后进入下一轮，直到 LLM 给出最终回答
        }
        final content = msg['content']?.toString().trim() ?? '';
        return AgentReply(content.isEmpty ? '（模型未返回文本）' : content, toolLog: log);
      }
      return AgentReply('（工具调用轮次已达上限，已执行 ${log.length} 次工具）', toolLog: log);
    } on DioException catch (e) {
      return AgentReply('请求失败：${e.message ?? e.type.name}。可改用离线工具模式或检查接口配置。',
          toolLog: log);
    } catch (e) {
      return AgentReply('发生错误：$e', toolLog: log);
    }
  }

  Map<String, dynamic> _safeSchema(String schema) {
    try {
      final v = jsonDecode(schema);
      if (v is Map) return Map<String, dynamic>.from(v);
    } catch (_) {}
    return {'type': 'object', 'properties': <String, dynamic>{}};
  }

  /// 离线：按用户意图真实执行已启用工具（无需 LLM），让工具链始终可跑。
  Future<AgentReply> _offlineAgent(String q, List<AiAgentTool> tools) async {
    bool enabled(String handler) {
      for (final t in tools) {
        if (t.handler == handler) return true;
      }
      return false;
    }

    final log = <String>[];
    Future<String> run(String handler, Map<String, dynamic> args) async {
      final r = await registry.execute(handler, args);
      log.add('$handler → ${r.length > 120 ? "${r.substring(0, 120)}…" : r}');
      return r;
    }

    String? bookNameFrom(String s) {
      final m = RegExp(r'《([^》]+)》').firstMatch(s);
      return m?.group(1);
    }

    if ((q.contains('书源') || q.contains('源头')) && enabled(BuiltinToolHandlers.listBookSources)) {
      final r = await run(BuiltinToolHandlers.listBookSources, {'keyword': ''});
      return AgentReply('【离线工具·查书源】\n$r', toolLog: log);
    }
    if ((q.contains('目录') || q.contains('章节列表') || q.contains('有哪些章')) &&
        enabled(BuiltinToolHandlers.getToc)) {
      final book = bookNameFrom(q) ?? (await _firstBookName());
      if (book == null) return AgentReply('【离线工具】书架上暂无书籍，无法查询目录。', toolLog: log);
      final r = await run(BuiltinToolHandlers.getToc, {'book': book, 'limit': 30});
      return AgentReply('【离线工具·查目录】\n$r', toolLog: log);
    }
    if ((q.contains('正文') || q.contains('内容') || q.contains('读一下') || q.contains('读第')) &&
        enabled(BuiltinToolHandlers.getChapterContent)) {
      final book = bookNameFrom(q) ?? (await _firstBookName());
      if (book == null) return AgentReply('【离线工具】书架上暂无书籍。', toolLog: log);
      final cm = RegExp(r'第\s*(\d+)\s*章').firstMatch(q);
      final chapter = cm != null ? (int.tryParse(cm.group(1)!) ?? 1) - 1 : 0;
      final r = await run(BuiltinToolHandlers.getChapterContent,
          {'book': book, 'chapter': chapter, 'maxChars': 1500});
      return AgentReply('【离线工具·取章节内容】\n$r', toolLog: log);
    }
    if ((q.contains('找') || q.contains('搜索') || q.contains('书架') || q.contains('有哪些书')) &&
        enabled(BuiltinToolHandlers.searchBooks)) {
      final kw = q
          .replaceAll(RegExp('帮我|搜索|查找|找一下|找找|书架|有哪些|书|的|？|\\?|，|。'), '')
          .trim();
      final r = await run(BuiltinToolHandlers.searchBooks, {'keyword': kw, 'limit': 10});
      return AgentReply('【离线工具·搜索书籍】\n$r', toolLog: log);
    }
    final names = tools.map((t) => t.name).join(' / ');
    return AgentReply(
      '当前为离线工具模式，已启用工具：$names。\n'
      '可以直接说：「搜索 xxx」「《书名》的目录」「《书名》第 3 章内容」「列出书源」；'
      '或在右上角「AI 设置」填入 OpenAI 兼容接口，由模型自动决定调用哪个工具。',
      toolLog: log,
    );
  }

  Future<String?> _firstBookName() async {
    final books = await DatabaseService().getAllBooks();
    return books.isEmpty ? null : books.first.name;
  }
}
