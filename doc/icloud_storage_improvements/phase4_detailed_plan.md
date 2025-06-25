# Phase 4: Add Document-Based File Operations - Detailed Implementation Plan

## Overview

Phase 4 addresses a critical gap in our API: users need to create, read, and update iCloud files without touching the local filesystem. This prevents permission errors and provides automatic conflict resolution through UIDocument/NSDocument.

## Core Problem Analysis

### Current Workflow Issues

1. **Unsafe File Creation**
   ```dart
   // Current problematic pattern
   final tempFile = File('${tempDir}/data.json');
   await tempFile.writeAsString(jsonString); // Not coordinated!
   await ICloudStorage.upload(filePath: tempFile.path, ...);
   ```

2. **Unsafe File Reading**
   ```dart
   // After download, users do this (causes NSCocoaErrorDomain 257)
   final file = File('$containerPath/$relativePath');
   final content = await file.readAsString(); // Permission error!
   ```

3. **No Conflict Resolution for Updates**
   - Read file → Modify → Write back loses changes from other devices
   - No version tracking or conflict detection

## Implementation Plan

### Step 1: Native Method Implementation

#### 1.1 iOS - Add to iOSICloudStoragePlugin.swift

```swift
// Add to handle() method switch statement
case "readDocument":
  readDocument(call, result)
case "writeDocument":
  writeDocument(call, result)
case "documentExists":
  documentExists(call, result)
case "getDocumentMetadata":
  getDocumentMetadata(call, result)
```

#### 1.2 iOS - Implement readDocument

```swift
private func readDocument(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let args = call.arguments as? Dictionary<String, Any>,
          let containerId = args["containerId"] as? String,
          let relativePath = args["relativePath"] as? String
    else {
        result(argumentError)
        return
    }
    
    guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: containerId)
    else {
        result(containerError)
        return
    }
    
    let fileURL = containerURL.appendingPathComponent(relativePath)
    
    // Check if file exists first
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory),
          !isDirectory.boolValue else {
        result(nil) // Return nil for non-existent files
        return
    }
    
    // Use our UIDocument wrapper for safe reading
    readDocumentAt(url: fileURL) { (data, error) in
        if let error = error {
            result(self.nativeCodeError(error))
            return
        }
        
        guard let data = data else {
            result(nil)
            return
        }
        
        // Return as FlutterStandardTypedData
        result(FlutterStandardTypedData(bytes: data))
    }
}
```

#### 1.3 iOS - Implement writeDocument

```swift
private func writeDocument(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let args = call.arguments as? Dictionary<String, Any>,
          let containerId = args["containerId"] as? String,
          let relativePath = args["relativePath"] as? String,
          let flutterData = args["data"] as? FlutterStandardTypedData
    else {
        result(argumentError)
        return
    }
    
    guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: containerId)
    else {
        result(containerError)
        return
    }
    
    let fileURL = containerURL.appendingPathComponent(relativePath)
    let data = flutterData.data
    
    // Create parent directories if needed
    let dirURL = fileURL.deletingLastPathComponent()
    do {
        if !FileManager.default.fileExists(atPath: dirURL.path) {
            try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true, attributes: nil)
        }
    } catch {
        result(nativeCodeError(error))
        return
    }
    
    // Use our UIDocument wrapper for safe writing
    writeDocument(at: fileURL, data: data) { (error) in
        if let error = error {
            result(self.nativeCodeError(error))
            return
        }
        result(nil)
    }
}
```

#### 1.4 macOS - Same implementations with NSDocument

(Similar code structure but using NSDocument wrapper)

### Step 2: Platform Interface Updates

#### 2.1 Add to icloud_storage_platform_interface.dart

