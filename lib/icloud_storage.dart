import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:icloud_storage_plus/icloud_storage_platform_interface.dart';
import 'package:icloud_storage_plus/models/exceptions.dart';
import 'package:icloud_storage_plus/models/icloud_file.dart';
import 'package:icloud_storage_plus/models/transfer_progress.dart';
export 'models/exceptions.dart';
export 'models/icloud_file.dart';
export 'models/transfer_progress.dart';

/// The main class for the plugin. Contains all the API's needed for listing,
/// uploading, downloading and deleting files.
///
/// ## 🏆 Recommended API Hierarchy (Use in this order)
///
/// **PRIMARY (90% of use cases - most efficient):**
/// - `readDocument()` / `readJsonDocument()` - Smart file reading with auto-download
/// - `writeDocument()` / `writeJsonDocument()` - Safe writing with conflict resolution
/// - `documentExists()` - Efficient file/directory existence checking
///
/// **COMPATIBILITY (10% of use cases - when you need progress monitoring):**
/// - `downloadAndRead()` - Combined download+read with progress callbacks
///
/// **ADVANCED (Power users - explicit control):**
/// - `download()` - Explicit downloading for caching/batch operations
/// - `upload()` - File uploading with progress monitoring
/// - `gather()` - File listing and metadata
///
/// ## Understanding iCloud Storage Locations
///
/// Files in an iCloud container can be stored in different locations:
///
/// - **Container Root** (default): Files sync across devices but are NOT
///   visible in the Files app. Use for app settings, databases, etc.
///   Example: `await upload(relativePath: 'settings.json')`
///
/// - **Documents Directory**: Files are visible in the Files app and can be
///   managed by users. Use for user documents, exports, etc.
///   Example: `await upload(relativePath: 'Documents/report.pdf')`
///
/// - **Data Directory**: For temporary or cache files that shouldn't sync.
///   Example: `await upload(relativePath: 'Data/cache.tmp')`
class ICloudStorage {
  /// The directory name for files that should be visible in the Files app.
  /// Files stored under this directory will appear in iCloud Drive and be
  /// accessible through the Files app.
  static const String documentsDirectory = 'Documents';

  /// The directory name for temporary files that should not sync to iCloud.
  /// Use this for cache files or temporary data.
  static const String dataDirectory = 'Data';

  /// Check if iCloud is available and user is logged in
  ///
  /// Returns true if iCloud is available and user is logged in, false otherwise
  static Future<bool> icloudAvailable() async {
    return ICloudStoragePlatform.instance.icloudAvailable();
  }

  /// Get all the files' meta data from iCloud container
  ///
  /// [containerId] is the iCloud Container Id.
  ///
  /// [onUpdate] is an optional paramater can be used as a callback when the
  /// list of files are updated. It won't be triggered when the function
  /// initially returns the list of files
  ///
  /// Returns a list of ALL files in the container, including:
  /// - Files in the root (app-private, not visible in Files app)
  /// - Files in Documents/ (visible in Files app)
  /// - Files in any subdirectories
  ///
  /// The relativePath in each ICloudFile will reflect the full path from
  /// the container root, e.g., "Documents/myfile.pdf" or "data/config.json"
  static Future<List<ICloudFile>> gather({
    required String containerId,
    StreamHandler<List<ICloudFile>>? onUpdate,
  }) async {
    return ICloudStoragePlatform.instance.gather(
      containerId: containerId,
      onUpdate: onUpdate,
    );
  }

  /// Get the absolute path to the iCloud container
  ///
  /// [containerId] is the iCloud Container Id.
  ///
  /// Returns the root path of the iCloud container, or null if unavailable.
  ///
  /// **Understanding the container structure**:
  /// ```md
  /// [returned path]/
  /// ├── Documents/     ← Files here are visible in Files app
  /// ├── Data/          ← App-private data
  /// └── [root files]   ← Files here sync but are NOT visible in Files app
  /// ```
  ///
  /// Example usage:
  /// ```dart
  /// final containerPath = await ICloudStorage.getContainerPath(
  ///   containerId: 'your.container.id',
  /// );
  /// if (containerPath != null) {
  ///   // For Files app visibility
  ///   final visibleFile = File('$containerPath/Documents/myfile.txt');
  ///
  ///   // For app-private storage
  ///   final privateFile = File('$containerPath/appdata.db');
  /// }
  /// ```
  static Future<String?> getContainerPath({
    required String containerId,
  }) async {
    return ICloudStoragePlatform.instance.getContainerPath(
      containerId: containerId,
    );
  }

