import 'dart:async';
import 'icloud_storage_platform_interface.dart';
import 'models/exceptions.dart';
import 'models/icloud_file.dart';
export 'models/exceptions.dart';
export 'models/icloud_file.dart';

/// The main class for the plugin. Contains all the API's needed for listing,
/// uploading, downloading and deleting files.
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
  /// Check if iCloud is available and user is logged in
  ///
  /// Returns true if iCloud is available and user is logged in, false otherwise
  static Future<bool> icloudAvailable() async {
    return await ICloudStoragePlatform.instance.icloudAvailable();
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
    return await ICloudStoragePlatform.instance.gather(
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
  /// ```
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
    return await ICloudStoragePlatform.instance.getContainerPath(
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
  /// upload. It takes a Stream<double> as input, which is the percentage of
  /// the data being uploaded.
  ///
  /// The returned future completes without waiting for the file to be uploaded
  /// to iCloud
  static Future<void> upload({
    required String containerId,
    required String filePath,
    String? destinationRelativePath,
    StreamHandler<double>? onProgress,
  }) async {
    if (filePath.trim().isEmpty) {
      throw InvalidArgumentException('invalid filePath: $filePath');
    }

    final destination = destinationRelativePath ?? filePath.split('/').last;

    if (!_validateRelativePath(destination)) {
      throw InvalidArgumentException(
          'invalid destination relative path: $destination');
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
  /// **Note**: This method downloads files in-place within the iCloud container.
  /// The file remains at its original location and is made available locally.
  /// To access the downloaded file, use getContainerPath() and append the
  /// relativePath.
  ///
  /// [onProgress] is an optional callback to track the progress of the
  /// download. It takes a Stream<double> as input, which is the percentage of
  /// the data being downloaded.
  ///
  /// Returns true if the download was initiated successfully, false otherwise.
  /// The returned future completes without waiting for the file to be
  /// downloaded
  static Future<bool> download({
    required String containerId,
    required String relativePath,
    StreamHandler<double>? onProgress,
  }) async {
    if (!_validateRelativePath(relativePath)) {
      throw InvalidArgumentException('invalid relativePath: $relativePath');
    }

    return await ICloudStoragePlatform.instance.download(
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
          'invalid relativePath: (from) $fromRelativePath');
    }

    if (!_validateRelativePath(toRelativePath)) {
      throw InvalidArgumentException(
          'invalid relativePath: (to) $toRelativePath');
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

    return fileOrDirNames.every((name) => _validateFileName(name));
  }

  /// Private method to validate file name. It shall not contain '/' or ':', and
  /// it shall not start with '.', and the length shall be greater than 0 and
  /// less than 255.
  static bool _validateFileName(String name) => !(name.isEmpty ||
      name.length > 255 ||
      RegExp(r"([:/]+)|(^[.].*$)").hasMatch(name));
}
