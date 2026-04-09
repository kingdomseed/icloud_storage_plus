import 'package:equatable/equatable.dart';
import 'package:icloud_storage_plus/models/download_status.dart';
import 'package:icloud_storage_plus/models/exceptions.dart';

/// Typed metadata for a known iCloud item path.
class ICloudItemMetadata extends Equatable {
  /// Creates metadata from a platform channel map.
  ICloudItemMetadata.fromMap(Map<dynamic, dynamic> map)
      : relativePath = _requireRelativePath(map),
        isDirectory = (map['isDirectory'] as bool?) ?? false,
        sizeInBytes = _mapToInt(map['sizeInBytes']),
        creationDate = _mapToDateTime(map['creationDate']),
        contentChangeDate = _mapToDateTime(map['contentChangeDate']),
        downloadStatus = parseDownloadStatus(map['downloadStatus'] as String?),
        isDownloading = (map['isDownloading'] as bool?) ?? false,
        isUploading = (map['isUploading'] as bool?) ?? false,
        isUploaded = (map['isUploaded'] as bool?) ?? false,
        hasUnresolvedConflicts =
            (map['hasUnresolvedConflicts'] as bool?) ?? false;

  /// File path relative to the iCloud container.
  final String relativePath;

  /// True when the item represents a directory.
  final bool isDirectory;

  /// Nullable when the platform does not provide it.
  final int? sizeInBytes;

  /// Nullable when the platform does not provide it.
  final DateTime? creationDate;

  /// Nullable when the platform does not provide it.
  final DateTime? contentChangeDate;

  /// Nullable when the platform does not provide it.
  final DownloadStatus? downloadStatus;

  /// Whether the system is actively downloading this item.
  final bool isDownloading;

  /// Whether the system is actively uploading this item.
  final bool isUploading;

  /// Whether this item has been uploaded to iCloud.
  final bool isUploaded;

  /// Whether this item has unresolved version conflicts.
  final bool hasUnresolvedConflicts;

  /// Whether the item has local content available.
  bool get isLocal =>
      downloadStatus == DownloadStatus.downloaded ||
      downloadStatus == DownloadStatus.current;

  static String _requireRelativePath(Map<dynamic, dynamic> map) {
    final value = map['relativePath'];
    if (value is String) return value;
    throw InvalidArgumentException(
      'relativePath is required and must be a String '
      '(got: ${value.runtimeType})',
    );
  }

  static int? _mapToInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.round();
    if (value is num) return value.toInt();
    return null;
  }

  static DateTime? _mapToDateTime(dynamic value) {
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch((value * 1000).round());
    }
    return null;
  }

  @override
  List<Object?> get props => [
        relativePath,
        isDirectory,
        sizeInBytes,
        creationDate,
        contentChangeDate,
        downloadStatus,
        isDownloading,
        isUploading,
        isUploaded,
        hasUnresolvedConflicts,
      ];
}
