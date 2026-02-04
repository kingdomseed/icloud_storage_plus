# iCloud Storage Plus

[![Pub Version](https://img.shields.io/pub/v/icloud_storage_plus)](https://pub.dev/packages/icloud_storage_plus)
[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/kingdomseed/icloud_storage_plus)
[![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20macOS-blue)]()
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![style: very good analysis](https://img.shields.io/badge/style-very_good_analysis-B22C89.svg)](https://pub.dev/packages/very_good_analysis)
[![shorebird ci](https://api.shorebird.dev/api/v1/github/kingdomseed/icloud_storage_plus/badge.svg)](https://console.shorebird.dev/ci)
[![Publisher](https://img.shields.io/badge/publisher-jasonholtdigital.com-2b7cff)](https://pub.dev/publishers/jasonholtdigital.com)

Flutter plugin for iCloud document storage (iOS/macOS) with coordinated file
access and optional Files app (iCloud Drive) visibility.

This package operates inside your app’s iCloud ubiquity container. You choose
which container to use via the `containerId` you configured in Apple Developer
Portal / Xcode.

## Platform support

| Platform | Minimum version |
|----------|-----------------|
| iOS | 13.0 |
| macOS | 10.15 |

## Installation

```bash
flutter pub add icloud_storage_plus
```

## Before you start (Xcode / entitlements)

1. Create an iCloud Container ID (example: `iCloud.com.yourapp.container`)
2. Enable iCloud for your App ID and assign that container
3. In Xcode → your target → Signing & Capabilities:
   - Add **iCloud**
   - Enable **iCloud Documents**
   - Select your container

### Files app integration (optional)

To make items visible in the Files app under “iCloud Drive”, you typically need
to declare your container under `NSUbiquitousContainers` in your `Info.plist`.

Files are only visible in Files/iCloud Drive when they live under the
`Documents/` prefix.

```dart
// Visible in Files app
cloudRelativePath: 'Documents/notes.txt'

// Not visible in Files app (still syncs)
cloudRelativePath: 'cache/notes.txt'
```

Note: your app’s folder won’t appear in Files/iCloud Drive until at least one
file exists under `Documents/`.

## Choosing the right API

There are two “tiers” of API in this plugin:

1. **Path-only transfers** for large files (no bytes returned to Dart)
   - `uploadFile` (local → iCloud)
   - `downloadFile` (iCloud → local)
2. **In-place content** for small files (bytes/strings cross the platform
   channel; loads full contents in memory)
   - `readInPlace`, `readInPlaceBytes`
   - `writeInPlace`, `writeInPlaceBytes`

The rest of the API is metadata + file management (`gather`, `getMetadata`,
`documentExists`, `delete`, `move`, `copy`, `rename`).

## Quick start

```dart
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:icloud_storage_plus/icloud_storage.dart';

const containerId = 'iCloud.com.yourapp.container';
const notesPath = 'Documents/notes.txt';

Future<void> example() async {
  final available = await ICloudStorage.icloudAvailable();
  if (!available) {
    // Not signed into iCloud, iCloud Drive disabled, etc.
    return;
  }

  // 1) Write a text file *in place* (recommended for JSON/text).
  await ICloudStorage.writeInPlace(
    containerId: containerId,
    relativePath: notesPath,
    contents: 'Hello from iCloud',
  );

  final contents = await ICloudStorage.readInPlace(
    containerId: containerId,
    relativePath: notesPath,
  );

  // 2) Copy-out to local storage (useful for large files / sharing / etc).
  final localCopy = '${Directory.systemTemp.path}/notes.txt';
  await ICloudStorage.downloadFile(
    containerId: containerId,
    cloudRelativePath: notesPath,
    localPath: localCopy,
  );

  // 3) Metadata / listing.
  final metadata = await ICloudStorage.getMetadata(
    containerId: containerId,
    relativePath: notesPath,
  );
  if (metadata != null && !metadata.isDirectory) {
    final size = metadata.sizeInBytes;
  }

  try {
    // Example: path validation happens in Dart before calling native.
    await ICloudStorage.readInPlace(
      containerId: containerId,
      relativePath: 'Documents/.hidden.txt',
    );
  } on InvalidArgumentException catch (e) {
    // Invalid path segment (starts with '.', contains ':', etc.)
    // This is a Dart-side exception (not a PlatformException).
    throw Exception(e);
  } on PlatformException catch (e) {
    // Native errors (e.g. container missing, file not found, etc.)
    throw Exception(e);
  }
}
```

## Transfers with progress

Progress is delivered via an `EventChannel` as *data events* of type
`ICloudTransferProgress`. Failures are **not** delivered via stream `onError`.

Important: the progress stream is listener-driven; start listening immediately
in the `onProgress` callback or you may miss early events.

```dart
await ICloudStorage.uploadFile(
  containerId: containerId,
  localPath: '/absolute/path/to/local/file.pdf',
  cloudRelativePath: 'Documents/file.pdf',
  onProgress: (stream) {
    stream.listen((event) {
      if (event.isProgress) {
        // 0.0 - 100.0
        final percent = event.percent!;
      } else if (event.isError) {
        final exception = event.exception!;
      }
    });
  },
);
```

## Paths: `cloudRelativePath` vs `relativePath`

This plugin always works in terms of paths *inside* the iCloud container:

- `cloudRelativePath`: used by `uploadFile` / `downloadFile`
- `relativePath`: used by the rest of the API

These are the same kind of value; the naming difference exists for historical
reasons.

### Trailing slashes

Directory paths can show up with trailing slashes in metadata, so the
directory-oriented methods accept them:

- `delete`, `move`, `copy`, `rename`, `documentExists`, `getMetadata`,
  `getDocumentMetadata`

File-centric operations reject trailing slashes (they require a file path):

- `uploadFile`, `downloadFile`
- `readInPlace`, `readInPlaceBytes`, `writeInPlace`, `writeInPlaceBytes`

### Path validation

Many methods validate path segments in Dart and throw `InvalidArgumentException`
for invalid values (empty segments, segments starting with `.`, segments that
contain `:` or `/`, etc).

## Listing / watching with `gather`

`gather()` returns a `GatherResult`:

- `files`: parsed metadata entries
- `invalidEntries`: entries that could not be parsed into `ICloudFile`

When `onUpdate` is provided, the update stream stays active until the
subscription is canceled. (Dispose listeners when done.)

```dart
final initial = await ICloudStorage.gather(
  containerId: containerId,
  onUpdate: (stream) {
    stream.listen((update) {
      // Full file list on every update.
      final files = update.files;
    });
  },
);
```

## Metadata: `ICloudFile`

`getMetadata()` and `gather()` return `ICloudFile`, which represents either a
file or a directory.

Some fields are nullable because iCloud may not have indexed the item yet, or
because the item is a directory (size) or remote-only (download status).

```dart
class ICloudFile {
  final String relativePath;
  final bool isDirectory;

  final int? sizeInBytes;
  final DateTime? creationDate;
  final DateTime? contentChangeDate;

  final bool isDownloading;
  final DownloadStatus? downloadStatus;
  final bool isUploading;
  final bool isUploaded;
  final bool hasUnresolvedConflicts;
}
```

## Error handling

### Dart-side validation (`InvalidArgumentException`)

Thrown when you pass an invalid path/name to the Dart API (before calling
native code).

### Native failures (`PlatformException`)

Thrown for container problems, file-not-found, read/write failures, etc.
`PlatformExceptionCode` contains constants:

- `E_CTR` (iCloud container/permission issues)
- `E_FNF` (file not found)
- `E_FNF_READ` (file not found during read)
- `E_FNF_WRITE` (file not found during write)
- `E_NAT` (native error)
- `E_ARG` (invalid arguments passed to native)
- `E_READ` (read failure)
- `E_CANCEL` (operation canceled)
- `E_INIT` (plugin not properly initialized)
- `E_TIMEOUT` (download idle timeout)
- `E_PLUGIN_INTERNAL` (internal plugin error)
- `E_INVALID_EVENT` (invalid event from native layer)

## Troubleshooting / gotchas

- Prefer testing on physical devices. iCloud sync is unreliable in iOS
  Simulator.
- `documentExists()` checks the filesystem path in the container; it does not
  force a download.
- If Files app visibility matters, ensure paths start with `Documents/` and
  your container is configured under `NSUbiquitousContainers`.

## Documentation

- Deeper implementation notes are available under `doc/`:
  - `doc/README.md`

## License

MIT License - see [LICENSE](LICENSE).

## Credits

Forked from [icloud_storage](https://github.com/deansyd/icloud_storage) by
[deansyd](https://github.com/deansyd).

Upstream is referenced for attribution only. This repository is not intended to
track upstream changes.
