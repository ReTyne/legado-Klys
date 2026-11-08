/// 由 backup_service.dart 按「一类一文件」拆出的 BackupDirResult。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../backup_service.dart';


/// 备份目录解析结果
class BackupDirResult {
  /// 实际使用的备份目录
  final Directory directory;
  /// true 表示用户配置的路径不可用，已回退到默认目录
  final bool fallback;
  /// 回退原因（供 UI 提示），未回退时为 null
  final String? error;
  const BackupDirResult(this.directory, this.fallback, this.error);
}
