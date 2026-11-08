/// 由 backup_service.dart 按「一类一文件」拆出的 BackupFileInfo。
/// 作为同一库的 part，私有成员互引保持可用。
part of '../backup_service.dart';


/// 备份文件概要信息（恢复界面展示用）
class BackupFileInfo {
  final String fileName;
  final bool isZip;
  final bool encrypted;
  final String? deviceName;
  final String? backupTime;
  final BackupSelection selection;
  final String? error;
  BackupFileInfo({
    required this.fileName,
    required this.isZip,
    required this.encrypted,
    required this.selection,
    this.deviceName,
    this.backupTime,
    this.error,
  });
}
