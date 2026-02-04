# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