  /// Initiate to upload a file to iCloud
  ///
  /// [containerId] is the iCloud Container Id.
  ///
  /// [filePath] is the full path of the local file
  ///
  /// [destinationRelativePath] is the relative path of the file you want to
  /// store in iCloud. If not specified, the name of the local file name is
  /// used.
  ///
  /// **Important**: Files are stored relative to the container root by default.
  /// - To make files visible in the Files app, prefix with 'Documents/'
  ///   Example: 'Documents/myfile.pdf'
  /// - For app-private files, use any other path or the root
  ///   Example: 'settings/config.json' or just 'data.db'
  ///
  /// [onProgress] is an optional callback to track the progress of the
  /// upload. It takes a Stream&lt;ICloudTransferProgress&gt; as input.
  ///
  /// The stream emits:
  /// - `ICloudTransferProgress.progress(percent)` progress updates
  /// - `ICloudTransferProgress.done()` once when the stream completes
  /// - `ICloudTransferProgress.error(exception)` if the upload fails
  ///
  /// The returned future completes without waiting for the file to be uploaded
  /// to iCloud
  static Future<void> upload({
    required String containerId,
    required String filePath,
    String? destinationRelativePath,
    StreamHandler<ICloudTransferProgress>? onProgress,
  }) async {
    if (filePath.trim().isEmpty) {
      throw InvalidArgumentException('invalid filePath: $filePath');
    }

    final destination = destinationRelativePath ?? filePath.split('/').last;

    if (!_validateRelativePath(destination)) {
      throw InvalidArgumentException(
        'invalid destination relative path: $destination',
      );
    }

    await ICloudStoragePlatform.instance.upload(
      containerId: containerId,
      filePath: filePath,
      destinationRelativePath: destination,
      onProgress: onProgress,
    );
  }

  /// Initiate to download a file from iCloud
  ///
  /// [containerId] is the iCloud Container Id.
  ///
  /// [relativePath] is the relative path of the file on iCloud, such as file1
  /// or folder/myfile2. For files in the Documents directory visible in Files
  /// app, include the Documents prefix: "Documents/myfile.pdf"
  ///
  /// **Note**: This method downloads files in-place within the iCloud
  /// container.
  /// The file remains at its original location and is made available locally.
  /// To access the downloaded file, use getContainerPath() and append the
  /// relativePath.
  ///
  /// **🚨 CRITICAL WARNING**: After download completes, do NOT read the file
  /// directly using standard file operations as this may cause
  /// NSCocoaErrorDomain
  /// Code=257 permission errors. Instead:
  /// - **RECOMMENDED**: Use `readDocument()` for efficient, safe file reading
  /// - Use `downloadAndRead()` for combined download+read operations
  /// - Or implement NSFileCoordinator/UIDocument/NSDocument manually
  ///
  /// **💡 TIP**: For most use cases, skip this method and use `readDocument()`
  /// directly - it's more efficient and handles downloading automatically.
  ///
  /// [onProgress] is an optional callback to track the progress of the
  /// download. It takes a Stream&lt;ICloudTransferProgress&gt; as input.
  ///
  /// The stream emits:
  /// - `ICloudTransferProgress.progress(percent)` progress updates
  /// - `ICloudTransferProgress.done()` once when the stream completes
  /// - `ICloudTransferProgress.error(exception)` if the download fails
  ///
  /// Returns true if the download was initiated successfully, false otherwise.
  /// The returned future completes without waiting for the file to be
  /// downloaded
  static Future<bool> download({
    required String containerId,
    required String relativePath,
    StreamHandler<ICloudTransferProgress>? onProgress,
  }) async {
    if (!_validateRelativePath(relativePath)) {
      throw InvalidArgumentException('invalid relativePath: $relativePath');
    }

    return ICloudStoragePlatform.instance.download(
      containerId: containerId,
      relativePath: relativePath,
      onProgress: onProgress,
    );
  }

