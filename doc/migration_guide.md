# Migration Guide: Adopting Safe iCloud Operations

This guide helps you migrate from basic iCloud operations to the new safe, document-based APIs that prevent permission errors and provide automatic conflict resolution.

## Overview

The iCloud Storage Plus plugin now provides two approaches for file operations:

1. **Legacy Methods** - Original APIs (still supported for backward compatibility)
2. **Safe Document-Based Methods** - New APIs that prevent common errors and provide better iCloud integration

## Why Migrate?

### Common Issues with Legacy Approach

#### Permission Errors (NSCocoaErrorDomain Code=257)
```dart
// ❌ PROBLEMATIC: This can cause permission errors
await ICloudStorage.download(containerId: 'iCloud.com.example.app', relativePath: 'data.json');
final containerPath = await ICloudStorage.getContainerPath(containerId: 'iCloud.com.example.app');
final file = File('$containerPath/data.json');
final content = await file.readAsString(); // ⚠️ May fail with Code=257
```

#### Unsafe File Creation
```dart
// ❌ PROBLEMATIC: Creating files outside of iCloud coordination
final tempFile = File('${tempDir}/settings.json');
await tempFile.writeAsString(jsonEncode(settings)); // Not coordinated!
await ICloudStorage.upload(filePath: tempFile.path, ...);
```

#### No Conflict Resolution
```dart
// ❌ PROBLEMATIC: Manual read-modify-write loses concurrent changes
final data = await downloadAndRead(...);
final modified = modifyData(data);
await upload(...); // Overwrites any changes from other devices
```

## Migration Strategies

### 1. Safe File Reading

#### Before (Error-Prone)
```dart
// Download then read manually - can cause permission errors
await ICloudStorage.download(
  containerId: 'iCloud.com.example.app', 
  relativePath: 'Documents/settings.json',
);

final containerPath = await ICloudStorage.getContainerPath(
  containerId: 'iCloud.com.example.app',
);
final file = File('$containerPath/Documents/settings.json');
final content = await file.readAsString(); // ⚠️ May fail
final settings = jsonDecode(content);
```

#### After (Safe)
```dart
// ✅ RECOMMENDED: Document-based reading (most efficient)
final settings = await ICloudStorage.readJsonDocument(
  containerId: 'iCloud.com.example.app',
  relativePath: 'Documents/settings.json',
);

// ✅ ALTERNATIVE: For binary files
final bytes = await ICloudStorage.readDocument(
  containerId: 'iCloud.com.example.app',
  relativePath: 'Documents/settings.json',
);
if (bytes != null) {
  final content = utf8.decode(bytes);
  final settings = jsonDecode(content);
}

// ⚠️ COMPATIBILITY: Only if you need progress monitoring
final bytes = await ICloudStorage.downloadAndRead(
  containerId: 'iCloud.com.example.app',
  relativePath: 'Documents/settings.json',
  onProgress: (stream) => stream.listen((progress) => print('$progress%')),
);
```

### 2. Safe File Writing

#### Before (Not Coordinated)
```dart
// Create local file then upload
final tempFile = File('${tempDir}/settings.json');
await tempFile.writeAsString(jsonEncode(settings));
await ICloudStorage.upload(
  containerId: 'iCloud.com.example.app',
  filePath: tempFile.path,
  destinationRelativePath: 'Documents/settings.json',
);
```

#### After (Safe with Conflict Resolution)
```dart
// Direct document writing with automatic conflict resolution
await ICloudStorage.writeJsonDocument(
  containerId: 'iCloud.com.example.app',
  relativePath: 'Documents/settings.json',
  data: settings,
);

// Or for binary data
final bytes = utf8.encode(jsonEncode(settings));
await ICloudStorage.writeDocument(
  containerId: 'iCloud.com.example.app',
  relativePath: 'Documents/settings.json',
  data: bytes,
);
```

### 3. Safe Read-Modify-Write Operations

