/// Metadata for an iCloud file or directory.
class ICloudFile {
  /// Constructor to create the object from the map passed from platform code
  ICloudFile.fromMap(Map<dynamic, dynamic> map)
      : relativePath = map['relativePath'] as String,
        isDirectory = (map['isDirectory'] as bool?) ?? false,
        sizeInBytes = _mapToInt(map['sizeInBytes']),
        creationDate = _mapToDateTime(map['creationDate']),
        contentChangeDate = _mapToDateTime(map['contentChangeDate']),
        isDownloading = (map['isDownloading'] as bool?) ?? false,
        downloadStatus =
            _mapToDownloadStatusFromNSKeys(map['downloadStatus'] as String?),
        isUploading = (map['isUploading'] as bool?) ?? false,
        isUploaded = (map['isUploaded'] as bool?) ?? false,
        hasUnresolvedConflicts =
            (map['hasUnresolvedConflicts'] as bool?) ?? false;

  /// File path relative to the iCloud container
  final String relativePath;

  /// True when the item represents a directory.
  final bool isDirectory;

  /// Corresponding to NSMetadataItemFSSizeKey.
  /// Nullable when the platform does not provide it.
  final int? sizeInBytes;

  /// Corresponding to NSMetadataItemFSCreationDateKey.
  /// Nullable when the platform does not provide it.
  final DateTime? creationDate;

  /// Corresponding to NSMetadataItemFSContentChangeDateKey.
  /// Nullable when the platform does not provide it.
  final DateTime? contentChangeDate;

  /// Corresponding to NSMetadataUbiquitousItemIsDownloadingKey
  final bool isDownloading;

  /// Corresponding to NSMetadataUbiquitousItemDownloadingStatusKey.
  /// Nullable when the platform does not provide it.
  final DownloadStatus? downloadStatus;

  /// Corresponding to NSMetadataUbiquitousItemIsUploadingKey
  final bool isUploading;

  /// Corresponding to NSMetadataUbiquitousItemIsUploadedKey
  final bool isUploaded;

  /// Corresponding to NSMetadataUbiquitousItemHasUnresolvedConflictsKey
  final bool hasUnresolvedConflicts;

  /// Map native download status keys to DownloadStatus enum
  static DownloadStatus? _mapToDownloadStatusFromNSKeys(String? key) {
    if (key == null) return null;
    switch (key) {
      case 'NSMetadataUbiquitousItemDownloadingStatusNotDownloaded':
      case 'notDownloaded':
        return DownloadStatus.notDownloaded;
      case 'NSMetadataUbiquitousItemDownloadingStatusDownloaded':
      case 'downloaded':
        return DownloadStatus.downloaded;
      case 'NSMetadataUbiquitousItemDownloadingStatusCurrent':
      case 'current':
        return DownloadStatus.current;
      default:
        return null;
    }
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
}

/// Download status of the File
enum DownloadStatus {
  /// Corresponding to NSMetadataUbiquitousItemDownloadingStatusNotDownloaded
  /// This item has not been downloaded yet.
  notDownloaded,

  /// Corresponding to NSMetadataUbiquitousItemDownloadingStatusDownloaded
  /// There is a local version of this item available.
  /// The most current version will get downloaded as soon as possible.
  downloaded,

  /// Corresponding to NSMetadataUbiquitousItemDownloadingStatusCurrent
  /// There is a local version of this item and it is the most up-to-date
  /// version known to this device.
  current,
}
