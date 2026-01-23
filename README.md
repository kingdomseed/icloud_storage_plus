[![style: very good analysis](https://img.shields.io/badge/style-very_good_analysis-B22C89.svg)](https://pub.dev/packages/very_good_analysis)

# iCloud Storage Plus

A Flutter plugin for safe iCloud file operations. Upload, download, and manage files in your app's iCloud container with automatic conflict resolution and permission error prevention.  Based on [icloud_storage](https://pub.dev/packages/icloud_storage).

## Quick Start - Safe File Operations

This plugin provides safe ways to work with iCloud files that prevent common permission errors.

### Read a file safely

```dart
// Read any file - handles download automatically
final bytes = await ICloudStorage.readDocument(
  containerId: 'iCloud.com.yourapp.container',
  relativePath: 'Documents/settings.json',
);

// For JSON files, get parsed data directly
final data = await ICloudStorage.readJsonDocument(
  containerId: 'iCloud.com.yourapp.container',
  relativePath: 'Documents/settings.json',
);
```

### Write a file safely

```dart
// Write any file with automatic conflict resolution
await ICloudStorage.writeDocument(
  containerId: 'iCloud.com.yourapp.container',
  relativePath: 'Documents/settings.json',
  data: utf8.encode(jsonEncode(myData)),
);

// For JSON files, pass data directly
await ICloudStorage.writeJsonDocument(
  containerId: 'iCloud.com.yourapp.container',
  relativePath: 'Documents/settings.json',
  data: {'setting1': true, 'setting2': 42},
);
```

### Check if a file exists

```dart
final exists = await ICloudStorage.documentExists(
  containerId: 'iCloud.com.yourapp.container',
  relativePath: 'Documents/myfile.pdf',
);
```

## Important: Avoid Permission Errors

**Warning:** Accessing files manually after downloading can cause permission errors:

```dart
// DON'T do this - causes permission errors
await ICloudStorage.download(containerId: id, relativePath: path);
final file = File('$containerPath/$path');
final content = await file.readAsString(); // ERROR: Permission denied
```

**Instead, use the safe methods shown above.** They handle all the technical details automatically.

## Understanding iCloud Containers

When you use this plugin, files are stored in your app's iCloud container:

```
iCloud Container (your-container-id)
├── Documents/     ← Files here are visible in Files app
├── Data/          ← App-private data
└── [root files]   ← Files here sync but are private to your app
```

### Making Files Visible in Files App

To make files appear in the iOS/macOS Files app, store them in the `Documents` folder:

```dart
// Visible in Files app
await ICloudStorage.writeDocument(
  containerId: 'iCloud.com.yourapp.container',
  relativePath: 'Documents/report.pdf',  // Note: Documents/ prefix
  data: pdfBytes,
);

// Private to your app
await ICloudStorage.writeDocument(
  containerId: 'iCloud.com.yourapp.container',
  relativePath: 'settings.json',  // No Documents/ prefix
  data: settingsBytes,
);
```

## Setup Requirements

To use this plugin, you need:

1. An Apple Developer account
2. An App ID and iCloud Container ID 
3. iCloud capability enabled for your App ID
4. iCloud capability enabled in Xcode

See the [Setup Instructions](#setup-instructions) section below for detailed steps.

## API Reference

### File Operations (Recommended)

These methods are safe and handle all iCloud coordination automatically:

#### Read files

```dart
// Read any file type
final bytes = await ICloudStorage.readDocument(
  containerId: 'iCloud.com.yourapp.container',
  relativePath: 'Documents/data.json',
);

// Read JSON files (returns parsed data)
final jsonData = await ICloudStorage.readJsonDocument(
  containerId: 'iCloud.com.yourapp.container',
  relativePath: 'Documents/config.json',
);
```

#### Write files

```dart
// Write any file type
await ICloudStorage.writeDocument(
  containerId: 'iCloud.com.yourapp.container',
  relativePath: 'Documents/report.pdf',
  data: pdfBytes,
);

// Write JSON files (pass Map/List directly)
await ICloudStorage.writeJsonDocument(
  containerId: 'iCloud.com.yourapp.container',
  relativePath: 'Documents/settings.json',
  data: {'theme': 'dark', 'notifications': true},
);
```

#### Update files safely

```dart
// Read, modify, and write back safely
await ICloudStorage.updateDocument(
  containerId: 'iCloud.com.yourapp.container',
  relativePath: 'Documents/counter.txt',
  updater: (currentData) {
    final count = currentData.isEmpty ? 0 : int.parse(utf8.decode(currentData));
    return utf8.encode((count + 1).toString());
  },
);
```

#### Check files

```dart
// Check if file exists
final exists = await ICloudStorage.documentExists(
  containerId: 'iCloud.com.yourapp.container',
  relativePath: 'Documents/myfile.pdf',
);

// Get file info without downloading
final metadata = await ICloudStorage.getDocumentMetadata(
  containerId: 'iCloud.com.yourapp.container',
  relativePath: 'Documents/report.pdf',
);
```

### File Management

#### List all files

```dart
final files = await ICloudStorage.gather(
  containerId: 'iCloud.com.yourapp.container',
  onUpdate: (stream) {
    stream.listen((updatedFiles) {
      print('Files updated: ${updatedFiles.length} files');
    });
  },
);
```

#### Delete files

```dart
await ICloudStorage.delete(
  containerId: 'iCloud.com.yourapp.container',
  relativePath: 'Documents/oldfile.pdf',
);
```

#### Move and rename files

```dart
// Move to different folder
await ICloudStorage.move(
  containerId: 'iCloud.com.yourapp.container',
  fromRelativePath: 'Documents/report.pdf',
  toRelativePath: 'Documents/Archive/report.pdf',
);

// Rename file
await ICloudStorage.rename(
  containerId: 'iCloud.com.yourapp.container',
  relativePath: 'Documents/draft.pdf',
  newName: 'final.pdf',
);
```

#### Copy files

```dart
await ICloudStorage.copy(
  containerId: 'iCloud.com.yourapp.container',
  fromRelativePath: 'Documents/template.docx',
  toRelativePath: 'Documents/new-document.docx',
);
```

### Advanced Operations

These methods are for special cases where you need more control:

#### Upload files with progress

```dart
await ICloudStorage.upload(
  containerId: 'iCloud.com.yourapp.container',
  filePath: '/path/to/local/file.pdf',
  destinationRelativePath: 'Documents/file.pdf',
  onProgress: (stream) {
    stream.listen((progress) {
      print('Upload: ${(progress * 100).round()}%');
    });
  },
);
```

#### Download for caching

```dart
// Only use this for pre-downloading large files
final success = await ICloudStorage.download(
  containerId: 'iCloud.com.yourapp.container',
  relativePath: 'Documents/large-video.mp4',
  onProgress: (stream) {
    stream.listen((progress) {
      print('Download: ${(progress * 100).round()}%');
    });
  },
);

// Then read safely later
final bytes = await ICloudStorage.readDocument(
  containerId: 'iCloud.com.yourapp.container',
  relativePath: 'Documents/large-video.mp4',
);
```

## Common Issues and Solutions

### Permission Errors

**Problem**: Getting "permission denied" errors when reading files.

**Cause**: Reading files manually after download without proper coordination.

**Solution**: Use `readDocument()` instead of manual file reading:

```dart
// Wrong - causes permission errors
await ICloudStorage.download(containerId: id, relativePath: path);
final file = File('$containerPath/$path');
final content = await file.readAsString(); // ERROR

// Right - works safely
final bytes = await ICloudStorage.readDocument(containerId: id, relativePath: path);
final content = utf8.decode(bytes);
```

### Files Not Appearing in Files App

**Problem**: Uploaded files don't show up in the iOS/macOS Files app.

**Solution**: Store files in the `Documents` folder:

```dart
// Files app visible
await ICloudStorage.writeDocument(
  containerId: 'iCloud.com.yourapp.container',
  relativePath: 'Documents/myfile.pdf',  // Must start with Documents/
  data: fileData,
);
```

### Files Not Syncing Between Devices

**Problem**: Files uploaded on one device don't appear on another device.

**Solution**: This is normal. iCloud syncing happens automatically but may take time. In the iOS Simulator, you can force sync from Features > Trigger iCloud Sync.

### Error Handling

```dart
try {
  final data = await ICloudStorage.readJsonDocument(
    containerId: 'iCloud.com.yourapp.container',
    relativePath: 'Documents/settings.json',
  );
} catch (e) {
  if (e is PlatformException) {
    if (e.code == 'E_NAT') {
      print('iCloud error: ${e.message}');
    } else if (e.code == 'fileNotFound') {
      print('File does not exist');
    }
  }
}
```

## Setup Instructions

### 1. Create iCloud Container

1. Go to [Apple Developer Console](https://developer.apple.com)
2. Select "Certificates, IDs & Profiles"
3. Select "Identifiers" 
4. Create an App ID (if you don't have one)
5. Create an iCloud Container ID

### 2. Enable iCloud for Your App

1. Click on your App ID
2. In Capabilities, select "iCloud"
3. Assign your iCloud Container to this App ID

### 3. Configure Xcode

1. Open your project in Xcode
2. Set your Bundle Identifier to match your App ID
3. Click "+ Capability" and select "iCloud"
4. Check "iCloud Documents" 
5. Select your iCloud Container

### 4. Check iCloud Availability

```dart
final available = await ICloudStorage.icloudAvailable();
if (!available) {
  print('iCloud is not available. User may not be signed in.');
}
```

## Migrating from Version 2.x.x

If you're using the old download + manual file reading pattern, update to the safe methods:

```dart
// Old way (causes permission errors)
await ICloudStorage.download(containerId: id, relativePath: path);
final containerPath = await ICloudStorage.getContainerPath(containerId: id);
final file = File('$containerPath/$path');
final content = await file.readAsString();

// New way (safe and simple)
final data = await ICloudStorage.readJsonDocument(containerId: id, relativePath: path);
```

## Support for macOS

When using this plugin on macOS, make sure File Access is enabled in your app's entitlements if App Sandbox is enabled. Files in the app container are automatically accessible.

## References

- [Apple Documentation - Configuring iCloud Services](https://developer.apple.com/documentation/Xcode/configuring-icloud-services)
- [Apple Documentation - iOS Data Storage Guidelines](https://developer.apple.com/icloud/documentation/data-storage/)
- [Apple Documentation - FileManager URL(forUbiquityContainerIdentifier:)](https://developer.apple.com/documentation/Foundation/FileManager/url(forUbiquityContainerIdentifier:))

## License

MIT License - see LICENSE file for details.