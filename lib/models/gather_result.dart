import 'package:icloud_storage_plus/models/icloud_file.dart';

/// Result of a gather operation, including malformed entries.
class GatherResult {
  /// Creates a gather result with parsed files and invalid entries.
  const GatherResult({
    required this.files,
    required this.invalidEntries,
  });

  /// Parsed, valid file metadata entries.
  final List<ICloudFile> files;

  /// Entries that could not be parsed into an [ICloudFile].
  final List<GatherInvalidEntry> invalidEntries;
}

/// Captures metadata entries that could not be parsed.
class GatherInvalidEntry {
  /// Creates a record of a metadata entry that failed to parse.
  const GatherInvalidEntry({
    required this.error,
    this.rawEntry,
    this.index,
  });

  /// Description of the parsing error.
  final String error;

  /// The raw entry returned by the platform (may be non-map).
  final Object? rawEntry;

  /// Index in the original platform list, when available.
  final int? index;
}