```dart
/// Read a document from iCloud using UIDocument/NSDocument
/// Returns null if file doesn't exist
Future<Uint8List?> readDocument({
  required String containerId,
  required String relativePath,
}) async {
  throw UnimplementedError('readDocument() has not been implemented.');
}

/// Write a document to iCloud using UIDocument/NSDocument
/// Creates the file if it doesn't exist, updates if it does
Future<void> writeDocument({
  required String containerId,
  required String relativePath,
  required Uint8List data,
}) async {
  throw UnimplementedError('writeDocument() has not been implemented.');
}

/// Check if a document exists without downloading
Future<bool> documentExists({
  required String containerId,
  required String relativePath,
}) async {
  throw UnimplementedError('documentExists() has not been implemented.');
}

/// Get document metadata without downloading content
Future<DocumentMetadata?> getDocumentMetadata({
  required String containerId,
  required String relativePath,
}) async {
  throw UnimplementedError('getDocumentMetadata() has not been implemented.');
}
```

### Step 3: Method Channel Implementation

#### 3.1 Add to icloud_storage_method_channel.dart

```dart
@override
Future<Uint8List?> readDocument({
  required String containerId,
  required String relativePath,
}) async {
  final result = await methodChannel.invokeMethod<Uint8List?>('readDocument', {
    'containerId': containerId,
    'relativePath': relativePath,
  });
  return result;
}

@override
Future<void> writeDocument({
  required String containerId,
  required String relativePath,
  required Uint8List data,
}) async {
  await methodChannel.invokeMethod('writeDocument', {
    'containerId': containerId,
    'relativePath': relativePath,
    'data': data,
  });
}
```

### Step 4: Main API Implementation

#### 4.1 Add to icloud_storage.dart

```dart
/// Read a document from iCloud safely
/// 
/// This method uses UIDocument/NSDocument internally to ensure proper
/// file coordination and prevent permission errors.
/// 
/// Returns null if the file doesn't exist.
/// 
/// Example:
/// ```dart
/// final bytes = await ICloudStorage.readDocument(
///   containerId: 'iCloud.com.example.app',
///   relativePath: 'Documents/settings.json',
/// );
/// if (bytes != null) {
///   final json = utf8.decode(bytes);
///   final settings = jsonDecode(json);
/// }
/// ```
static Future<Uint8List?> readDocument({
  required String containerId,
  required String relativePath,
}) async {
  if (!_validateRelativePath(relativePath)) {
    throw InvalidArgumentException('invalid relativePath: $relativePath');
  }
  
  return await ICloudStoragePlatform.instance.readDocument(
    containerId: containerId,
    relativePath: relativePath,
  );
}

/// Write a document to iCloud safely
/// 
/// This method uses UIDocument/NSDocument internally to ensure proper
/// file coordination, conflict resolution, and version tracking.
/// 
/// Creates the file if it doesn't exist, updates if it does.
/// 
/// Example:
/// ```dart
/// final data = {'setting1': true, 'setting2': 42};
/// final json = jsonEncode(data);
/// final bytes = utf8.encode(json);
/// 
/// await ICloudStorage.writeDocument(
///   containerId: 'iCloud.com.example.app',
///   relativePath: 'Documents/settings.json',
///   data: bytes,
/// );
/// ```
static Future<void> writeDocument({
  required String containerId,
  required String relativePath,
  required Uint8List data,
}) async {
  if (!_validateRelativePath(relativePath)) {
    throw InvalidArgumentException('invalid relativePath: $relativePath');
  }
  
  await ICloudStoragePlatform.instance.writeDocument(
    containerId: containerId,
    relativePath: relativePath,
    data: data,
  );
}
```

### Step 5: Convenience Methods

#### 5.1 Add JSON-specific helpers

```dart
/// Read a JSON document from iCloud
static Future<Map<String, dynamic>?> readJsonDocument({
  required String containerId,
  required String relativePath,
}) async {
  final bytes = await readDocument(
    containerId: containerId,
    relativePath: relativePath,
  );
  
  if (bytes == null) return null;
  
  try {
    final json = utf8.decode(bytes);
    return jsonDecode(json) as Map<String, dynamic>;
  } catch (e) {
    throw InvalidArgumentException('Invalid JSON in document: $e');
  }
}

