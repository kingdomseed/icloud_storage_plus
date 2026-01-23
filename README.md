# iCloud Storage Plus

[![Pub Version](https://img.shields.io/pub/v/icloud_storage_plus)](https://pub.dev/packages/icloud_storage_plus)
[![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20macOS-blue)]()
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![style: very good analysis](https://img.shields.io/badge/style-very_good_analysis-B22C89.svg)](https://pub.dev/packages/very_good_analysis)

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

### Basic Example

```dart
import 'dart:convert';
import 'package:icloud_storage_plus/icloud_storage.dart';
import 'package:flutter/services.dart';

// Check iCloud availability
final available = await ICloudStorage.icloudAvailable();
if (!available) {
  // User is not signed into iCloud
  return;
}

// Write a document
try {
  await ICloudStorage.writeDocument(
    containerId: 'iCloud.com.yourapp.container',
    relativePath: 'Documents/notes.txt',
    data: utf8.encode('My notes'),
  );
} on PlatformException catch (e) {
  // Handle errors
}

// Read a document
final bytes = await ICloudStorage.readDocument(
  containerId: 'iCloud.com.yourapp.container',
  relativePath: 'Documents/notes.txt',
);

if (bytes != null) {
  final content = utf8.decode(bytes);
}
```

### JSON Operations

```dart
// Write JSON
await ICloudStorage.writeJsonDocument(
  containerId: 'iCloud.com.yourapp.container',
  relativePath: 'Documents/settings.json',
  data: {'theme': 'dark', 'notifications': true},
);

// Read JSON
final data = await ICloudStorage.readJsonDocument(
  containerId: 'iCloud.com.yourapp.container',
  relativePath: 'Documents/settings.json',
);
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
final files = await ICloudStorage.gather(
  containerId: 'iCloud.com.yourapp.container',
  onUpdate: (stream) {
    stream.listen((updates) {
      // Handle file list updates
    });
  },
);
```

## Migration from 2.x

### Breaking Changes

#### 1. Nullable ICloudFile Fields

Four fields are now nullable:
- `sizeInBytes: int?` - null for directories and undownloaded files
- `creationDate: DateTime?` - null when metadata unavailable
- `contentChangeDate: DateTime?` - null when metadata unavailable
- `downloadStatus: DownloadStatus?` - null for local-only files

**Before (2.x):**
```dart
final metadata = await ICloudStorage.getMetadata(...);
final size = metadata.sizeInBytes;  // Always non-null
```

**After (3.0):**
```dart
final metadata = await ICloudStorage.getMetadata(...);
final size = metadata?.sizeInBytes ?? 0;  // Handle null
```

#### 2. Directory Detection

`exists()` and `getMetadata()` now return true/non-null for directories. Use `isDirectory` field to distinguish files from directories.

**Before (2.x):**
```dart
// Directories returned false
final exists = await ICloudStorage.exists(...);
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

Replace manual file operations with document methods:

**Before (2.x):**
```dart
await ICloudStorage.download(...);
final path = await ICloudStorage.getContainerPath(...);
final file = File('$path/Documents/file.json');
final contents = await file.readAsString();  // Can fail with permission errors
```

**After (3.0):**
```dart
final data = await ICloudStorage.readJsonDocument(...);  // Safe, coordinated access
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
relativePath: 'Documents/notes.txt'

// Hidden from Files app
relativePath: 'cache/temp.dat'
```

## API Reference

### Document Operations

Recommended methods for most use cases. These methods handle downloading, file coordination, and conflict resolution automatically.

#### readDocument
```dart
Future<Uint8List?> readDocument({
  required String containerId,
  required String relativePath,
})
```
Reads a document with automatic download if needed. Returns null if file does not exist.

#### writeDocument
```dart
Future<void> writeDocument({
  required String containerId,
  required String relativePath,
  required Uint8List data,
})
```
Writes a document with automatic conflict resolution. Creates parent directories as needed.

#### readJsonDocument
```dart
Future<Map<String, dynamic>?> readJsonDocument({
  required String containerId,
  required String relativePath,
})
```
Reads and parses JSON document. Returns null if the file does not exist.
Throws InvalidArgumentException if the JSON is invalid.

#### writeJsonDocument
```dart
Future<void> writeJsonDocument({
  required String containerId,
  required String relativePath,
  required Map<String, dynamic> data,
})
```
Encodes and writes JSON document.

#### updateDocument
```dart
Future<void> updateDocument({
  required String containerId,
  required String relativePath,
  required Uint8List Function(Uint8List currentData) updater,
})
```
Atomic read-modify-write operation. The updater receives current data (empty if
the file doesn't exist) and returns new data.

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
Future<List<ICloudFile>> gather({
  required String containerId,
  StreamHandler<List<ICloudFile>>? onUpdate,
})
```
Lists all files and directories in the container. Optional `onUpdate` callback receives updates when files change.

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

### Compatibility Helpers

#### downloadAndRead
```dart
Future<Uint8List?> downloadAndRead({
  required String containerId,
  required String relativePath,
  StreamHandler<double>? onProgress,
})
```
Downloads a file with progress callbacks and then reads it safely. Throws
`PlatformException` with `E_FNF` if the file doesn't exist.

#### exists
```dart
Future<bool> exists({
  required String containerId,
  required String relativePath,
})
```
Alias for `documentExists()` with path validation.

### Convenience Paths

#### uploadToDocuments
```dart
Future<void> uploadToDocuments({
  required String containerId,
  required String filePath,
  String? destinationRelativePath,
  StreamHandler<double>? onProgress,
})
```
Uploads to `Documents/` so files are visible in the Files app.

#### uploadPrivate
```dart
Future<void> uploadPrivate({
  required String containerId,
  required String filePath,
  String? destinationRelativePath,
  StreamHandler<double>? onProgress,
})
```
Uploads to the container root for app-private storage.

#### downloadFromDocuments
```dart
Future<bool> downloadFromDocuments({
  required String containerId,
  required String relativePath,
  StreamHandler<double>? onProgress,
})
```
Downloads from `Documents/` with progress callbacks.

### Advanced Operations

For specialized use cases requiring progress monitoring or explicit control over download/upload.

#### download
```dart
Future<bool> download({
  required String containerId,
  required String relativePath,
  StreamHandler<double>? onProgress,
})
```
Downloads a file with progress callbacks. Returns true if download succeeded.

#### upload
```dart
Future<void> upload({
  required String containerId,
  required String filePath,
  String? destinationRelativePath,
  StreamHandler<double>? onProgress,
})
```
Uploads a local file to iCloud with progress callbacks.

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
- `E_NAT` (native error)
- `E_ARG` (invalid arguments)
- `E_READ` (read failure)

```dart
try {
  await ICloudStorage.writeDocument(...);
} on PlatformException catch (e) {
  switch (e.code) {
    case PlatformExceptionCode.iCloudConnectionOrPermission:
      // Invalid containerId or iCloud unavailable
      break;
    case PlatformExceptionCode.fileNotFound:
      // File does not exist in iCloud
      break;
    case PlatformExceptionCode.nativeCodeError:
      // Underlying native error
      break;
    case 'E_ARG':
      // Invalid arguments
      break;
    case 'E_READ':
      // Failed to read file content
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

- **NSMetadataQuery**: Discovers files in iCloud container, including files that haven't been downloaded yet
- **NSFileCoordinator**: Coordinates file access to prevent conflicts with system processes
- **UIDocument (iOS) / NSDocument (macOS)**: Handles file reading/writing with automatic conflict resolution
- **NSUbiquitousContainerIdentifier**: Accesses app-specific iCloud container

### File Coordination

Without file coordination, your app can encounter "Operation not permitted" errors (NSCocoaErrorDomain Code=257) when iCloud sync is accessing files. This plugin uses `NSFileCoordinator` with `UIDocument`/`NSDocument` to:

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
- [NSFileCoordinator](https://developer.apple.com/documentation/foundation/nsfilecoordinator)
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

### Permission Errors

Use document methods (`readDocument`, `writeDocument`) instead of manual file access. These methods use `NSFileCoordinator` to prevent permission errors.

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Support

If you find this plugin helpful, consider supporting its development:

[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-support-yellow?logo=buy-me-a-coffee)](https://buymeacoffee.com/jasonholtdigital)

## Credits

Forked from [icloud_storage](https://github.com/deansyd/icloud_storage) by [deansyd](https://github.com/deansyd).
