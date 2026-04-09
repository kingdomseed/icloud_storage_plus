import 'package:logging/logging.dart';

final Logger _logger = Logger('DownloadStatus');

/// Download status of an iCloud item.
enum DownloadStatus {
  /// This item has not been downloaded yet.
  notDownloaded,

  /// There is a local version of this item available.
  downloaded,

  /// The local version is current on this device.
  current,
}

/// Parses normalized and Apple-native download status strings.
DownloadStatus? parseDownloadStatus(String? value) {
  if (value == null) return null;

  switch (value) {
    case 'notDownloaded':
    case 'NSMetadataUbiquitousItemDownloadingStatusNotDownloaded':
    case 'NSURLUbiquitousItemDownloadingStatusNotDownloaded':
      return DownloadStatus.notDownloaded;
    case 'downloaded':
    case 'NSMetadataUbiquitousItemDownloadingStatusDownloaded':
    case 'NSURLUbiquitousItemDownloadingStatusDownloaded':
      return DownloadStatus.downloaded;
    case 'current':
    case 'NSMetadataUbiquitousItemDownloadingStatusCurrent':
    case 'NSURLUbiquitousItemDownloadingStatusCurrent':
      return DownloadStatus.current;
    default:
      _logger.warning('Unknown download status from native metadata: $value');
      return null;
  }
}