/// Write a JSON document to iCloud
static Future<void> writeJsonDocument({
  required String containerId,
  required String relativePath,
  required Map<String, dynamic> data,
}) async {
  final json = jsonEncode(data);
  final bytes = utf8.encode(json);
  
  await writeDocument(
    containerId: containerId,
    relativePath: relativePath,
    data: bytes,
  );
}
```

#### 5.2 Add update method for safe read-modify-write

```dart
/// Update a document with automatic conflict resolution
/// 
/// This method safely handles concurrent updates by:
/// 1. Reading the current document
/// 2. Applying your changes
/// 3. Writing back with conflict detection
/// 
/// If the document doesn't exist, it will be created with the
/// result of calling updater with an empty Uint8List.
static Future<void> updateDocument({
  required String containerId,
  required String relativePath,
  required Uint8List Function(Uint8List currentData) updater,
}) async {
  // Read current content (or empty if doesn't exist)
  final currentData = await readDocument(
    containerId: containerId,
    relativePath: relativePath,
  ) ?? Uint8List(0);
  
  // Apply changes
  final newData = updater(currentData);
  
  // Write back
  await writeDocument(
    containerId: containerId,
    relativePath: relativePath,
    data: newData,
  );
}
```

### Step 6: Modify Existing Methods for Safety

#### 6.1 Update upload() to use document wrapper when appropriate

```dart
// In native code, detect text files and use document wrapper
private func upload(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    // ... existing parameter extraction ...
    
    let fileExtension = (cloudFileName as NSString).pathExtension.lowercased()
    let textExtensions = ["json", "txt", "xml", "plist", "yaml", "yml", "md"]
    
    if textExtensions.contains(fileExtension) {
        // Use document-based approach for text files
        do {
            let data = try Data(contentsOf: localFileURL)
            writeDocument(at: cloudFileURL, data: data) { error in
                if let error = error {
                    result(self.nativeCodeError(error))
                } else {
                    result(nil)
                }
            }
        } catch {
            result(nativeCodeError(error))
        }
    } else {
        // Use existing file copy for binary files
        // ... existing implementation ...
    }
}
```

## Testing Strategy

### Unit Tests

1. **Document Operations**
   - Test reading non-existent files (should return nil)
   - Test writing new files
   - Test updating existing files
   - Test JSON helpers with valid/invalid data

2. **Conflict Simulation**
   - Write same file from two "devices" (test instances)
   - Verify conflict resolution chooses most recent
   - Test update method handles conflicts

3. **Error Cases**
   - Invalid container ID
   - Invalid paths
   - Corrupted data
   - Network failures

### Integration Tests

1. **Full Workflow**
   ```dart
   // Create
   await writeJsonDocument(data: {'v': 1});
   
   // Read
   final data = await readJsonDocument();
   expect(data?['v'], equals(1));
   
   // Update
   await updateDocument((current) {
     final json = jsonDecode(utf8.decode(current));
     json['v'] = 2;
     return utf8.encode(jsonEncode(json));
   });
   
   // Verify
   final updated = await readJsonDocument();
   expect(updated?['v'], equals(2));
   ```

## Migration Guide

### For Existing Apps

```dart
// OLD: Unsafe pattern
final tempFile = File('${temp.path}/data.json');
await tempFile.writeAsString(jsonEncode(data));
await ICloudStorage.upload(
  filePath: tempFile.path,
  destinationRelativePath: 'data.json',
);

// NEW: Safe pattern
await ICloudStorage.writeJsonDocument(
  containerId: containerId,
  relativePath: 'data.json',
  data: data,
);
```

### Gradual Migration

1. Start using `downloadAndRead` instead of `download` + file read
2. Replace temp file creation with `writeDocument`
3. Use `updateDocument` for read-modify-write operations
4. Add proper error handling for nil returns

## Implementation Timeline

1. **Day 1**: Implement native methods (iOS & macOS)
2. **Day 2**: Add Dart API and test
3. **Day 3**: Documentation and migration guide

## Success Criteria

1. All document operations use UIDocument/NSDocument
2. No permission errors when reading/writing
3. Automatic conflict resolution works
4. Existing API remains unchanged
5. Clear migration path documented