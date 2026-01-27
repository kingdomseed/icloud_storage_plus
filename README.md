# iCloud Storage Plus

[![Pub Version](https://img.shields.io/pub/v/icloud_storage_plus)](https://pub.dev/packages/icloud_storage_plus)
[![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20macOS-blue)]()
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![style: very good analysis](https://img.shields.io/badge/style-very_good_analysis-B22C89.svg)](https://pub.dev/packages/very_good_analysis)
[![shorebird ci](https://api.shorebird.dev/api/v1/github/kingdomseed/icloud_storage_plus/badge.svg)](https://console.shorebird.dev/ci)

Flutter plugin for iCloud document storage with automatic conflict resolution and Files app integration.

## Features

- Document-based operations with automatic download and conflict resolution
- Files app integration for user-visible documents
- Directory detection and metadata extraction
- Progress callbacks for long-running operations
- Coordinated file access prevents "file locked" errors during iCloud sync

## Installation

```bash
flutter pub add icloud_storage_plus
```

## Requirements

- Dart SDK: `>=3.0.0 <4.0.0`
- Flutter: `>=3.10.0`

## Usage

This plugin operates on your app’s iCloud container (files you write under that
container). 

### Basic Example

```dart
import 'dart:io';
import 'package:icloud_storage_plus/icloud_storage.dart';

// Check iCloud availability
final available = await ICloudStorage.icloudAvailable();
if (!available) {
  // User is not signed into iCloud
  return;
}

// Prepare local file
final localPath = '${Directory.systemTemp.path}/notes.txt';
await File(localPath).writeAsString('My notes');

// Upload to iCloud (Files app visible)
await ICloudStorage.uploadFile(
  containerId: 'iCloud.com.yourapp.container',
  localPath: localPath,
  cloudRelativePath: 'Documents/notes.txt',
);

// Download from iCloud to a local path
final downloadPath = '${Directory.systemTemp.path}/notes-downloaded.txt';
await ICloudStorage.downloadFile(
  containerId: 'iCloud.com.yourapp.container',
  cloudRelativePath: 'Documents/notes.txt',
  localPath: downloadPath,
);

final content = await File(downloadPath).readAsString();
```

### File Operations

```dart
// Check if file exists
final exists = await ICloudStorage.documentExists(
  containerId: 'iCloud.com.yourapp.container',
  relativePath: 'Documents/notes.txt',
);

// Get file metadata
final metadata = await ICloudStorage.getMetadata(
  containerId: 'iCloud.com.yourapp.container',
  relativePath: 'Documents/notes.txt',
);

if (metadata != null && !metadata.isDirectory) {
  final size = metadata.sizeInBytes ?? 0;
  final modified = metadata.contentChangeDate;
}

// Delete file
await ICloudStorage.delete(
  containerId: 'iCloud.com.yourapp.container',
  relativePath: 'Documents/notes.txt',
);

// Move file
await ICloudStorage.move(
  containerId: 'iCloud.com.yourapp.container',
  fromRelativePath: 'Documents/draft.txt',
  toRelativePath: 'Documents/Archive/draft.txt',
);

// List all files
final result = await ICloudStorage.gather(
  containerId: 'iCloud.com.yourapp.container',
  onUpdate: (stream) {
    stream.listen((gatherResult) {
      final files = gatherResult.files;
      // Handle full file list updates
    });
  },
);
final files = result.files;
```

## Migration from 2.x

### Breaking Changes

#### 1. Nullable ICloudFile Fields

Four fields are now nullable:
- `sizeInBytes: int?` - null for directories and undownloaded files
- `creationDate: DateTime?` - null when metadata unavailable
- `contentChangeDate: DateTime?` - null when metadata unavailable
- `downloadStatus: DownloadStatus?` - null for local-only or unknown statuses

**Before (2.x):**
```dart
final metadata = await ICloudStorage.getMetadata(...);
final size = metadata.sizeInBytes;  // Always non-null
```

#### 2. gather() now returns GatherResult
`gather()` now returns a `GatherResult` with `files` and `invalidEntries`
instead of a raw list. This makes malformed metadata visible to callers.

**Before (2.x):**
```dart
final files = await ICloudStorage.gather(...);
```

**After (3.0):**
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

**After (3.0):**
```dart
final metadata = await ICloudStorage.getMetadata(...);
final size = metadata?.sizeInBytes ?? 0;  // Handle null
```

#### 2. Directory Detection

`documentExists()` and `getMetadata()` return true/non-null for directories.
Use `isDirectory` to distinguish files from directories.

**Before (2.x):**
```dart
// Directories returned false
final exists = await ICloudStorage.documentExists(...);
```

**After (3.0):**
```dart
final metadata = await ICloudStorage.getMetadata(...);
if (metadata != null && !metadata.isDirectory) {
  // Process file only
}
```

#### 3. Import Paths

Use package-qualified imports:
```dart
import 'package:icloud_storage_plus/models/icloud_file.dart';
```

### Recommended Migration

Replace manual file operations with streaming file-path methods:

**Before (2.x):**
```dart
await ICloudStorage.download(...);
final path = await ICloudStorage.getContainerPath(...);
final file = File('$path/Documents/file.json');
final contents = await file.readAsString();  // Can fail with permission errors
```

**After (3.0):**
```dart
final localPath = '${Directory.systemTemp.path}/file.json';
await ICloudStorage.downloadFile(
  containerId: 'iCloud.com.yourapp.container',
  cloudRelativePath: 'Documents/file.json',
  localPath: localPath,
);
final contents = await File(localPath).readAsString();
```

## Configuration

### 1. Apple Developer Setup

1. Create an App ID in Apple Developer portal
2. Create an iCloud Container ID (e.g., `iCloud.com.yourapp.container`)
3. Enable iCloud for your App ID and assign the container

### 2. Xcode Configuration

1. Open your project in Xcode
2. Select your target → Signing & Capabilities
3. Add iCloud capability
4. Enable "iCloud Documents"
5. Select your container

### 3. Files App Integration

To make files visible in the Files app, configure `Info.plist`:

```xml
<key>NSUbiquitousContainers</key>
<dict>
    <key>iCloud.com.yourapp.container</key>
    <dict>
        <key>NSUbiquitousContainerIsDocumentScopePublic</key>
        <true/>
        <key>NSUbiquitousContainerName</key>
        <string>YourAppName</string>
    </dict>
</dict>
```

Files must use the `Documents/` prefix to appear in Files app:
```dart
// Visible in Files app
cloudRelativePath: 'Documents/notes.txt'

// Hidden from Files app
cloudRelativePath: 'cache/temp.dat'
```
Paths outside `Documents/` still sync across devices but remain hidden from
the Files app.

**Note:** Your app’s folder won’t appear in Files/iCloud Drive until at least
one file has been written under `Documents/`.

## API Reference

### Streaming File Operations

These methods use file-path-only streaming with Apple’s UIDocument (iOS) and
NSDocument (macOS) for coordinated reads/writes. No bytes cross the platform
channel.

#### uploadFile
```dart
Future<void> uploadFile({
  required String containerId,
  required String localPath,
  required String cloudRelativePath,
  StreamHandler<ICloudTransferProgress>? onProgress,
})
```
Streams a local file into the iCloud container. Use `Documents/` in
`cloudRelativePath` to expose the file in Files app.

`cloudRelativePath` must refer to a file and must not end with `/`. Directory
paths with trailing slashes may appear in metadata and are accepted by
directory-oriented operations like `delete`, `move`, and `getMetadata`.
`uploadFile` rejects directory paths because it uses file-specific document
coordination APIs.

#### downloadFile
```dart
Future<void> downloadFile({
  required String containerId,
  required String cloudRelativePath,
  required String localPath,
  StreamHandler<ICloudTransferProgress>? onProgress,
})
```
Streams a file from iCloud into a local path.

`cloudRelativePath` must refer to a file and must not end with `/`.
`downloadFile` rejects directory paths because it uses file-specific document
coordination APIs.

Progress streams are broadcast and start when a listener attaches. For the most
consistent updates, start listening immediately in the `onProgress` callback.

Progress failures are delivered as `ICloudTransferProgressType.error` events
(not as stream `onError`). Treat `error` and `done` as terminal: the stream
emits the event and then closes. Unexpected progress event payload types are
surfaced as `E_INVALID_EVENT` and terminate the stream.

Existence checks use `FileManager.fileExists` on the container path rather than
metadata queries. iCloud creates local placeholder entries for remote files, so
`fileExists` returns true once the container metadata has synced, even if the
file’s bytes are not downloaded. This method does not force a download.

#### documentExists
```dart
Future<bool> documentExists({
  required String containerId,
  required String relativePath,
})
```
Checks if a file or directory exists. Returns true for both files and directories.

#### getMetadata
```dart
Future<ICloudFile?> getMetadata({
  required String containerId,
  required String relativePath,
})
```
Returns metadata for a file or directory. Use `isDirectory` field to distinguish between them.

#### getDocumentMetadata
```dart
Future<Map<String, dynamic>?> getDocumentMetadata({
  required String containerId,
  required String relativePath,
})
```
Returns raw metadata map (same fields as `ICloudFile`). Most users should
prefer `getMetadata()` for the typed model.

### File Management

#### gather
```dart
Future<GatherResult> gather({
  required String containerId,
  StreamHandler<GatherResult>? onUpdate,
})
```
Lists all files and directories in the container. Optional `onUpdate` callback
receives the full list when files change. Invalid entries are returned in
`result.invalidEntries`.

```dart
for (final invalid in result.invalidEntries) {
  // Inspect malformed metadata entries if needed.
  debugPrint('Invalid entry: ${invalid.error}');
}
```

#### delete
```dart
Future<void> delete({
  required String containerId,
  required String relativePath,
})
```
Deletes a file or directory.

#### move
```dart
Future<void> move({
  required String containerId,
  required String fromRelativePath,
  required String toRelativePath,
})
```
Moves or renames a file or directory.

#### rename
```dart
Future<void> rename({
  required String containerId,
  required String relativePath,
  required String newName,
})
```
Renames a file or directory in place.

#### copy
```dart
Future<void> copy({
  required String containerId,
  required String fromRelativePath,
  required String toRelativePath,
})
```
Copies a file.

### Utilities

#### icloudAvailable
```dart
Future<bool> icloudAvailable()
```
Checks if iCloud is available and the user is signed in.

#### getContainerPath
```dart
Future<String?> getContainerPath({
  required String containerId,
})
```
Returns the local container path when available. Use document APIs for access.
Avoid direct `File()` reads/writes inside the container; use `uploadFile` and
`downloadFile` instead.

### ICloudFile Model

```dart
class ICloudFile {
  final String relativePath;
  final bool isDirectory;
  final int? sizeInBytes;           // null for directories, undownloaded files
  final DateTime? creationDate;     // null when metadata unavailable
  final DateTime? contentChangeDate; // null when metadata unavailable
  final DownloadStatus? downloadStatus; // null for local-only files
}
```

`ICloudFile` uses value equality (via `equatable`) to make testing and
comparisons predictable.

### Error Handling

All methods throw `PlatformException` on errors. Common codes:
- `E_CTR` (iCloud container/permission issues)
- `E_FNF` (file not found)
- `E_FNF_READ` (file not found during read)
- `E_FNF_WRITE` (file not found during write)
- `E_NAT` (native error)
- `E_PLUGIN_INTERNAL` (internal plugin error — please open a GitHub issue)
- `E_ARG` (invalid arguments)
- `E_READ` (read failure)
- `E_CANCEL` (operation canceled)

`PlatformExceptionCode` provides constants for the common native error codes
above. Use string literals for codes that are not defined there.

```dart
try {
  await ICloudStorage.uploadFile(...);
} on PlatformException catch (e) {
  switch (e.code) {
    case PlatformExceptionCode.iCloudConnectionOrPermission:
      // Invalid containerId or iCloud unavailable
      break;
    case PlatformExceptionCode.fileNotFound:
      // File does not exist in iCloud
      break;
    case PlatformExceptionCode.fileNotFoundRead:
      // File not found during read
      break;
    case PlatformExceptionCode.fileNotFoundWrite:
      // File not found during write
      break;
    case PlatformExceptionCode.nativeCodeError:
      // Underlying native error
      break;
    case 'E_PLUGIN_INTERNAL':
      // Internal plugin error — please open a GitHub issue
      break;
    case 'E_ARG':
      // Invalid arguments
      break;
    case 'E_READ':
      // Failed to read file content
      break;
    case 'E_CANCEL':
      // Operation canceled by caller
      break;
    default:
      // Other error
  }
}
```

## Platform Support

| Platform | Minimum Version |
|----------|----------------|
| iOS | 13.0 |
| macOS | 10.15 |

## Technical Details

### Implementation

This plugin uses Apple's document storage APIs to provide safe, coordinated access to iCloud files:

- **NSMetadataQuery**: Reports sync progress and metadata updates
- **UIDocument (iOS) / NSDocument (macOS)**: Coordinates file access and handles conflict resolution
- **NSUbiquitousContainerIdentifier**: Accesses app-specific iCloud container
- **FileManager + NSFileCoordinator**: Performs delete/move/copy/exists/metadata
  operations on container paths with coordinated access

### File Coordination

Without coordinated access, your app can encounter "Operation not permitted"
errors (NSCocoaErrorDomain Code=257) when iCloud sync is accessing files. This
plugin relies on `UIDocument`/`NSDocument` to coordinate reads/writes and to:

1. Coordinate with iCloud sync processes
2. Handle file conflicts automatically
3. Download files on-demand when reading
4. Upload files reliably when writing

### Sync Behavior

- Files sync automatically across devices signed into the same iCloud account
- iOS may defer uploads on cellular connections
- macOS typically syncs immediately when network is available
- Use `gather()` with `onUpdate` to monitor file changes

### Testing Recommendations

- **Use physical devices for testing**: iCloud functionality is unreliable in iOS Simulator
- Basic file operations may work in simulator, but sync behavior is unpredictable
- Multi-device sync testing requires multiple physical devices
- The Simulator's "Trigger iCloud Sync" feature (Debug → Trigger iCloud Sync) exists but is unreliable

### Apple Documentation

- [NSMetadataQuery](https://developer.apple.com/documentation/foundation/nsmetadataquery)
- [UIDocument](https://developer.apple.com/documentation/uikit/uidocument)
- [NSDocument](https://developer.apple.com/documentation/appkit/nsdocument)
- [iCloud Document Storage](https://developer.apple.com/icloud/documentation/data-storage/)
- [Configuring iCloud Services](https://developer.apple.com/documentation/xcode/configuring-icloud-services)

## Troubleshooting

### iCloud Not Available

If `icloudAvailable()` returns false:
- User is not signed into iCloud
- iCloud Drive is disabled in Settings
- Container ID does not match Xcode configuration

### Files Not Syncing

- **Test on real devices**: iCloud sync is unreliable in iOS Simulator. Use physical devices for sync testing
- Sync can take time, especially for large files or slow connections
- Check that container ID matches in code, Xcode capabilities, and Apple Developer portal
- Verify iCloud capability is enabled for the correct target
- For multi-device sync testing, use multiple physical devices signed into the same iCloud account

### Files Not Visible in Files App

- File path must start with `Documents/` (case-sensitive)
- `Info.plist` must include `NSUbiquitousContainers` configuration
- `NSUbiquitousContainerIsDocumentScopePublic` must be set to true
- The app folder appears only after writing at least one file under
  `Documents/`

### Permission Errors

Use streaming methods (`uploadFile`, `downloadFile`) instead of manual file
access within the iCloud container. These methods coordinate access via
UIDocument/NSDocument to prevent permission errors.

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Support

If you find this plugin helpful, consider supporting its development:

[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-support-yellow?logo=buy-me-a-coffee)](https://buymeacoffee.com/jasonholtdigital)

## Credits

Forked from [icloud_storage](https://github.com/deansyd/icloud_storage) by [deansyd](https://github.com/deansyd).
