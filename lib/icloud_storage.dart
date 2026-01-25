import 'package:icloud_storage_plus/icloud_storage_platform_interface.dart';
import 'package:icloud_storage_plus/models/exceptions.dart';
import 'package:icloud_storage_plus/models/gather_result.dart';
import 'package:icloud_storage_plus/models/icloud_file.dart';
import 'package:icloud_storage_plus/models/transfer_progress.dart';

export 'models/exceptions.dart';
export 'models/gather_result.dart';
export 'models/icloud_file.dart';
export 'models/transfer_progress.dart';

/// The main class for the plugin. Provides streaming, file-path-only access
/// to iCloud containers using Apple’s document APIs.
///
/// ## Overriding Goals
/// 1. Sync files to iCloud so users can retrieve them on other devices.
/// 2. Expose files in the Files app in iCloud Drive (when enabled by the app).
///
/// ## Streaming-Only API
/// This API never moves raw bytes over the platform channel. All operations
/// reference local file paths to avoid memory spikes and IPC limits.
///
/// ## Document IO Tier Rationale
/// The plugin uses the URL-tier document APIs (`UIDocument`/`NSDocument`) so
/// reads and writes are coordinated with iCloud and can stream efficiently
/// for large files.
///
/// ## iCloud Storage Locations
/// - **Container Root**: Syncs across devices but not visible in Files app.
/// - **Documents/**: Visible in Files app.
/// - **Data/**: App-private; should not sync.
class ICloudStorage {
  /// The directory name for files that should be visible in the Files app.
  static const String documentsDirectory = 'Documents';

  /// The directory name for temporary files that should not sync to iCloud.
  static const String dataDirectory = 'Data';

  /// Check if iCloud is available and user is logged in.
  static Future<bool> icloudAvailable() async {
    return ICloudStoragePlatform.instance.icloudAvailable();
  }

  /// Get all file metadata from the iCloud container.
  static Future<GatherResult> gather({
    required String containerId,
    StreamHandler<GatherResult>? onUpdate,
  }) async {
    return ICloudStoragePlatform.instance.gather(
      containerId: containerId,
      onUpdate: onUpdate,
    );
  }

  /// Get the absolute path to the iCloud container.
  static Future<String?> getContainerPath({
    required String containerId,
  }) async {
    return ICloudStoragePlatform.instance.getContainerPath(
      containerId: containerId,
    );
  }

  /// Upload a local file to iCloud using streaming IO.
  ///
  /// [localPath] is the absolute path to a local file.
  /// [cloudRelativePath] is the path within the iCloud container.
  /// Use 'Documents/' prefix for Files app visibility.
  static Future<void> uploadFile({
    required String containerId,
    required String localPath,
    required String cloudRelativePath,
    StreamHandler<ICloudTransferProgress>? onProgress,
  }) async {
    if (localPath.trim().isEmpty) {
      throw InvalidArgumentException('invalid localPath: $localPath');
    }

    if (!_validateRelativePath(cloudRelativePath)) {
      throw InvalidArgumentException(
        'invalid cloudRelativePath: $cloudRelativePath',
      );
    }

    await ICloudStoragePlatform.instance.uploadFile(
      containerId: containerId,
      localPath: localPath,
      cloudRelativePath: cloudRelativePath,
      onProgress: onProgress,
    );
  }

  /// Download a file from iCloud to a local path using streaming IO.
  ///
  /// [cloudRelativePath] is the path within the iCloud container.
  /// [localPath] is the absolute destination path to write.
  static Future<void> downloadFile({
    required String containerId,
    required String cloudRelativePath,
    required String localPath,
    StreamHandler<ICloudTransferProgress>? onProgress,
  }) async {
    if (localPath.trim().isEmpty) {
      throw InvalidArgumentException('invalid localPath: $localPath');
    }

    if (!_validateRelativePath(cloudRelativePath)) {
      throw InvalidArgumentException(
        'invalid cloudRelativePath: $cloudRelativePath',
      );
    }

    await ICloudStoragePlatform.instance.downloadFile(
      containerId: containerId,
      cloudRelativePath: cloudRelativePath,
      localPath: localPath,
      onProgress: onProgress,
    );
  }