  /// Download a file from iCloud and safely read its contents
  ///
  /// **COMPATIBILITY METHOD**: Consider using `readDocument()` instead for
  /// better performance and efficiency.
  ///
  /// This method combines download and reading to prevent permission errors
  /// that occur when trying to read iCloud files directly without proper
  /// coordination. However, it always performs a download operation even if
  /// the file is already available locally.
  ///
  /// **When to use this method**:
  /// - When you specifically need download progress monitoring
  /// - When migrating from unsafe download() + manual file reading patterns
  /// - For compatibility with existing code
  ///
  /// **Better alternative**: Use `readDocument()` which automatically handles
  /// downloading only when needed and is more efficient.
  ///
  /// [containerId] is the iCloud Container Id.
  ///
  /// [relativePath] is the relative path of the file on iCloud, such as file1
  /// or folder/myfile2. For files in the Documents directory visible in Files
  /// app, include the Documents prefix: "Documents/myfile.pdf"
  ///
  /// [onProgress] is an optional callback to track the progress of the
  /// download. It takes a Stream&lt;ICloudTransferProgress&gt; as input.
  ///
  /// Returns the file contents as Uint8List, or null if the file doesn't exist.
  ///
  /// Example:
  /// ```dart
  /// // ✅ BETTER: Use readDocument() for most cases
  /// final bytes = await ICloudStorage.readDocument(...);
  ///
  /// // ⚠️ COMPATIBILITY: Use this only if you need progress monitoring
  /// final bytes = await ICloudStorage.downloadAndRead(
  ///   containerId: 'iCloud.com.example.app',
  ///   relativePath: 'Documents/large-file.pdf',
  ///   onProgress: (stream) => stream.listen((progress) =>
  ///     print('Progress: ${(progress * 100).toStringAsFixed(1)}%')
  ///   ),
  /// );
  /// ```
  static Future<Uint8List?> downloadAndRead({
    required String containerId,
    required String relativePath,
    StreamHandler<ICloudTransferProgress>? onProgress,
  }) async {
    if (!_validateRelativePath(relativePath)) {
      throw InvalidArgumentException('invalid relativePath: $relativePath');
    }

    return ICloudStoragePlatform.instance.downloadAndRead(
      containerId: containerId,
      relativePath: relativePath,
      onProgress: onProgress,
    );
  }

  /// Delete a file from iCloud container directory, whether it is been
  /// downloaded or not
  ///
  /// [containerId] is the iCloud Container Id.
  ///
  /// [relativePath] is the relative path of the file on iCloud, such as file1
  /// or folder/file2
  ///
  /// PlatformException with code PlatformExceptionCode.fileNotFound will be
  /// thrown if the file does not exist
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

  /// Move a file from one location to another in the iCloud container
  ///
  /// [containerId] is the iCloud Container Id.
  ///
  /// [fromRelativePath] is the relative path of the file to be moved, such as
  /// folder1/file
  ///
  /// [toRelativePath] is the relative path to move to, such as folder2/file
  ///
  /// PlatformException with code PlatformExceptionCode.fileNotFound will be
  /// thrown if the file does not exist
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

  /// Rename a file in the iCloud container
  ///
  /// [containerId] is the iCloud Container Id.
  ///
  /// [relativePath] is the relative path of the file to be renamed, such as
  /// file1 or folder/file1
  ///
  /// [newName] is the name of the file to be renamed to. It is not a relative
  /// path.
  ///
  /// PlatformException with code PlatformExceptionCode.fileNotFound will be
  /// thrown if the file does not exist
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