#### Before (Loses Concurrent Changes)
```dart
// Unsafe: concurrent changes will be lost
final current = await downloadAndRead(...);
final modified = modifyData(current);
await writeDocument(..., modified); // Overwrites concurrent changes
```

#### After (Atomic Updates)
```dart
// Safe: handles concurrent modifications automatically
await ICloudStorage.updateDocument(
  containerId: 'iCloud.com.example.app',
  relativePath: 'Documents/counter.txt',
  updater: (currentData) {
    final current = currentData.isEmpty 
        ? 0 
        : int.parse(utf8.decode(currentData));
    return utf8.encode((current + 1).toString());
  },
);
```

### 4. File Existence Checking

#### Before (Inefficient)
```dart
// Downloads metadata for all files
final files = await ICloudStorage.gather(containerId: 'iCloud.com.example.app');
final exists = files.any((file) => file.relativePath == 'Documents/myfile.pdf');
```

#### After (Efficient)
```dart
// Direct check without downloading file list
final exists = await ICloudStorage.documentExists(
  containerId: 'iCloud.com.example.app',
  relativePath: 'Documents/myfile.pdf',
);
```

### 5. Getting File Metadata

#### Before (Gets All Files)
```dart
final files = await ICloudStorage.gather(containerId: 'iCloud.com.example.app');
final myFile = files.firstWhere((file) => file.relativePath == 'Documents/report.pdf');
print('Size: ${myFile.sizeInBytes}');
```

#### After (Targeted Metadata)
```dart
final metadata = await ICloudStorage.getDocumentMetadata(
  containerId: 'iCloud.com.example.app',
  relativePath: 'Documents/report.pdf',
);
if (metadata != null) {
  print('Size: ${metadata['sizeInBytes']}');
  print('Modified: ${metadata['modificationDate']}');
  print('Conflicts: ${metadata['hasUnresolvedConflicts']}');
}
```

## Files App Visibility

### Making Files Visible in iOS Files App

#### Before (Confusing)
```dart
// Easy to forget the Documents/ prefix
await ICloudStorage.upload(
  containerId: 'iCloud.com.example.app',
  filePath: localPath,
  destinationRelativePath: 'Documents/report.pdf', // Easy to forget Documents/
);
```

#### After (Explicit)
```dart
// Method makes intention clear
await ICloudStorage.uploadToDocuments(
  containerId: 'iCloud.com.example.app',
  filePath: localPath,
  destinationRelativePath: 'report.pdf', // Documents/ added automatically
);

// Or use constants for clarity
await ICloudStorage.upload(
  containerId: 'iCloud.com.example.app', 
  filePath: localPath,
  destinationRelativePath: '${ICloudStorage.documentsDirectory}/report.pdf',
);
```

### App-Private Storage

#### Before (Implicit)
```dart
// Not clear that this is private storage
await ICloudStorage.upload(
  containerId: 'iCloud.com.example.app',
  filePath: localPath,
  destinationRelativePath: 'cache/data.db',
);
```

#### After (Explicit)
```dart
// Method makes intention clear
await ICloudStorage.uploadPrivate(
  containerId: 'iCloud.com.example.app',
  filePath: localPath,
  destinationRelativePath: 'cache/data.db',
);
```

## Progressive Migration Strategy

### Phase 1: Adopt Document APIs (High Priority) ⭐
**RECOMMENDED**: Replace unsafe patterns with document-based methods:

```dart
// Replace this dangerous pattern everywhere:
await ICloudStorage.download(...);
final file = File('$containerPath/...');
final content = await file.readAsString(); // FAILS

// With this simple, efficient solution:
final data = await ICloudStorage.readJsonDocument(...); // For JSON
final bytes = await ICloudStorage.readDocument(...);    // For other files
```

### Phase 2: Use downloadAndRead() for Compatibility (Medium Priority)
**FALLBACK**: If you need progress monitoring or have complex migration needs:

```dart
// Only use this if you specifically need progress callbacks
final bytes = await ICloudStorage.downloadAndRead(
  ...,
  onProgress: (stream) => stream.listen((progress) => updateUI(progress))
);
```

