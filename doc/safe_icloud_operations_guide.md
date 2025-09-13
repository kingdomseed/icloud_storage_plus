# Safe iCloud Operations Guide

This guide explains how to safely work with iCloud files to avoid NSCocoaErrorDomain Code=257 permission errors and handle conflicts properly.

## Understanding the Problem

When working with iCloud files, directly reading or writing files can cause permission errors because:
1. iCloud files may be placeholders that haven't been downloaded yet
2. File operations need coordination to prevent conflicts
3. Multiple devices may be modifying the same file

## Safe vs Unsafe Operations

### ❌ Unsafe Pattern (Causes Permission Errors)
```dart
// DON'T DO THIS - Can cause NSCocoaErrorDomain Code=257
await ICloudStorage.download(containerId: id, relativePath: 'data.json');
final path = await ICloudStorage.getContainerPath(containerId: id);
final file = File('$path/data.json');
final content = await file.readAsString(); // May fail with permission error!
```

### ✅ Safe Pattern 1: Use downloadAndRead
```dart
// Safe way to download and read in one operation
final bytes = await ICloudStorage.downloadAndRead(
  containerId: id,
  relativePath: 'data.json',
);
if (bytes != null) {
  final content = utf8.decode(bytes);
  final data = jsonDecode(content);
}
```

### ✅ Safe Pattern 2: Use Document-Based Operations (Coming in Phase 4)
```dart
// Direct read without download
final bytes = await ICloudStorage.readDocument(
  containerId: id,
  relativePath: 'data.json',
);
if (bytes != null) {
  final content = utf8.decode(bytes);
  final data = jsonDecode(content);
}

// Direct write without temporary files
final json = jsonEncode(myData);
final bytes = utf8.encode(json);
await ICloudStorage.writeDocument(
  containerId: id,
  relativePath: 'data.json',
  data: bytes,
);
```

## Complete Workflows

### Saving JSON Data to iCloud

#### Current Approach (Phase 1-3)
```dart
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

Future<void> saveJsonToICloud(Map<String, dynamic> data) async {
  // 1. Serialize to JSON
  final json = jsonEncode(data);
  
  // 2. Create temporary file
  final tempDir = await getTemporaryDirectory();
  final tempFile = File('${tempDir.path}/temp_data.json');
  await tempFile.writeAsString(json);
  
  // 3. Upload to iCloud
  await ICloudStorage.upload(
    containerId: 'iCloud.com.example.app',
    filePath: tempFile.path,
    destinationRelativePath: 'Documents/user_data.json',
  );
  
  // 4. Clean up temp file
  await tempFile.delete();
}
```

#### Future Approach (Phase 4+)
```dart
Future<void> saveJsonToICloud(Map<String, dynamic> data) async {
  // Direct write - no temp files needed!
  final json = jsonEncode(data);
  final bytes = utf8.encode(json);
  
  await ICloudStorage.writeDocument(
    containerId: 'iCloud.com.example.app',
    relativePath: 'Documents/user_data.json',
    data: bytes,
  );
}
```

### Reading JSON Data from iCloud

#### Safe Approach (Available Now)
```dart
Future<Map<String, dynamic>?> readJsonFromICloud() async {
  final bytes = await ICloudStorage.downloadAndRead(
    containerId: 'iCloud.com.example.app',
    relativePath: 'Documents/user_data.json',
  );
  
  if (bytes != null) {
    final json = utf8.decode(bytes);
    return jsonDecode(json);
  }
  return null;
}
```

#### Future Approach (Phase 4+)
```dart
Future<Map<String, dynamic>?> readJsonFromICloud() async {
  // Read without downloading first
  final bytes = await ICloudStorage.readDocument(
    containerId: 'iCloud.com.example.app',
    relativePath: 'Documents/user_data.json',
  );
  
  if (bytes != null) {
    final json = utf8.decode(bytes);
    return jsonDecode(json);
  }
  return null;
}
```

### Updating Existing Data

#### Safe Pattern for Updates
```dart
Future<void> updateJsonInICloud(
  String key, 
  dynamic value,
) async {
  // 1. Read existing data safely
  final bytes = await ICloudStorage.downloadAndRead(
    containerId: 'iCloud.com.example.app',
    relativePath: 'Documents/user_data.json',
  );
  
  Map<String, dynamic> data = {};
  if (bytes != null) {
    final json = utf8.decode(bytes);
    data = jsonDecode(json);
  }
  
  // 2. Update data
  data[key] = value;
  
  // 3. Save back (current approach)
  final tempDir = await getTemporaryDirectory();
  final tempFile = File('${tempDir.path}/temp_data.json');
  await tempFile.writeAsString(jsonEncode(data));
  
  await ICloudStorage.upload(
    containerId: 'iCloud.com.example.app',
    filePath: tempFile.path,
    destinationRelativePath: 'Documents/user_data.json',
  );
  
  await tempFile.delete();
}
```

## When to Use Each Method

### Use File-Based Operations (`upload`/`download`) For:
- Large binary files (images, videos, PDFs)
- Files that need specific local processing
- Existing files that need to be uploaded
- Backward compatibility

### Use Document-Based Operations (`readDocument`/`writeDocument`) For:
- JSON/XML configuration files
- Text documents
- Small data files
- Frequent read/write operations
- When you need conflict resolution

### Use `downloadAndRead` For:
- One-time reads of remote files
- When you need the content immediately
- Migration from unsafe download + read patterns

## Best Practices

1. **Always use helper methods** - Never read iCloud files directly with `File` class
2. **Handle nil/null results** - Files might not exist or download might fail  
3. **Use Documents directory** - For user-visible files, always use `Documents/` prefix
4. **Consider conflicts** - Document-based operations handle conflicts automatically
5. **Error handling** - Wrap operations in try-catch for network/permission errors

## Migration Guide

If you have existing code using unsafe patterns:

```dart
// Old unsafe code
await ICloudStorage.download(...);
final file = File(fullPath);
final content = await file.readAsString();

// Migrate to safe code
final bytes = await ICloudStorage.downloadAndRead(...);
final content = bytes != null ? utf8.decode(bytes) : null;
```

## Implementation Status

- ✅ **Available Now**: `downloadAndRead` method
- 🚧 **Phase 4**: `readDocument`/`writeDocument` methods
- 🚧 **Phase 4**: Conflict resolution UI helpers
- 🚧 **Phase 5**: Public API updates

## Summary

The key to safe iCloud operations is to never directly access iCloud files using standard file operations. Always use the provided methods that handle NSFileCoordinator and UIDocument/NSDocument internally. This prevents permission errors and ensures proper conflict handling.