    await move(
      containerId: containerId,
      fromRelativePath: relativePath,
      toRelativePath:
          relativePath.substring(0, relativePath.lastIndexOf('/') + 1) +
              newName,
    );
  }

  /// Private method to validate relative path; each part must be valid name
  static bool _validateRelativePath(String path) {
    final fileOrDirNames = path.split('/');
    if (fileOrDirNames.isEmpty) return false;

    return fileOrDirNames.every(_validateFileName);
  }

  /// Private method to validate file name. It shall not contain '/' or ':', and
  /// it shall not start with '.', and the length shall be greater than 0 and
  /// less than 255.
  static bool _validateFileName(String name) => !(name.isEmpty ||
      name.length > 255 ||
      RegExp(r'([:/]+)|(^[.].*$)').hasMatch(name));

  static String _stripDocumentsPrefix(String path) {
    const prefix = '$documentsDirectory/';
    if (path == documentsDirectory) return '';
    return path.startsWith(prefix) ? path.substring(prefix.length) : path;
  }

  /// Upload a file to the Documents directory (visible in Files app)
  ///
  /// This is a convenience method that automatically prefixes the destination
  /// path with 'Documents/' to ensure the file is visible in the Files app.
  ///
  /// [containerId] is the iCloud Container Id.
  ///
  /// [filePath] is the full path of the local file
  ///
  /// [destinationRelativePath] is the relative path within the Documents
  /// directory. If not specified, the local file name is used. If the path
  /// already starts with 'Documents/', the prefix is removed automatically.
  /// Example: 'reports/2023/report.pdf' becomes 'Documents/reports/2023/report.pdf'
  ///
  /// [onProgress] is an optional callback to track upload progress
  static Future<void> uploadToDocuments({
    required String containerId,
    required String filePath,
    String? destinationRelativePath,
    StreamHandler<ICloudTransferProgress>? onProgress,
  }) async {
    var destination = destinationRelativePath ?? filePath.split('/').last;
    destination = _stripDocumentsPrefix(destination);
    if (destination.isEmpty) {
      throw InvalidArgumentException(
        'invalid destination relative path: $destinationRelativePath',
      );
    }

    await upload(
      containerId: containerId,
      filePath: filePath,
      destinationRelativePath: '$documentsDirectory/$destination',
      onProgress: onProgress,
    );
  }

  /// Upload a file to app-private storage (not visible in Files app)
  ///
  /// This is a convenience method that makes it explicit the file will be
  /// stored in the app's private iCloud container, not visible to users
  /// in the Files app.
  ///
  /// [containerId] is the iCloud Container Id.
  ///
  /// [filePath] is the full path of the local file
  ///
  /// [destinationRelativePath] is the relative path within the container root.
  /// If not specified, the local file name is used.
  ///
  /// [onProgress] is an optional callback to track upload progress
  static Future<void> uploadPrivate({
    required String containerId,
    required String filePath,
    String? destinationRelativePath,
    StreamHandler<ICloudTransferProgress>? onProgress,
  }) async {
    // This is effectively the same as upload(), but the method name
    // makes the intent clear
    await upload(
      containerId: containerId,
      filePath: filePath,
      destinationRelativePath: destinationRelativePath,
      onProgress: onProgress,
    );
  }

  /// Download a file from the Documents directory (Files app visible location)
  ///
  /// This is a convenience method that automatically prefixes the path
  /// with 'Documents/' to download files from the Files app visible location.
  ///
  /// [containerId] is the iCloud Container Id.
  ///
  /// [relativePath] is the relative path within the Documents directory
  /// Example: 'report.pdf' becomes 'Documents/report.pdf'. If the path already
  /// starts with 'Documents/', the prefix is removed automatically.
  ///
  /// [onProgress] is an optional callback to track download progress
  static Future<bool> downloadFromDocuments({
    required String containerId,
    required String relativePath,
    StreamHandler<ICloudTransferProgress>? onProgress,
  }) async {
    final normalized = _stripDocumentsPrefix(relativePath);
    if (normalized.isEmpty) {
      throw InvalidArgumentException('invalid relativePath: $relativePath');
    }
    return download(
      containerId: containerId,
      relativePath: '$documentsDirectory/$normalized',
      onProgress: onProgress,
    );
  }

  /// Check if a file exists in iCloud without downloading it
  ///
  /// [containerId] is the iCloud Container Id.
  ///
  /// [relativePath] is the relative path of the item to check, such as file1
  /// or folder/file2 or Documents/myfile.pdf
  ///
  /// Returns true if the file or directory exists, false otherwise.
  ///
  /// This method uses iCloud metadata to detect remote-only items.
  static Future<bool> exists({
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

  /// Copy a file within the iCloud container
  ///
  /// [containerId] is the iCloud Container Id.
  ///
  /// [fromRelativePath] is the relative path of the source file
  ///
  /// [toRelativePath] is the relative path of the destination file
  ///
  /// The destination file will be overwritten if it exists.
  /// Parent directories will be created if needed.
  ///
  /// Throws PlatformException if the source file doesn't exist
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

  /// Get metadata for a specific file or directory without downloading it
  ///
  /// [containerId] is the iCloud Container Id.
  ///
  /// [relativePath] is the relative path of the item to get metadata for
  ///
  /// Returns the ICloudFile metadata if the item exists, null otherwise.
  ///
  /// The returned metadata includes `isDirectory` to distinguish file vs
  /// directory, and optional fields may be null if iCloud does not provide
  /// them for the given item.
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

  /// Read a document from iCloud safely
  ///
  /// **RECOMMENDED METHOD**: This is the preferred way to read iCloud files.
  ///
  /// This method uses UIDocument/NSDocument internally to ensure proper
  /// file coordination and prevent permission errors. It automatically
  /// handles downloading if the file exists in iCloud but isn't local yet.
  ///
  /// **Performance**: More efficient than download() + manual reading because:
  /// - No redundant downloads if file is already local
  /// - Automatic iCloud coordination via UIDocument/NSDocument
  /// - Single operation instead of download-then-read pattern
  ///
  /// [containerId] is the iCloud Container Id.
  ///
  /// [relativePath] is the relative path of the file on iCloud
  ///
  /// Returns null if the file doesn't exist.
  ///
  /// **Use this instead of**: download() followed by manual file reading
  ///
  /// Example:
  /// ```dart
  /// // ✅ RECOMMENDED: Simple, efficient, safe
  /// final bytes = await ICloudStorage.readDocument(
  ///   containerId: 'iCloud.com.example.app',
  ///   relativePath: 'Documents/settings.json',
  /// );
  /// if (bytes != null) {
  ///   final json = utf8.decode(bytes);
  ///   final settings = jsonDecode(json);
  /// }
  ///
  /// // ❌ AVOID: Manual pattern that can cause permission errors
  /// // await ICloudStorage.download(...);
  /// // final file = File('$containerPath/settings.json');
  /// // final content = await file.readAsString(); // Can fail!
  /// ```
  static Future<Uint8List?> readDocument({
    required String containerId,
    required String relativePath,
  }) async {
    if (!_validateRelativePath(relativePath)) {
      throw InvalidArgumentException('invalid relativePath: $relativePath');
    }

    return ICloudStoragePlatform.instance.readDocument(
      containerId: containerId,
      relativePath: relativePath,
    );
  }

  /// Write a document to iCloud safely
  ///
  /// This method uses UIDocument/NSDocument internally to ensure proper
  /// file coordination, conflict resolution, and version tracking.
  ///
  /// [containerId] is the iCloud Container Id.
  ///
  /// [relativePath] is the relative path of the file on iCloud
  ///
  /// [data] is the content to write to the file
  ///
  /// Creates the file if it doesn't exist, updates if it does.
  ///
  /// Example:
  /// ```dart
  /// final data = {'setting1': true, 'setting2': 42};
  /// final json = jsonEncode(data);
  /// final bytes = utf8.encode(json);
  ///
  /// await ICloudStorage.writeDocument(
  ///   containerId: 'iCloud.com.example.app',
  ///   relativePath: 'Documents/settings.json',
  ///   data: bytes,
  /// );
  /// ```
  static Future<void> writeDocument({
    required String containerId,
    required String relativePath,
    required Uint8List data,
  }) async {
    if (!_validateRelativePath(relativePath)) {
      throw InvalidArgumentException('invalid relativePath: $relativePath');
    }

    await ICloudStoragePlatform.instance.writeDocument(
      containerId: containerId,
      relativePath: relativePath,
      data: data,
    );
  }

  /// Check if a file or directory exists using native iCloud metadata APIs
  ///
  /// This method is more efficient than [exists] as it uses native APIs
  /// without gathering all files.
  ///
  /// [containerId] is the iCloud Container Id.
  ///
  /// [relativePath] is the relative path of the item on iCloud
  ///
  /// Returns true if the file or directory exists, false otherwise
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

  /// Get file or directory metadata without downloading content
  ///
  /// [containerId] is the iCloud Container Id.
  ///
  /// [relativePath] is the relative path of the item on iCloud
  ///
  /// Returns metadata about the item including:
  /// - relativePath: Path relative to container
  /// - isDirectory: Whether this item is a directory
  /// - sizeInBytes: File or directory size (if provided by iCloud)
  /// - creationDate: Creation timestamp (if provided)
  /// - contentChangeDate: Content change timestamp (if provided)
  /// - downloadStatus: iCloud download status (if provided)
  /// - isDownloading/isUploading/isUploaded/hasUnresolvedConflicts
  ///
  /// Returns null if the item doesn't exist
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

  /// Read a JSON document from iCloud
  ///
  /// Convenience method that reads a document and parses it as JSON.
  ///
  /// [containerId] is the iCloud Container Id.
  ///
  /// [relativePath] is the relative path of the JSON file on iCloud
  ///
  /// Returns null if the file doesn't exist.
  /// Throws [InvalidArgumentException] if the file content is not valid JSON.
  ///
  /// Example:
  /// ```dart
  /// final settings = await ICloudStorage.readJsonDocument(
  ///   containerId: 'iCloud.com.example.app',
  ///   relativePath: 'Documents/settings.json',
  /// );
  /// if (settings != null) {
  ///   print('Dark mode: ${settings['darkMode']}');
  /// }
  /// ```
  static Future<Map<String, dynamic>?> readJsonDocument({
    required String containerId,
    required String relativePath,
  }) async {
    final bytes = await readDocument(
      containerId: containerId,
      relativePath: relativePath,
    );

    if (bytes == null) return null;

    try {
      final json = utf8.decode(bytes);
      return jsonDecode(json) as Map<String, dynamic>;
    } catch (e) {
      throw InvalidArgumentException('Invalid JSON in document: $e');
    }
  }

  /// Write a JSON document to iCloud
  ///
  /// Convenience method that encodes a Map as JSON and writes it to iCloud.
  ///
  /// [containerId] is the iCloud Container Id.
  ///
  /// [relativePath] is the relative path of the JSON file on iCloud
  ///
  /// [data] is the Map to encode as JSON
  ///
  /// Example:
  /// ```dart
  /// await ICloudStorage.writeJsonDocument(
  ///   containerId: 'iCloud.com.example.app',
  ///   relativePath: 'Documents/settings.json',
  ///   data: {
  ///     'darkMode': true,
  ///     'language': 'en',
  ///     'version': 2,
  ///   },
  /// );
  /// ```
  static Future<void> writeJsonDocument({
    required String containerId,
    required String relativePath,
    required Map<String, dynamic> data,
  }) async {
    final json = jsonEncode(data);
    final bytes = Uint8List.fromList(utf8.encode(json));

    await writeDocument(
      containerId: containerId,
      relativePath: relativePath,
      data: bytes,
    );
  }

  /// Update a document with automatic conflict resolution
  ///
  /// This method safely handles concurrent updates by:
  /// 1. Reading the current document
  /// 2. Applying your changes
  /// 3. Writing back with conflict detection
  ///
  /// If the document doesn't exist, it will be created with the
  /// result of calling updater with an empty Uint8List.
  ///
  /// [containerId] is the iCloud Container Id.
  ///
  /// [relativePath] is the relative path of the file on iCloud
  ///
  /// [updater] is a function that receives the current data and returns
  /// the updated data
  ///
  /// Example:
  /// ```dart
  /// await ICloudStorage.updateDocument(
  ///   containerId: 'iCloud.com.example.app',
  ///   relativePath: 'Documents/counter.txt',
  ///   updater: (currentData) {
  ///     final current = currentData.isEmpty
  ///         ? 0
  ///         : int.parse(utf8.decode(currentData));
  ///     return utf8.encode((current + 1).toString());
  ///   },
  /// );
  /// ```
  static Future<void> updateDocument({
    required String containerId,
    required String relativePath,
    required Uint8List Function(Uint8List currentData) updater,
  }) async {
    // Read current content (or empty if doesn't exist)
    final currentData = await readDocument(
          containerId: containerId,
          relativePath: relativePath,
        ) ??
        Uint8List(0);

    // Apply changes
    final newData = updater(currentData);

    // Write back
    await writeDocument(
      containerId: containerId,
      relativePath: relativePath,
      data: newData,
    );
  }
}
