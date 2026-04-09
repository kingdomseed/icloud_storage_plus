# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.0.0] - 2026-04-09

Breaking release that hardens the Dart API contract around known-path metadata,
typed request/response failures, and coordinated overwrite behavior on iOS and
macOS.

### BREAKING CHANGES
- Removed the old typed `getMetadata()` API in favor of `getItemMetadata()`.
- Structured native request/response failures now map to typed
  `ICloudOperationException` subclasses across the Dart API.
- `getDocumentMetadata()` remains the raw metadata escape hatch and preserves
  raw `PlatformException` behavior.

### Added
- `ICloudItemMetadata` as the typed known-path metadata model returned by
  `getItemMetadata()`.
- Typed request/response exception mapping for structured native payloads,
  including container access, not found, conflict, download-in-progress, item
  not downloaded, and timeout cases.

### Changed
- README, example code, and public Dart doc comments now document the `2.0.0`
  contract explicitly, including the separation between `ICloudItemMetadata`,
  `ICloudFile`, and raw `getDocumentMetadata()` payloads.
- Transfer-progress streams continue to emit `PlatformException`-based error
  payloads in `2.0.0`; only request/response APIs use the new typed exception
  mapping.
- iOS and macOS existing-destination writes and copies continue to use
  coordinated atomic replacement, with release-facing docs updated to match the
  final API behavior.

### Fixed
- iOS and macOS existing-file `writeDocument`, `writeInPlace`, and
  `writeInPlaceBytes` now stage replacement content outside the ubiquity
  container and replace the destination through coordinated atomic replacement.
- iOS and macOS `copy()` now keep existing destinations inside coordinated
  atomic replacement flows instead of removing the destination before copying.

### Changed
- Darwin coordinated replacement logic now has standalone Foundation-level Swift
  test seams on iOS and macOS, with helper XCTest coverage for overwrite and
  existing-destination copy replacement behavior.
- Repository documentation now points to the hosted DeepWiki site instead of
  keeping a checked-in export under `doc/deepwiki/`.

## [1.2.2] - 2026-03-30

### Fixed
- iOS and macOS download-wait completion no longer uses a local
  `DispatchQueue`. The short-lived queue could be deallocated before
  `UIDocument.openWithCompletionHandler:` finished retaining it (via the
  deprecated `dispatch_get_current_queue` call in UIKit internals), causing
  an `_os_object_retain` crash with "API MISUSE: Resurrection of an object".
  Completion is now dispatched on `DispatchQueue.main`, which is consistent
  with UIDocument's own completion-handler contract.

## [1.2.1] - 2026-03-27

### Changed
- iOS method-channel filesystem work now uses Flutter's background task queue
  when that queue is available. Container lookup, iCloud path preflight, and
  `UIDocument` initialization stay coordinated but no longer block the UI
  thread during in-place reads and writes on supported runtimes.

### Fixed
- iOS and macOS metadata query update handling no longer depends on
  `DispatchQueue.main.sync` for event-channel state checks, reducing deadlock
  risk when iCloud change notifications arrive while other native work is in
  flight.
- Event stream state on iOS and macOS is now synchronized for cross-queue
  access, which avoids races between cancellation, progress delivery, and
  metadata updates.
- iOS download watchdog startup now schedules its initial timeout on the main
  run loop even when the method channel handler starts on a background task
  queue, preventing stalled in-place reads from hanging indefinitely.
- iOS and macOS download completion/cancellation paths now use a synchronized
  single-fire completion gate, preventing double `FlutterResult` delivery when
  cancellation races with native completion.

## [1.2.0] - 2026-03-09

### Added
- `listContents()` API for immediately-consistent container listings using
  `FileManager.contentsOfDirectory` with URL resource values. Unlike `gather()`
  (which reads the Spotlight metadata index), `listContents()` reflects
  filesystem mutations (rename, delete, copy) immediately.
- `ContainerItem` model with `relativePath`, `downloadStatus`, `isDownloading`,
  `isUploaded`, `isUploading`, `hasUnresolvedConflicts`, `isDirectory`, and a
  convenience `isDownloaded` getter.
- iCloud placeholder file resolution: both iOS (`.originalName.icloud` stubs)
  and macOS Sonoma+ (APFS dataless files) are handled transparently —
  `listContents` returns the real filename and accurate download status.
- Hidden file filtering: `listContents` suppresses system files (`.DS_Store`,
  `.Trash`, etc.) by filtering entries whose resolved name starts with `.`.

### Changed
- `ICloudFile` dartdoc now cross-references `ContainerItem` and explains the
  eventual-consistency distinction.
- `GatherResult` dartdoc expanded to describe `invalidEntries` purpose.
- Fixed typo in `InvalidArgumentException` doc comment ("ued" → "used").
- README expanded with `listContents` documentation, `gather` vs `listContents`
  comparison table, iCloud placeholder files section, and `ContainerItem` model
  reference.

## [1.1.1] - 2026-02-14

### Fixed
- GitHub Actions automated publishing trigger for tags like `1.2.3` (no `v`
  prefix).
- Remove example ephemeral LLDB helper files that were causing `dart pub publish`
  validation warnings.

## [1.1.0] - 2026-02-13

### Added
- Swift Package Manager support for iOS and macOS (Flutter 3.24+ opt-in).

### Changed
- Native iOS/macOS sources are now packaged under `Sources/icloud_storage_plus/`
  for SwiftPM compatibility (CocoaPods support remains via the podspecs).
