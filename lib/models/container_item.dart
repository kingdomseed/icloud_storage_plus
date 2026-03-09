import 'package:equatable/equatable.dart';
import 'package:icloud_storage_plus/models/exceptions.dart';
import 'package:icloud_storage_plus/models/icloud_file.dart';

/// A file or directory entry from the iCloud ubiquity container, enumerated
/// via `FileManager.contentsOfDirectory` with URL resource values.
///
/// Unlike [ICloudFile] (populated from `NSMetadataQuery`), this model is
/// **immediately consistent** after local filesystem mutations (rename, delete,
/// copy). It provides download/upload status via URL resource values rather
/// than the Spotlight metadata index.
///
/// Use `ICloudStorage.listContents` to obtain these items.
///
/// ## When to use this vs [ICloudFile]
///
/// - **After your own mutations** (rename, delete, save): use `listContents`
///   for immediate consistency.
/// - **For remote sync monitoring** (changes from other devices): use
///   `gather()` which provides real-time notifications and download progress.
/// - **Initial discovery on a new device**: `gather()` discovers document
///   promises (files not yet placeholder'd locally); `listContents` only sees
///   files with a local representation.
class ContainerItem extends Equatable {
  /// Creates a [ContainerItem] from a platform channel map.
  ///
  /// Used internally by the method channel layer to deserialize native results.
  /// Expected keys: `relativePath` (String, required), `downloadStatus`
  /// (String?), `isDownloading` (bool?), `isUploaded` (bool?),
  /// `isUploading` (bool?), `hasUnresolvedConflicts` (bool?),
  /// `isDirectory` (bool?).
  ContainerItem.fromMap(Map<dynamic, dynamic> map)
      : relativePath = _requireRelativePath(map),
        downloadStatus = _mapDownloadStatus(
          map['downloadStatus'] as String?,
        ),
        isDownloading = (map['isDownloading'] as bool?) ?? false,
        isUploaded = (map['isUploaded'] as bool?) ?? false,
        isUploading = (map['isUploading'] as bool?) ?? false,
        hasUnresolvedConflicts =
            (map['hasUnresolvedConflicts'] as bool?) ?? false,
        isDirectory = (map['isDirectory'] as bool?) ?? false;

  /// File path relative to the iCloud container root, regardless of which
  /// subdirectory was passed as `relativePath` to `listContents`.
  final String relativePath;

  /// Download status from `URLUbiquitousItemDownloadingStatus`.
  ///
  /// Possible values are [DownloadStatus.notDownloaded],
  /// [DownloadStatus.downloaded], or [DownloadStatus.current].
  /// Null when the platform does not provide it (e.g. the file is not in
  /// a ubiquity container).
  final DownloadStatus? downloadStatus;

  /// Whether the system is actively downloading this item.
  final bool isDownloading;

  /// Whether this item has been uploaded to iCloud.
  final bool isUploaded;

  /// Whether the system is actively uploading this item.
  final bool isUploading;

  /// Whether this item has unresolved version conflicts.
  final bool hasUnresolvedConflicts;

  /// Whether this entry represents a directory.
  final bool isDirectory;

  /// Whether the item has local content available.
  ///
  /// Returns `true` when [downloadStatus] is [DownloadStatus.downloaded] or
  /// [DownloadStatus.current].
  bool get isDownloaded =>
      downloadStatus == DownloadStatus.downloaded ||
      downloadStatus == DownloadStatus.current;

  @override
  List<Object?> get props => [
        relativePath,
        downloadStatus,
        isDownloading,
        isUploaded,
        isUploading,
        hasUnresolvedConflicts,
        isDirectory,
      ];

  static String _requireRelativePath(Map<dynamic, dynamic> map) {
    final value = map['relativePath'];
    if (value is String) return value;
    throw InvalidArgumentException(
      'relativePath is required and must be a String '
      '(got: ${value.runtimeType})',
    );
  }

  static DownloadStatus? _mapDownloadStatus(String? key) {
    if (key == null) return null;
    return switch (key) {
      'notDownloaded' => DownloadStatus.notDownloaded,
      'downloaded' => DownloadStatus.downloaded,
      'current' => DownloadStatus.current,
      _ => null,
    };
  }
}
