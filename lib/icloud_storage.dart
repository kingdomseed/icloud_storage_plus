import 'dart:typed_data';

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
  ///
  /// When [onUpdate] is provided, the update stream stays active until the
  /// subscription is canceled. Callers should dispose listeners when done.
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

  /// Copy a local file into the iCloud container (copy-in).
  ///
  /// [localPath] is the absolute path to a local file to copy.
  /// [cloudRelativePath] is the path within the iCloud container.
  /// Use 'Documents/' prefix for Files app visibility.
  ///
  /// This does not keep the local file in sync. After the copy completes,
  /// iCloud uploads the container file automatically in the background.
  ///
  /// Trailing slashes are rejected here because transfers are file-centric and
  /// coordinated through UIDocument/NSDocument (directories are not supported).
  ///
  /// If [onProgress] is provided, attach a listener immediately inside the
  /// callback. Progress streams are listener-driven (not buffered), so delaying
  /// `listen()` may miss early progress events.
  static Future<void> uploadFile({
    required String containerId,
    required String localPath,
    required String cloudRelativePath,
    StreamHandler<ICloudTransferProgress>? onProgress,
  }) async {
    if (localPath.trim().isEmpty) {
      throw InvalidArgumentException('invalid localPath: $localPath');
    }

    // Transfers are file-centric (UIDocument/NSDocument). A trailing slash
    // indicates a directory path and would be ambiguous or fail natively.
    if (cloudRelativePath.endsWith('/')) {
      throw InvalidArgumentException(
        'invalid cloudRelativePath: $cloudRelativePath',
      );
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

  /// Download a file from iCloud, then copy it out to a local path.
  ///
  /// [cloudRelativePath] is the path within the iCloud container.
  /// [localPath] is the absolute destination path to write a local copy.
  ///
  /// This is not in-place access. Use [readInPlace] for coordinated reads
  /// inside the container.
  ///
  /// Trailing slashes are rejected here because transfers are file-centric and
  /// coordinated through UIDocument/NSDocument (directories are not supported).
  ///
  /// If [onProgress] is provided, attach a listener immediately inside the
  /// callback. Progress streams are listener-driven (not buffered), so delaying
  /// `listen()` may miss early progress events.
  static Future<void> downloadFile({
    required String containerId,
    required String cloudRelativePath,
    required String localPath,
    StreamHandler<ICloudTransferProgress>? onProgress,
  }) async {
    if (localPath.trim().isEmpty) {
      throw InvalidArgumentException('invalid localPath: $localPath');
    }

    // Transfers are file-centric (UIDocument/NSDocument). A trailing slash
    // indicates a directory path and would be ambiguous or fail natively.
    if (cloudRelativePath.endsWith('/')) {
      throw InvalidArgumentException(
        'invalid cloudRelativePath: $cloudRelativePath',
      );
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

  /// Read a file in place from the iCloud container using coordinated access.
  ///
  /// [relativePath] is the path within the iCloud container.
  ///
  /// Trailing slashes are rejected here because reads are file-centric and
  /// coordinated through UIDocument/NSDocument.
  ///
  /// Coordinated access loads the full contents into memory. Text is decoded
  /// as UTF-8; use [readInPlaceBytes] for binary formats.
  ///
  /// [idleTimeouts] configures the idle watchdog for downloads (defaults to
  /// 60s, 90s, 180s).
  /// [retryBackoff] configures the retry delay between attempts (exponential
  /// backoff by default).
  ///
  /// Returns the file contents as a String.
  ///
  /// Throws on file-not-found and other failures.
  /// Note: the return type is nullable to match the platform interface, but
  /// the native implementations only return `null` if a platform explicitly
  /// chooses to.
  static Future<String?> readInPlace({
    required String containerId,
    required String relativePath,
    List<Duration>? idleTimeouts,
    List<Duration>? retryBackoff,
  }) async {
    // Reads are file-centric; reject directory paths.
    if (relativePath.endsWith('/')) {
      throw InvalidArgumentException('invalid relativePath: $relativePath');
    }

    if (relativePath.trim().isEmpty) {
      throw InvalidArgumentException('invalid relativePath: $relativePath');
    }

    if (!_validateRelativePath(relativePath)) {
      throw InvalidArgumentException('invalid relativePath: $relativePath');
    }

    return ICloudStoragePlatform.instance.readInPlace(
      containerId: containerId,
      relativePath: relativePath,
      idleTimeouts: idleTimeouts,
      retryBackoff: retryBackoff,
    );
  }

  /// Read a file in place as bytes from the iCloud container using coordinated
  /// access.
  ///
  /// [relativePath] is the path within the iCloud container.
  ///
  /// Trailing slashes are rejected here because reads are file-centric and
  /// coordinated through UIDocument/NSDocument.
  ///
  /// Coordinated access loads the full contents into memory. Use for small
  /// files.
  ///
  /// [idleTimeouts] configures the idle watchdog for downloads (defaults to
  /// 60s, 90s, 180s).
  /// [retryBackoff] configures the retry delay between attempts (exponential
  /// backoff by default).
  ///
  /// Returns the file contents as bytes.
  ///
  /// Throws on file-not-found and other failures.
  static Future<Uint8List?> readInPlaceBytes({
    required String containerId,
    required String relativePath,
    List<Duration>? idleTimeouts,
    List<Duration>? retryBackoff,
  }) async {
    if (relativePath.endsWith('/')) {
      throw InvalidArgumentException('invalid relativePath: $relativePath');
    }

    if (relativePath.trim().isEmpty) {
      throw InvalidArgumentException('invalid relativePath: $relativePath');
    }

    if (!_validateRelativePath(relativePath)) {
      throw InvalidArgumentException('invalid relativePath: $relativePath');
    }

    return ICloudStoragePlatform.instance.readInPlaceBytes(
      containerId: containerId,
      relativePath: relativePath,
      idleTimeouts: idleTimeouts,
      retryBackoff: retryBackoff,
    );
  }

  /// Write a file in place inside the iCloud container using coordinated
  /// access.
  ///
  /// [relativePath] is the path within the iCloud container.
  /// [contents] is the full contents to write.
  ///
  /// Trailing slashes are rejected here because writes are file-centric and
  /// coordinated through UIDocument/NSDocument.
  ///
  /// Coordinated access writes the full contents as a single operation. Use
  /// for small text/JSON files.
  static Future<void> writeInPlace({
    required String containerId,
    required String relativePath,
    required String contents,
  }) async {
    // Writes are file-centric; reject directory paths.
    if (relativePath.endsWith('/')) {
      throw InvalidArgumentException('invalid relativePath: $relativePath');
    }

    if (relativePath.trim().isEmpty) {
      throw InvalidArgumentException('invalid relativePath: $relativePath');
    }

    if (!_validateRelativePath(relativePath)) {
      throw InvalidArgumentException('invalid relativePath: $relativePath');
    }

    await ICloudStoragePlatform.instance.writeInPlace(
      containerId: containerId,
      relativePath: relativePath,
      contents: contents,
    );
  }

  /// Write a file in place as bytes inside the iCloud container using
  /// coordinated access.
  ///
  /// [relativePath] is the path within the iCloud container.
  /// [contents] is the full contents to write.
  ///
  /// Trailing slashes are rejected here because writes are file-centric and
  /// coordinated through UIDocument/NSDocument.
  ///
  /// Coordinated access writes the full contents as a single operation. Use
  /// for small files.
  static Future<void> writeInPlaceBytes({
    required String containerId,
    required String relativePath,
    required Uint8List contents,
  }) async {
    if (relativePath.endsWith('/')) {
      throw InvalidArgumentException('invalid relativePath: $relativePath');
    }

    if (relativePath.trim().isEmpty) {
      throw InvalidArgumentException('invalid relativePath: $relativePath');
    }

    if (!_validateRelativePath(relativePath)) {
      throw InvalidArgumentException('invalid relativePath: $relativePath');
    }

    await ICloudStoragePlatform.instance.writeInPlaceBytes(
      containerId: containerId,
      relativePath: relativePath,
      contents: contents,
    );
  }

  /// Delete a file from the iCloud container.
  ///
  /// Trailing slashes are allowed here because directory paths can include
  /// them in metadata and FileManager operations handle directories.
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
  ///
  /// Trailing slashes are allowed for directory paths (from metadata), but both
  /// paths must resolve to valid filesystem entries.
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
  ///
  /// Trailing slashes are allowed in [relativePath] for directory entries and
  /// are normalized before deriving the new path.
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

    final normalizedPath = relativePath.endsWith('/')
        ? relativePath.substring(0, relativePath.length - 1)
        : relativePath;

    final lastSlash = normalizedPath.lastIndexOf('/');
    final directory =
        lastSlash == -1 ? '' : normalizedPath.substring(0, lastSlash + 1);

    await move(
      containerId: containerId,
      fromRelativePath: relativePath,
      toRelativePath: '$directory$newName',
    );
  }

  /// Copy a file within the iCloud container.
  ///
  /// Trailing slashes are allowed for directory paths (from metadata), but both
  /// paths must resolve to valid filesystem entries.
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
  ///
  /// Trailing slashes are allowed for directory paths returned by metadata.
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
  ///
  /// Trailing slashes are allowed for directory paths returned by metadata.
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
  ///
  /// Trailing slashes are allowed for directory paths returned by metadata.
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

    if (fileOrDirNames.length > 1 && fileOrDirNames.last.isEmpty) {
      fileOrDirNames.removeLast();
    }

    return fileOrDirNames.every(_validateFileName);
  }

  /// Validate a single file or directory name.
  static bool _validateFileName(String name) => !(name.isEmpty ||
      name.length > 255 ||
      RegExp(r'([:/]+)|(^[.].*$)').hasMatch(name));
}