- Example apps now use Flutter's SwiftPM plugin integration (no CocoaPods
  `Podfile`s in the example projects).

## [1.0.1] - 2026-02-11

### Fixed
- Avoid reading `NSMetadataItem` off the query thread by running `NSMetadataQuery`
  on a dedicated operation queue and disabling updates during snapshot reads.
- Ensure `relativePath` generation is path-boundary-aware (avoid prefix-collision
  edge cases).

### Changed
- Clarify benchmark documentation around `standardizedFileURL` behavior.

## [1.0.0] - 2026-02-04

Major API update with path-based transfers for large files, coordinated in-place
read/write APIs for small files, and a documentation overhaul.

### BREAKING CHANGES

#### Transfer API: file-path based for large files
Byte-based transfer APIs have been removed in favor of file-path methods. Large
file content is no longer sent over platform channels.

**Removed:** `upload()`, `download()`, and related byte/JSON helpers.

**New:** `uploadFile()` and `downloadFile()` using local paths plus
`cloudRelativePath`.

**Migration:**
1. Write data to a local file in Dart.
2. Call `uploadFile(localPath, cloudRelativePath)`.
3. To read, call `downloadFile(cloudRelativePath, localPath)` and read the
   local file in Dart.

#### gather() now returns GatherResult
`gather()` now returns a `GatherResult` containing:
- `files`: parsed `ICloudFile` entries
- `invalidEntries`: entries that could not be parsed (helps debug malformed
  metadata payloads)

#### ICloudFile metadata shape and nullability
`ICloudFile` now:
- includes `isDirectory: bool` (directories are returned by metadata APIs)
- may return `null` for some fields when iCloud metadata is unavailable or the
  entry represents a directory (for example `sizeInBytes`)

#### Directory detection behavior
`documentExists()` and `getMetadata()` return true/non-null for both files and
directories. Filter directories explicitly if your code expects only files.

#### Platform requirements updated
Minimum deployment targets match Flutter 3.10+:
- **iOS**: 13.0
- **macOS**: 10.15

#### Internal channel name change
The native method channel name is `icloud_storage_plus` (was `icloud_storage`).

#### Linting package change
Dev linting moved to `very_good_analysis`.

### Added

- File-path transfer methods:
  - `uploadFile()` (local → iCloud container)
  - `downloadFile()` (iCloud container → local)
- Coordinated in-place access for small files:
  - `readInPlace()` / `writeInPlace()` (String, UTF-8)
  - `readInPlaceBytes()` / `writeInPlaceBytes()` (Uint8List)
  - Optional `idleTimeouts` + `retryBackoff` to control download watchdog/retry
    behavior; stalled downloads surface `E_TIMEOUT`.
- Convenience `rename()` API (implemented in Dart via `move()`).
- Additional iCloud sync-state fields on `ICloudFile`:
  - `downloadStatus`, `isDownloading`
  - `isUploading`, `isUploaded`
  - `hasUnresolvedConflicts`
- New public error code constants:
  - `PlatformExceptionCode.initializationError` (`E_INIT`)
  - `PlatformExceptionCode.timeout` (`E_TIMEOUT`)
- Documentation overhaul:
  - README updated to match the real API surface and semantics
  - DeepWiki badge added to the README
  - DeepWiki exported into `doc/` for GitHub navigation
  - Added `scripts/fix_deepwiki_links.py` to keep exported docs linkable
  - Old `doc/` research/plans removed (replaced by short notes under
    `doc/notes/`)

### Changed

- Structural operations (`delete`, `move`, `copy`) use coordinated file URL
  operations (NSFileCoordinator) rather than relying on metadata queries.
- Existence and metadata (`documentExists`, `getDocumentMetadata`) use direct
  filesystem checks (FileManager / URL resource values) rather than metadata
  queries.
- `documentExists()` is a filesystem existence check; it does not force a
  download. Use `gather()` for a remote-aware view of container contents.
- Transfer progress streams deliver failures as `ICloudTransferProgressType.error`
  data events (not stream `onError`).

### Fixed

- `gather()` now verifies the event channel handler exists before registering
  query observers (prevents leaked observers on early-return).
- `getDocumentMetadata()` now serializes download status keys as strings
  (`.rawValue`) for correct transport to Dart.
- Dart relative-path validation accepts trailing slashes so directory paths from
  metadata can be reused directly in operations like `delete()`, `move()`,
  `rename()`, etc.
- `uploadFile()` / `downloadFile()` reject `cloudRelativePath` values that end
  with `/` (directory-style paths).
- macOS streaming writes use `.saveOperation` for existing files to avoid
  unintended “Save As” behavior.

### Migration Guide (2.x → 1.0.0)

1. Replace byte-based reads/writes with local files + `uploadFile()` /
   `downloadFile()`.
2. For small JSON/text stored in iCloud Drive, consider switching to in-place
   access (`readInPlace`/`writeInPlace`) for “transparent sync”.
3. Update call sites to handle directories via `ICloudFile.isDirectory` and
   add null checks for optional metadata fields.
4. If you use transfer progress, attach a listener immediately inside
   `onProgress` (streams are listener-driven and may miss early events).
5. Run `flutter analyze` to address any `very_good_analysis` lint findings.

---

## Previous Releases

For history prior to 1.0.0 (including the upstream lineage), see git history
and the upstream repository: https://github.com/deansyd/icloud_storage
