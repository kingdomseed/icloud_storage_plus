# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### BREAKING CHANGES

#### Platform Requirements Updated
Minimum deployment targets have been updated to match Flutter 3.38+ requirements:

- **iOS**: Minimum version increased from iOS 9.0 to iOS 13.0
- **macOS**: Minimum version increased from macOS 10.11 to macOS 10.15

**Migration:** Users must:
1. Run `flutter clean && flutter pub get`
2. Run `pod install` in iOS and macOS directories
3. May need `pod cache clean --all` if experiencing pod resolution issues

#### Internal Channel Name Change
The native method channel name has been renamed from `icloud_storage` to `icloud_storage_plus` to match the package name. Pod module names have also been updated accordingly.

**Impact:** This is transparent to users - no code changes required in your application. The public Dart API (`import 'package:icloud_storage_plus/icloud_storage.dart'`) remains unchanged. The plugin will automatically use the new channel names after running `flutter clean` and reinstalling pods.

## [3.0.0] - 2026-01-23

### BREAKING CHANGES

#### ICloudFile Nullable Fields
Four fields in `ICloudFile` are now nullable and will return `null` in specific scenarios:

- `sizeInBytes: int?` - Returns `null` for directories and undownloaded iCloud files
- `creationDate: DateTime?` - Returns `null` when file metadata lacks creation timestamp
- `contentChangeDate: DateTime?` - Returns `null` when file metadata lacks modification timestamp
- `downloadStatus: DownloadStatus?` - Returns `null` for local-only files outside iCloud

**Migration:** Check for null before use. Choose fallbacks based on your logic:
```dart
// Size: Use 0 for missing sizes, or skip size-dependent operations
final size = file.sizeInBytes ?? 0;

// Dates: Use epoch time or handle absence explicitly
final created = file.creationDate ?? DateTime.fromMillisecondsSinceEpoch(0);

// Download status: Handle offline/local files
if (file.downloadStatus != null) {
  // Process iCloud sync status
}
```

#### New Required Field: isDirectory
`ICloudFile` now includes `isDirectory: bool`. Version 2.x returned `false` from `exists()` for directories. Version 3.0 returns `true` and sets `isDirectory` appropriately.

**Migration:** Filter directories explicitly if your code expects only files:
```dart
final metadata = await ICloudStorage.getMetadata(...);
if (metadata != null && !metadata.isDirectory) {
  // Process file
}
```

#### Import Path Requirements
Plugin internal imports and the example/test app now use package-qualified paths. Application code should already use package-qualified imports.

**Before:**
```dart
import 'models/icloud_file.dart';
import 'models/exceptions.dart';
```

**After:**
```dart
import 'package:icloud_storage_plus/models/icloud_file.dart';
import 'package:icloud_storage_plus/models/exceptions.dart';
```

This change affects:
- Application code importing plugin classes
- Example application files
- Test files

#### Directory Detection Behavior
`exists()`, `documentExists()`, and `getMetadata()` now return `true` / non-null results for directories. In version 2.x, these methods returned `false` / `null` for directories.

**Migration:** Add explicit directory filtering when needed:
```dart
final metadata = await ICloudStorage.getMetadata(
  containerId: containerId,
  relativePath: 'path/to/item',
);
if (metadata != null && !metadata.isDirectory) {
  // Only process files
  final size = metadata.sizeInBytes ?? 0;
}
```

#### Linting Package Change
Dependency changed from `flutter_lints` to `very_good_analysis`. Run `flutter analyze` after upgrading to identify lint violations that must be fixed.

### Added

#### Document-Based File Operations
New methods using UIDocument/NSDocument prevent NSCocoaErrorDomain Code=257 permission errors:

- `readDocument()` - Read file contents with automatic download
- `writeDocument()` - Write files with automatic conflict resolution
- `readJsonDocument()` - Read and parse JSON in one operation
- `writeJsonDocument()` - Encode and write JSON directly
- `updateDocument()` - Atomic read-modify-write operation
- `updateJsonDocument()` - Atomic update for JSON documents
- `downloadAndRead()` - Combined download and read with progress callbacks

Example with error handling:
```dart
try {
  final data = await ICloudStorage.readJsonDocument(
    containerId: 'iCloud.com.example.app',
    relativePath: 'Documents/settings.json',
  );
  // Process data
} on PlatformException catch (e) {
  if (e.code == 'fileNotFound') {
    // Handle missing file
  } else {
    // Handle other errors
  }
}
```

#### Directory Support
- `ICloudFile.isDirectory` field indicates item type
- Metadata operations support files and directories
- Directory entries include available metadata from iCloud