### Phase 3: Migrate Critical Read-Modify-Write Operations (Medium Priority)
Replace unsafe update patterns with `updateDocument()`:

```dart
// Replace manual read-modify-write patterns
await ICloudStorage.updateDocument(..., updater: (current) => modified);
```

### Phase 4: Use Convenience Methods (Low Priority)
Adopt clearer method names for Files app visibility:

```dart
// Replace upload() with explicit methods
await ICloudStorage.uploadToDocuments(...);  // For user files
await ICloudStorage.uploadPrivate(...);      // For app data
```

## Error Handling

### Document-Based Operations
```dart
try {
  await ICloudStorage.writeJsonDocument(...);
} on InvalidArgumentException catch (e) {
  // Handle validation errors (path, JSON format, etc.)
  print('Invalid argument: $e');
} on PlatformException catch (e) {
  // Handle iCloud/system errors
  print('Platform error: ${e.code} - ${e.message}');
}
```

### Conflict Detection
```dart
final metadata = await ICloudStorage.getDocumentMetadata(...);
if (metadata?['hasUnresolvedConflicts'] == true) {
  // Handle conflicts - document APIs resolve automatically
  // but you may want to notify users
  print('File has conflicts - automatic resolution applied');
}
```

## Testing Considerations

### Unit Tests
```dart
// Mock document operations the same way as legacy operations
when(mockPlatform.readJsonDocument(...))
    .thenAnswer((_) async => {'key': 'value'});
```

### Integration Tests
```dart
// Test with actual iCloud container
final originalData = {'version': 1};
await ICloudStorage.writeJsonDocument(..., data: originalData);

final readData = await ICloudStorage.readJsonDocument(...);
expect(readData, equals(originalData));
```

## Troubleshooting Common Issues

### "File not found" Errors
```dart
// Always check existence before reading
final exists = await ICloudStorage.documentExists(...);
if (exists) {
  final data = await ICloudStorage.readDocument(...);
}
```

### iCloud Sync Delays
```dart
// Use metadata to check download status
final metadata = await ICloudStorage.getDocumentMetadata(...);
if (metadata?['isDownloaded'] != true) {
  // File may not be downloaded yet
  await ICloudStorage.downloadAndRead(...); // Forces download
}
```

### Large File Performance
```dart
// For large files, monitor progress
await ICloudStorage.downloadAndRead(
  ...,
  onProgress: (stream) {
    stream.listen((progress) {
      print('Download progress: ${(progress * 100).toStringAsFixed(1)}%');
    });
  },
);
```

## Best Practices Summary

1. **⭐ ALWAYS use `readDocument()` / `readJsonDocument()` for reading files** (most efficient)
2. **⭐ ALWAYS use `writeDocument()` / `writeJsonDocument()` for writing files** (safe with conflict resolution)
3. **Use `updateDocument()` for safe read-modify-write operations**
4. **Check file existence with `documentExists()` before reading**
5. **Use convenience methods for clear intent (`uploadToDocuments`, `uploadPrivate`)**
6. **AVOID: `download()` + manual file reading** (causes Code=257 errors)
7. **Use `downloadAndRead()` only when you need progress monitoring**
8. **Use explicit `download()` only for pre-caching or batch operations**
9. **Monitor file metadata for sync status and conflicts**
10. **Handle `InvalidArgumentException` for validation errors**
11. **Test with actual iCloud containers, not just mocks**

## Backward Compatibility

All legacy methods remain available and functional. You can migrate incrementally:

- ✅ `upload()`, `download()`, `delete()`, `move()`, `rename()` - Still work
- ✅ `gather()` - Still works, now with fixed null metadata handling
- ✅ `exists()`, `getMetadata()`, `copy()` - Still work
- ✅ `getContainerPath()` - Still works for advanced use cases

The new APIs complement rather than replace the legacy APIs, so you can adopt them gradually based on your priorities and needs.