# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [3.0.0] - Unreleased

This repository is currently tracking the upcoming `3.0.0` release. There are a number of breaking changes below.

### BREAKING CHANGES

#### Streaming-Only File Path API
All byte-based APIs have been removed in favor of file-path methods.
This aligns with Apple’s URL/stream tier for large files and avoids platform
channel memory spikes.

**Removed:** `upload()`, `download()`, and related byte/JSON/document helpers.

**New:** `uploadFile()` and `downloadFile()` using local paths plus
`cloudRelativePath`.

**Migration:**
1. Write data to a local file in Dart.
2. Call `uploadFile(localPath, cloudRelativePath)`.
3. To read, call `downloadFile(cloudRelativePath, localPath)` and read the
   local file in Dart.

#### ICloudFile Nullable Fields
Some `ICloudFile` metadata fields are now nullable and may return `null` in
specific scenarios (directories, undownloaded iCloud files, missing timestamps,
and local-only items).

**Migration:** Check for null before use and choose appropriate fallbacks.

#### New Required Field: isDirectory
`ICloudFile` now includes `isDirectory: bool` to distinguish files vs
directories.

**Migration:** Filter directories explicitly if your code expects only files.

#### Directory Detection Behavior
`exists()`, `documentExists()`, and `getMetadata()` now return `true` / non-null
results for directories. In version 2.x these methods returned `false` / `null`
for directories.

#### Import Path Requirements
Plugin internal imports and the example/test app now use package-qualified
paths.

**Before:**
```dart
import 'models/icloud_file.dart';
```

**After:**
```dart
import 'package:icloud_storage_plus/models/icloud_file.dart';
```

#### Platform Requirements Updated
Minimum deployment targets have been updated to match Flutter 3.10+
requirements:

- **iOS**: minimum version increased from iOS 9.0 to iOS 13.0
- **macOS**: minimum version increased from macOS 10.11 to macOS 10.15

#### Internal Channel Name Change
The native method channel name has been renamed from `icloud_storage` to
`icloud_storage_plus` to match the package name.

#### Linting Package Change

#### gather() Now Returns GatherResult
`gather()` now returns a `GatherResult` containing `files` and
`invalidEntries` rather than a raw list, so malformed metadata is visible to
callers.

**Migration:**
```dart
final result = await ICloudStorage.gather(...);
final files = result.files;

if (result.invalidEntries.isNotEmpty) {
  // Optional: log or surface skipped metadata to aid debugging.
  debugPrint(
    'Skipped ${result.invalidEntries.length} invalid metadata entries.',
  );
}
```
Dependency changed from `flutter_lints` to `very_good_analysis`.

### Added

- Directory support via `ICloudFile.isDirectory`.
- Error code `E_PLUGIN_INTERNAL` for unexpected Dart-side stream errors.
- Error code `E_INVALID_EVENT` for invalid event types from native layer.
- `PlatformExceptionCode` constants for all error codes (`argumentError`,
  `readError`, `canceled`, `pluginInternal`, `invalidEvent`) to replace
  hardcoded string literals.
- Warning log when an unknown download status key is encountered.
- `GatherResult.invalidEntries` to surface malformed metadata entries.
- Removed `E_TIMEOUT` from public error codes.

### Changed

- Updated iOS/macOS podspec metadata (name, version, summary, description,
  homepage, author) to match the package.
- Native implementation and metadata extraction updated to support the new API
  surface (file-path transfers + richer metadata).
- Structural operations (`delete`, `move`, `copy`, `documentExists`,
  `getDocumentMetadata`) now use file URLs with coordinated FileManager access
  instead of metadata queries.
- `documentExists` uses `FileManager.fileExists` and returns true for iCloud
  placeholder entries once container metadata syncs (even if bytes are not
  downloaded).
- Documentation clarifies that `gather()` update streams deliver the full list,
  `uploadFile`/`downloadFile` reject directory paths, and `downloadStatus` may
  be null for unknown platform statuses.

### Fixed

- Resource leak in `gather()` where NSMetadataQuery observers were registered
  before verifying event channel handler exists. On E_NO_HANDLER early return,
  observers would remain registered. Now the handler check occurs before
  observer registration.
- Serialization bug in `getDocumentMetadata()` where `downloadStatus` was
  passed as a non-serializable Swift enum struct instead of extracting its
  `.rawValue` string, causing the field to be null or unserializable on the
  Dart side.
- Dart relative-path validation now accepts trailing slashes so directory
  metadata from `gather()` or `getMetadata()` can be used directly in
  operations like `delete()`, `move()`, `rename()`, etc. Previously, directory
  paths like `Documents/folder/` would fail Dart validation when reused.
- Transfer progress streams are now listener-driven; attach immediately to
  avoid missing early progress updates.
- Transfer progress stream failures are surfaced as `ICloudTransferProgress`
  error events (not stream `onError`) and terminal events close the stream.
- Documented progress stream error-as-data behavior in code comments.
- `uploadFile()` / `downloadFile()` now reject `cloudRelativePath` values that
  end with `/` (directory-style paths). Directory operations still accept
  trailing slashes when appropriate.
- macOS streaming writes now use `.saveOperation` for existing files to avoid
  unintended “Save As” behavior.
- Method channel null handling when platform methods return null.
- Stream mapping and event handling correctness.
- Removed metadata query timeouts from structural operations.

### Migration Guide (2.x -> 3.0.0)

1. Replace byte-based reads/writes with local files + `uploadFile()` /
   `downloadFile()`.
2. Update imports to package-qualified paths.
3. Add null checks for `ICloudFile` fields and handle directories via
   `isDirectory`.
4. If you use transfer progress, attach a listener immediately inside
  `onProgress` (streams are listener-driven and may miss early events).
5. Run `flutter analyze` to address any `very_good_analysis` lint findings.

---

## [2.x.x] - Previous Releases

See git history for changelog of releases before 3.0.0.