#### API Documentation
- "Recommended API Hierarchy" categorizes methods by use case
- PRIMARY methods (90% of use cases): `readDocument()`, `writeDocument()`, `documentExists()`
- COMPATIBILITY methods (10% of use cases): `downloadAndRead()` for progress monitoring
- ADVANCED methods: `download()`, `upload()`, `gather()` for explicit control

### Changed

#### Native Implementation
- iOS and macOS code uses UIDocument/NSDocument for file coordination
- Metadata extraction uses NSMetadataQuery with targeted predicates and best-effort attribute mapping (some fields may be null if iCloud does not provide them)
- Directory handling detects and reports type correctly
- Import paths updated across main plugin, example app, and test files

#### Code Quality
- Applied `very_good_analysis` lint rules
- Improved type annotations and null safety
- Consistent code formatting
- Extended inline documentation with comprehensive docstrings in Swift files and doc comments in Dart files

### Fixed

- Method channel null handling: Fixed crashes when platform methods return null
- Stream mapping: Corrected event handling for all event types
- Import paths: Updated to package-qualified paths consistently
- File coordination: UIDocument/NSDocument prevents permission errors (NSCocoaErrorDomain Code=257)
- Metadata extraction: Canonical download status constants from Apple are passed through; unknown values map to null
- Type safety: Fixed type casting in method channel communication

### Migration Guide

#### Update ICloudFile Usage

```dart
// Version 2.x code (compile errors in 3.0.0)
final metadata = await ICloudStorage.getMetadata(...);
final size = metadata.sizeInBytes;  // Error: now nullable
final created = metadata.creationDate;  // Error: now nullable

// Version 3.0.0 code
final metadata = await ICloudStorage.getMetadata(...);
if (metadata != null) {
  // Handle nulls with appropriate fallbacks
  final size = metadata.sizeInBytes ?? 0;
  final created = metadata.creationDate ?? DateTime.fromMillisecondsSinceEpoch(0);

  // Handle directories explicitly
  if (metadata.isDirectory) {
    print('Directory: ${metadata.relativePath}');
  } else {
    print('File: ${metadata.relativePath}, size: $size');
  }
}
```

#### Replace Manual File Reading

```dart
// Version 2.x approach (permission errors possible)
await ICloudStorage.download(
  containerId: containerId,
  relativePath: 'Documents/file.json',
);
final containerPath = await ICloudStorage.getContainerPath(
  containerId: containerId,
);
final file = File('$containerPath/Documents/file.json');
final contents = await file.readAsString();  // Risk: NSCocoaErrorDomain Code=257

// Version 3.0.0 approach (safe)
try {
  final data = await ICloudStorage.readJsonDocument(
    containerId: containerId,
    relativePath: 'Documents/file.json',
  );
  // Process data
} on PlatformException catch (e) {
  if (e.code == 'fileNotFound') {
    // Handle missing file
  }
}
```

#### Update Import Statements

```dart
// Version 2.x imports (errors in 3.0.0)
import 'models/icloud_file.dart';

// Version 3.0.0 imports (required)
import 'package:icloud_storage_plus/models/icloud_file.dart';
```

#### Handle Directories

```dart
// Version 2.x: exists() returned false for directories
final exists = await ICloudStorage.exists(
  containerId: containerId,
  relativePath: 'Documents/folder',
);
// exists == false (even if folder exists)

// Version 3.0.0: exists() returns true for directories
final metadata = await ICloudStorage.getMetadata(
  containerId: containerId,
  relativePath: 'Documents/folder',
);
if (metadata != null) {
  if (metadata.isDirectory) {
    print('Directory exists');
  } else {
    print('File exists');
  }
}
```

### Dependencies

- `very_good_analysis: ^10.0.0` (previously `flutter_lints: ^6.0.0`)
- Minimum Dart SDK: `>=2.18.2 <3.0.0`
- Minimum Flutter: `>=2.5.0`

### Upgrade Steps

1. Update `pubspec.yaml`: `icloud_storage_plus: ^3.0.0`
2. Run `dart pub get`
3. Update imports to package-qualified paths
4. Add null checks for `ICloudFile` fields: `sizeInBytes`, `creationDate`, `contentChangeDate`, `downloadStatus`
5. Handle directories explicitly using `isDirectory` field
6. Migrate to `readDocument`/`writeDocument` for safer file operations
7. Run `flutter analyze` to identify `very_good_analysis` violations

### Support

- Issues: https://github.com/kingdomseed/icloud_storage_plus/issues
- Documentation: README.md

---

## [2.x.x] - Previous Releases

See git history for changelog of releases before 3.0.0.

[Unreleased]: https://github.com/kingdomseed/icloud_storage_plus/compare/v3.0.0...HEAD
[3.0.0]: https://github.com/kingdomseed/icloud_storage_plus/releases/tag/v3.0.0
