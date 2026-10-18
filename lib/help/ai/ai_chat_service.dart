import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 一条聊天消息
class AiMessage {
  final String role; // user / assistant / system
  final String content;
  AiMessage(this.role, this.content);

  Map<String, String> toJson() => {'role': role, 'content': content};
}

/// AI 聊天服务：
/// - 默认走 OpenAI 兼容的 /chat/completions（可在聊天页配置 BaseUrl / Key / Model）；
/// - 未配置接口时使用内置离线助手兜底，保证功能始终可用。
class AiChatService {
  static const _kBaseUrl = 'ai_base_url';
  static const _kApiKey = 'ai_api_key';
  static const _kModel = 'ai_model';
  static const _kSystem = 'ai_system_prompt';

  String? baseUrl;
  String? apiKey;
  String model;
  String systemPrompt;
  bool _loaded = false;

  AiChatService({
    this.baseUrl,
    this.apiKey,
    this.model = 'gpt-4o-mini',
    this.systemPrompt = '你是“阅读 MD3”内置的读书助手，回答简洁、有条理，可帮助理解书籍、整理人物关系、总结章节、解释生词。',
  });

  bool get isConfigured => baseUrl != null && baseUrl!.trim().isNotEmpty;

  Future<void> load() async {
    if (_loaded) return;
    final p = await SharedPreferences.getInstance();
    baseUrl = p.getString(_kBaseUrl);
    apiKey = p.getString(_kApiKey);
    model = p.getString(_kModel) ?? model;
    systemPrompt = p.getString(_kSystem) ?? systemPrompt;
    _loaded = true;
  }

  Future<void> saveConfig({String? baseUrl, String? apiKey, String? model, String? systemPrompt}) async {
    this.baseUrl = baseUrl?.trim().isEmpty ?? true ? null : baseUrl?.trim();
    this.apiKey = apiKey?.trim().isEmpty ?? true ? null : apiKey?.trim();
    if (model != null && model.trim().isNotEmpty) this.model = model.trim();
    if (systemPrompt != null) this.systemPrompt = systemPrompt.trim();
    final p = await SharedPreferences.getInstance();
    await p.setString(_kBaseUrl, this.baseUrl ?? '');
    await p.setString(_kApiKey, this.apiKey ?? '');
    await p.setString(_kModel, this.model);
    await p.setString(_kSystem, this.systemPrompt);
  }

  Dio get _dio => Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 40),
        headers: {'Content-Type': 'application/json'},
      ));

  /// 发送一轮对话，[history] 不含本次用户消息与系统提示
  Future<String> send(String userText, List<AiMessage> history) async {
    await load();
    if (!isConfigured) return _offlineReply(userText);
    try {
      final messages = <Map<String, String>>[
        AiMessage('system', systemPrompt).toJson(),
        ...history.map((m) => m.toJson()),
        AiMessage('user', userText).toJson(),
      ];
      final endpoint = baseUrl!.replaceAll(RegExp(r'/+$'), '');
      final url = endpoint.endsWith('/chat/completions') ? endpoint : '$endpoint/v1/chat/completions';
      final resp = await _dio.post(
        url,
        data: {
          'model': model,
          'messages': messages,
          'temperature': 0.7,
          'stream': false,
        },
        options: Options(headers: {if (apiKey != null && apiKey!.isNotEmpty) 'Authorization': 'Bearer $apiKey'}),
      );
      final choices = resp.data['choices'];
      if (choices is List && choices.isNotEmpty) {
        final content = choices[0]['message']?['content'];
        if (content != null && content.toString().trim().isNotEmpty) return content.toString().trim();
      }
      return '（接口返回为空，请检查模型名或接口地址）';
    } on DioException catch (e) {
      return '请求失败：${e.message ?? e.type.name}。可在右上角设置中检查接口配置，或暂用离线助手。';
    } catch (e) {
      return '发生错误：$e';
    }
  }

  /// 离线兜底：无需联网的确定性读书助手
  String _offlineReply(String input) {
    final q = input.trim();
    if (q.isEmpty) return '我在，想聊点什么？';
    if (q.contains('总结') || q.contains('概括')) {
      return '【离线助手】总结章节的小方法：\n1. 先找出本章的人物、地点与核心冲突；\n2. 用“起因—经过—结果”三句话串联；\n3. 记录与主线相关的伏笔。\n配置 AI 接口后，我可以直接为你生成总结。';
    }
    if (q.contains('人物') || q.contains('关系')) {
      return '【离线助手】整理人物关系：列出出场人物 → 标注身份 → 用箭头连接彼此关系（盟友/对立/亲属）。配置接口后可自动生成关系图说明。';
    }
    if (q.contains('你是谁') || q.contains('功能') || q.contains('会什么')) {
      return '【离线助手】我是内置读书助手，能总结章节、解释词义、梳理人物关系、给阅读建议。当前为离线模式，在右上角“AI 设置”填入 OpenAI 兼容接口即可联网对话。';
    }
    return '【离线助手】我已收到：“$q”。\n当前未配置 AI 接口，仅能离线应答；点右上角设置填入兼容 OpenAI 的 BaseUrl / Key / 模型后即可获得完整回答。';
  }
}