  /// Delete a file from the iCloud container.
  static Future<void> delete({
    required String containerId,
    required String relativePath,
  }) async {
    if (!_validateRelativePath(relativePath)) {
      throw InvalidArgumentException('invalid relativePath: $relativePath');
    }

    await ICloudStoragePlatform.instance.delete(
      containerId: containerId,
      relativePath: relativePath,
    );
  }

  /// Move a file within the iCloud container.
  static Future<void> move({
    required String containerId,
    required String fromRelativePath,
    required String toRelativePath,
  }) async {
    if (!_validateRelativePath(fromRelativePath)) {
      throw InvalidArgumentException(
        'invalid relativePath: (from) $fromRelativePath',
      );
    }

    if (!_validateRelativePath(toRelativePath)) {
      throw InvalidArgumentException(
        'invalid relativePath: (to) $toRelativePath',
      );
    }

    await ICloudStoragePlatform.instance.move(
      containerId: containerId,
      fromRelativePath: fromRelativePath,
      toRelativePath: toRelativePath,
    );
  }

  /// Rename a file in the iCloud container.
  static Future<void> rename({
    required String containerId,
    required String relativePath,
    required String newName,
  }) async {
    if (!_validateRelativePath(relativePath)) {
      throw InvalidArgumentException('invalid relativePath: $relativePath');
    }

    if (!_validateFileName(newName)) {
      throw InvalidArgumentException('invalid newName: $newName');
    }

    final lastSlash = relativePath.lastIndexOf('/');
    final directory =
        lastSlash == -1 ? '' : relativePath.substring(0, lastSlash + 1);

    await move(
      containerId: containerId,
      fromRelativePath: relativePath,
      toRelativePath: '$directory$newName',
    );
  }

  /// Copy a file within the iCloud container.
  static Future<void> copy({
    required String containerId,
    required String fromRelativePath,
    required String toRelativePath,
  }) async {
    if (!_validateRelativePath(fromRelativePath)) {
      throw InvalidArgumentException(
        'invalid relativePath: (from) $fromRelativePath',
      );
    }

    if (!_validateRelativePath(toRelativePath)) {
      throw InvalidArgumentException(
        'invalid relativePath: (to) $toRelativePath',
      );
    }

    await ICloudStoragePlatform.instance.copy(
      containerId: containerId,
      fromRelativePath: fromRelativePath,
      toRelativePath: toRelativePath,
    );
  }

  /// Check if a file or directory exists without downloading.
  static Future<bool> documentExists({
    required String containerId,
    required String relativePath,
  }) async {
    if (!_validateRelativePath(relativePath)) {
      throw InvalidArgumentException('invalid relativePath: $relativePath');
    }

    return ICloudStoragePlatform.instance.documentExists(
      containerId: containerId,
      relativePath: relativePath,
    );
  }

  /// Get metadata for a file or directory without downloading content.
  static Future<ICloudFile?> getMetadata({
    required String containerId,
    required String relativePath,
  }) async {
    if (!_validateRelativePath(relativePath)) {
      throw InvalidArgumentException('invalid relativePath: $relativePath');
    }
    final metadata = await ICloudStoragePlatform.instance.getDocumentMetadata(
      containerId: containerId,
      relativePath: relativePath,
    );
    if (metadata == null) return null;
    return ICloudFile.fromMap(metadata);
  }

  /// Get raw metadata map for a file or directory.
  static Future<Map<String, dynamic>?> getDocumentMetadata({
    required String containerId,
    required String relativePath,
  }) async {
    if (!_validateRelativePath(relativePath)) {
      throw InvalidArgumentException('invalid relativePath: $relativePath');
    }

    return ICloudStoragePlatform.instance.getDocumentMetadata(
      containerId: containerId,
      relativePath: relativePath,
    );
  }

  /// Validate relative path segments.
  static bool _validateRelativePath(String path) {
    final fileOrDirNames = path.split('/');
    if (fileOrDirNames.isEmpty) return false;

    return fileOrDirNames.every(_validateFileName);
  }

  /// Validate a single file or directory name.
  static bool _validateFileName(String name) => !(name.isEmpty ||
      name.length > 255 ||
      RegExp(r'([:/]+)|(^[.].*$)').hasMatch(name));
}
