/// 设置领域模型：聚合各设置分类开关
class AppSettings {
  final String language;
  final bool autoCheckUpdate;
  final bool webAutoStart;
  final int webPort;
  final String? localPassword;

  const AppSettings({
    this.language = 'system',
    this.autoCheckUpdate = true,
    this.webAutoStart = false,
    this.webPort = 1122,
    this.localPassword,
  });

  AppSettings copyWith({
    String? language,
    bool? autoCheckUpdate,
    bool? webAutoStart,
    int? webPort,
    String? localPassword,
  }) => AppSettings(
    language: language ?? this.language,
    autoCheckUpdate: autoCheckUpdate ?? this.autoCheckUpdate,
    webAutoStart: webAutoStart ?? this.webAutoStart,
    webPort: webPort ?? this.webPort,
    localPassword: localPassword ?? this.localPassword,
  );
}

/// 阅读排版设置
class TypographySettings {
  final double fontSize;
  final double lineSpacing;
  final double paragraphSpacing;
  final String? fontFamily;
  final bool bold;
  final int textColor;
  final int bgColor;

  const TypographySettings({
    this.fontSize = 18,
    this.lineSpacing = 1.2,
    this.paragraphSpacing = 8,
    this.fontFamily,
    this.bold = false,
    this.textColor = 0xFF333333,
    this.bgColor = 0xFFF7F1E1,
  });
}
