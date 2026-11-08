import 'package:flutter/foundation.dart';

/// AI Agent 工具注册（对齐 fork AI Agent 工具链）
@immutable
class AiAgentTool {
  final int? id;
  final String name;
  final String description;
  final String schema; // JSON Schema
  final String handler; // 处理器标识（Dart 侧分发键）
  final int enabled;

  const AiAgentTool({
    this.id,
    required this.name,
    this.description = '',
    this.schema = '{}',
    required this.handler,
    this.enabled = 1,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'description': description,
        'schema': schema,
        'handler': handler,
        'enabled': enabled,
      };

  factory AiAgentTool.fromMap(Map<String, dynamic> m) => AiAgentTool(
        id: m['id'],
        name: m['name'] ?? '',
        description: m['description'] ?? '',
        schema: m['schema'] ?? '{}',
        handler: m['handler'] ?? '',
        enabled: m['enabled'] ?? 1,
      );
}
