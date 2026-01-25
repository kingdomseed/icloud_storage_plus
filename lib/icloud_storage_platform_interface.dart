import 'package:icloud_storage_plus/icloud_storage_method_channel.dart';
import 'package:icloud_storage_plus/models/gather_result.dart';
import 'package:icloud_storage_plus/models/transfer_progress.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// A function-type alias that receives a stream of values.
typedef StreamHandler<T> = void Function(Stream<T>);

/// Platform interface for iCloud storage implementations.
abstract class ICloudStoragePlatform extends PlatformInterface {
  /// Constructs a ICloudStoragePlatform.
  ICloudStoragePlatform() : super(token: _token);

  static final Object _token = Object();

  static ICloudStoragePlatform _instance = MethodChannelICloudStorage();

  /// The default instance of [ICloudStoragePlatform] to use.
  ///
  /// Defaults to [MethodChannelICloudStorage].
  static ICloudStoragePlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [ICloudStoragePlatform] when
  /// they register themselves.
  static set instance(ICloudStoragePlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Check if iCloud is available and user is logged in
  ///
  /// Returns true if iCloud is available and user is logged in, false otherwise
  Future<bool> icloudAvailable() async {
    throw UnimplementedError('icloudAvailable() has not been implemented.');
  }

  /// Gather all the files' meta data from iCloud container.
  ///
  /// [containerId] is the iCloud Container Id.
  ///
  /// [onUpdate] is an optional paramater can be used as a call back every time
  /// when the list of files are updated. It won't be triggered when the
  /// function initially returns the list of files.
  ///
  /// The function returns a [GatherResult] containing parsed files and any
  /// invalid entries.
  Future<GatherResult> gather({
    required String containerId,
    StreamHandler<GatherResult>? onUpdate,
  }) async {
    throw UnimplementedError('gather() has not been implemented.');
  }

  /// Get the local path to the iCloud container root, if available.
  ///
  /// Returns null when iCloud is unavailable for the given container.
  Future<String?> getContainerPath({
    required String containerId,
  }) async {
    throw UnimplementedError('getContainerPath() has not been implemented.');
  }

  /// Upload a local file to iCloud from a local path.
  ///
  /// [containerId] is the iCloud Container Id.
  ///
  /// [localPath] is the full path of the local file.
  ///
  /// [cloudRelativePath] is the relative path of the file in iCloud.
  ///
  /// [onProgress] is an optional callback to track the progress of the
  /// upload. It takes a Stream&lt;double&gt; as input, which is the percentage
  /// of the data being uploaded.
  ///
  /// The returned future completes without waiting for the file to be uploaded
  /// to iCloud.
  Future<void> uploadFile({
    required String containerId,
    required String localPath,
    required String cloudRelativePath,
    StreamHandler<ICloudTransferProgress>? onProgress,
  }) async {
    throw UnimplementedError('uploadFile() has not been implemented.');
  }

  /// Download a file from iCloud to a local path.
  ///
  /// [containerId] is the iCloud Container Id.
  ///
  /// [cloudRelativePath] is the relative path of the file on iCloud.

  /// [localPath] is the full path where the file should be written locally.
  ///
  /// [onProgress] is an optional callback to track the progress of the
  /// download. It takes a Stream&lt;double&gt; as input, which is the
  /// percentage of the data being downloaded.
  ///
  /// The returned future completes without waiting for the file to be
  /// downloaded.
  Future<void> downloadFile({
    required String containerId,
    required String cloudRelativePath,
    required String localPath,
    StreamHandler<ICloudTransferProgress>? onProgress,
  }) async {
    throw UnimplementedError('downloadFile() has not been implemented.');
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
  Future<void> delete({
    required String containerId,
    required String relativePath,
  }) async {
    throw UnimplementedError('delete() has not been implemented.');
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
  Future<void> move({
    required String containerId,
    required String fromRelativePath,
    required String toRelativePath,
  }) async {
    throw UnimplementedError('move() has not been implemented.');
  }

  /// Copy a file from one location to another in the iCloud container
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
  /// PlatformException with code PlatformExceptionCode.fileNotFound will be
  /// thrown if the source file does not exist
  Future<void> copy({
    required String containerId,
    required String fromRelativePath,
    required String toRelativePath,
  }) async {
    throw UnimplementedError('copy() has not been implemented.');
  }

  /// Check if a file or directory exists without downloading
  ///
  /// [containerId] is the iCloud Container Id.
  ///
  /// [relativePath] is the relative path of the item on iCloud
  ///
  /// Returns true if the file or directory exists, false otherwise
  Future<bool> documentExists({
    required String containerId,
    required String relativePath,
  }) async {
    throw UnimplementedError('documentExists() has not been implemented.');
  }

  /// Get file or directory metadata without downloading content
  ///
  /// [containerId] is the iCloud Container Id.
  ///
  /// [relativePath] is the relative path of the item on iCloud
  ///
  /// Returns metadata about the item, or null if it doesn't exist.
  /// The map should include `isDirectory` to distinguish directories.
  Future<Map<String, dynamic>?> getDocumentMetadata({
    required String containerId,
    required String relativePath,
  }) async {
    throw UnimplementedError('getDocumentMetadata() has not been implemented.');
  }
}
