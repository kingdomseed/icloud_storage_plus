# iCloud API Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the semver-major iCloud API cleanup that replaces ambiguous typed metadata with `ICloudItemMetadata`, introduces stable typed Dart exceptions backed by structured native error payloads, and normalizes typed metadata/listing download status without changing existing transfer-progress stream behavior.

**Architecture:** Keep the existing Darwin document IO model (`UIDocument` / `NSDocument`, `NSMetadataQuery`, `URLResourceValues`, `NSFileCoordinator`) intact. Move contract cleanup to the API and transport boundaries: add a dedicated typed known-path metadata model, keep the raw metadata escape hatch raw, and translate structured native error payloads into typed Dart exceptions while leaving progress streams on `PlatformException`.

**Tech Stack:** Flutter plugin, Dart, MethodChannel/EventChannel, Swift on iOS/macOS, XCTest helper packages, Flutter test, Flutter analyze.

---

## File Map

- Create: `lib/models/download_status.dart`
  - Shared `DownloadStatus` enum and raw-to-normalized parsing helper.
- Create: `lib/models/icloud_item_metadata.dart`
  - Typed known-path metadata model with in-band conflict/download/locality state.
- Create: `test/models/icloud_item_metadata_test.dart`
  - Unit tests for the new typed metadata model.
- Create: `test/models/exceptions_test.dart`
  - Unit tests for typed Dart exception mapping from `PlatformException`.
- Modify: `lib/models/icloud_file.dart`
  - Stop owning `DownloadStatus`; import the shared enum/parser.
- Modify: `lib/models/container_item.dart`
  - Import the shared `DownloadStatus` enum/parser.
- Modify: `lib/models/exceptions.dart`
  - Add typed Dart exception hierarchy, stable request/response transport codes, and `PlatformException` -> typed exception mapping.
- Modify: `lib/icloud_storage.dart`
  - Export the new model(s), remove `getMetadata`, add `getItemMetadata`, and update doc comments.
- Modify: `lib/icloud_storage_platform_interface.dart`
  - Add `getItemMetadata()` and update API contract comments.
- Modify: `lib/icloud_storage_method_channel.dart`
  - Add structured request/response error mapping, add `getItemMetadata()` invocation, keep progress streams unchanged.
- Modify: `ios/icloud_storage_plus/Sources/icloud_storage_plus/iOSICloudStoragePlugin.swift`
  - Add `getItemMetadata` native method, keep `getDocumentMetadata` raw, emit structured `FlutterError.details`, and route typed categories for current iOS operations.
- Modify: `ios/icloud_storage_plus/Sources/icloud_storage_plus/CoordinatedReplaceWriter.swift`
  - Split nonlocal replacement preflight into distinct not-downloaded vs download-in-progress categories.
- Modify: `ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/CoordinatedReplaceWriter.swift`
  - Keep the helper-package writer in parity with the production preflight split.
- Modify: `ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/Tests/icloud_storage_plus_foundationTests/CoordinatedReplaceWriterTests.swift`
  - Add helper tests for the new download-in-progress category split.
- Modify: `macos/icloud_storage_plus/Sources/icloud_storage_plus/macOSICloudStoragePlugin.swift`
  - Mirror the iOS native transport and metadata changes.
- Modify: `macos/icloud_storage_plus/Sources/icloud_storage_plus/CoordinatedReplaceWriter.swift`
  - Split nonlocal replacement preflight into distinct not-downloaded vs download-in-progress categories.
- Modify: `macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation/CoordinatedReplaceWriter.swift`
  - Keep the helper-package writer in parity with the production preflight split.
- Modify: `macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation/Tests/icloud_storage_plus_foundationTests/CoordinatedReplaceWriterTests.swift`
  - Add helper tests for the new download-in-progress category split.
- Modify: `test/icloud_storage_test.dart`
  - Replace `getMetadata` expectations with `getItemMetadata` and update fake platform behavior.
- Modify: `test/icloud_storage_method_channel_test.dart`
  - Add request/response typed-exception tests, `getItemMetadata` method-channel tests, and keep transfer-progress tests on `PlatformException`.
- Modify: `test/models/icloud_file_test.dart`
  - Update imports after `DownloadStatus` extraction.
- Modify: `README.md`
  - Replace `getMetadata` docs, add `ICloudItemMetadata`, document typed exceptions, and explicitly keep progress-stream errors on `PlatformException`.
- Modify: `example/lib/utils.dart`
  - Update error formatting for typed exceptions while keeping transfer-progress `PlatformException` handling intact.
- Modify: `CHANGELOG.md`
  - Add `2.0.0` breaking-change notes.
- Modify: `pubspec.yaml`
  - Bump version to `2.0.0`.

### Task 1: Extract Shared DownloadStatus And Add ICloudItemMetadata

**Files:**
- Create: `lib/models/download_status.dart`
- Create: `lib/models/icloud_item_metadata.dart`
- Create: `test/models/icloud_item_metadata_test.dart`
- Modify: `lib/models/icloud_file.dart`
- Modify: `lib/models/container_item.dart`
- Modify: `test/models/icloud_file_test.dart`

- [ ] **Step 1: Write the failing model tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:icloud_storage_plus/models/download_status.dart';
import 'package:icloud_storage_plus/models/icloud_item_metadata.dart';

void main() {
  test('fromMap normalizes typed metadata fields', () {
    final metadata = ICloudItemMetadata.fromMap({
      'relativePath': 'Documents/note.json',
      'isDirectory': false,
      'sizeInBytes': 7,
      'creationDate': 1.0,
      'contentChangeDate': 2.0,
      'downloadStatus': 'current',
      'isDownloading': false,
      'isUploading': true,
      'isUploaded': false,
      'hasUnresolvedConflicts': true,
    });

    expect(metadata.relativePath, 'Documents/note.json');
    expect(metadata.downloadStatus, DownloadStatus.current);
    expect(metadata.isLocal, isTrue);
    expect(metadata.hasUnresolvedConflicts, isTrue);
  });

  test('fromMap tolerates raw Apple download status keys during migration', () {
    final metadata = ICloudItemMetadata.fromMap({
      'relativePath': 'Documents/note.json',
      'downloadStatus':
          'NSURLUbiquitousItemDownloadingStatusNotDownloaded',
    });

    expect(metadata.downloadStatus, DownloadStatus.notDownloaded);
    expect(metadata.isLocal, isFalse);
  });
}
```

- [ ] **Step 2: Run the new model tests and verify they fail**

Run: `flutter test test/models/icloud_item_metadata_test.dart -r expanded`

Expected: FAIL with import or symbol errors for `ICloudItemMetadata` and `DownloadStatus`.

- [ ] **Step 3: Add the shared enum/parser and the new metadata model**

```dart
// lib/models/download_status.dart
enum DownloadStatus {
  notDownloaded,
  downloaded,
  current,
}

DownloadStatus? mapDownloadStatus(String? key) {
  if (key == null) return null;
  return switch (key) {
    'notDownloaded' ||
    'NSMetadataUbiquitousItemDownloadingStatusNotDownloaded' ||
    'NSURLUbiquitousItemDownloadingStatusNotDownloaded' =>
      DownloadStatus.notDownloaded,
    'downloaded' ||
    'NSMetadataUbiquitousItemDownloadingStatusDownloaded' ||
    'NSURLUbiquitousItemDownloadingStatusDownloaded' =>
      DownloadStatus.downloaded,
    'current' ||
    'NSMetadataUbiquitousItemDownloadingStatusCurrent' ||
    'NSURLUbiquitousItemDownloadingStatusCurrent' =>
      DownloadStatus.current,
    _ => null,
  };
}
```

```dart
// lib/models/icloud_item_metadata.dart
import 'package:equatable/equatable.dart';
import 'package:icloud_storage_plus/models/download_status.dart';
import 'package:icloud_storage_plus/models/exceptions.dart';

class ICloudItemMetadata extends Equatable {
  ICloudItemMetadata.fromMap(Map<dynamic, dynamic> map)
      : relativePath = _requireRelativePath(map),
        isDirectory = (map['isDirectory'] as bool?) ?? false,
        sizeInBytes = _mapToInt(map['sizeInBytes']),
        creationDate = _mapToDateTime(map['creationDate']),
        contentChangeDate = _mapToDateTime(map['contentChangeDate']),
        downloadStatus = mapDownloadStatus(map['downloadStatus'] as String?),
        isDownloading = (map['isDownloading'] as bool?) ?? false,
        isUploading = (map['isUploading'] as bool?) ?? false,
        isUploaded = (map['isUploaded'] as bool?) ?? false,
        hasUnresolvedConflicts =
            (map['hasUnresolvedConflicts'] as bool?) ?? false;

  final String relativePath;
  final bool isDirectory;
  final int? sizeInBytes;
  final DateTime? creationDate;
  final DateTime? contentChangeDate;
  final DownloadStatus? downloadStatus;
  final bool isDownloading;
  final bool isUploading;
  final bool isUploaded;
  final bool hasUnresolvedConflicts;

  bool get isLocal =>
      downloadStatus == DownloadStatus.downloaded ||
      downloadStatus == DownloadStatus.current;

  static String _requireRelativePath(Map<dynamic, dynamic> map) {
    final value = map['relativePath'];
    if (value is String) return value;
    throw InvalidArgumentException(
      'relativePath is required and must be a String '
      '(got: ${value.runtimeType})',
    );
  }

  static int? _mapToInt(dynamic value) => switch (value) {
    int value => value,
    double value => value.round(),
    num value => value.toInt(),
    _ => null,
  };

  static DateTime? _mapToDateTime(dynamic value) {
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch((value * 1000).round());
    }
    return null;
  }

  @override
  List<Object?> get props => [
        relativePath,
        isDirectory,
        sizeInBytes,
        creationDate,
        contentChangeDate,
        downloadStatus,
        isDownloading,
        isUploading,
        isUploaded,
        hasUnresolvedConflicts,
      ];
}
```

```dart
// lib/models/icloud_file.dart and lib/models/container_item.dart
import 'package:icloud_storage_plus/models/download_status.dart';

// Replace bespoke download-status parsing with:
downloadStatus = mapDownloadStatus(map['downloadStatus'] as String?),
```

- [ ] **Step 4: Run model tests and the existing metadata model tests**

Run: `flutter test test/models/icloud_item_metadata_test.dart test/models/icloud_file_test.dart -r expanded`

Expected: PASS

- [ ] **Step 5: Commit the shared model extraction**

```bash
git add lib/models/download_status.dart lib/models/icloud_item_metadata.dart lib/models/icloud_file.dart lib/models/container_item.dart test/models/icloud_item_metadata_test.dart test/models/icloud_file_test.dart
git commit -m "feat: add typed known-path metadata model"
```

### Task 2: Replace The Public Typed Metadata API

**Files:**
- Modify: `lib/icloud_storage.dart`
- Modify: `lib/icloud_storage_platform_interface.dart`
- Modify: `lib/icloud_storage_method_channel.dart`
- Modify: `test/icloud_storage_test.dart`

- [ ] **Step 1: Write the failing public API tests for `getItemMetadata()`**

```dart
test('getItemMetadata returns typed metadata', () async {
  final metadata = await ICloudStorage.getItemMetadata(
    containerId: containerId,
    relativePath: 'Documents/test.pdf',
  );

  expect(metadata, isNotNull);
  expect(metadata?.relativePath, 'Documents/test.pdf');
});

test('getItemMetadata returns null for missing item', () async {
  fakePlatform.itemMetadataResult = null;

  final metadata = await ICloudStorage.getItemMetadata(
    containerId: containerId,
    relativePath: 'Documents/missing.pdf',
  );

  expect(metadata, isNull);
});
```

- [ ] **Step 2: Run the API tests and verify they fail**

Run: `flutter test test/icloud_storage_test.dart -r expanded`

Expected: FAIL because `getItemMetadata()` and `itemMetadataResult` do not exist.

- [ ] **Step 3: Replace the typed metadata surface and add the platform hook**

```dart
// lib/icloud_storage_platform_interface.dart
Future<Map<String, dynamic>?> getItemMetadata({
  required String containerId,
  required String relativePath,
}) async {
  throw UnimplementedError('getItemMetadata() has not been implemented.');
}
```

```dart
// lib/icloud_storage.dart
export 'models/download_status.dart';
export 'models/icloud_item_metadata.dart';

static Future<ICloudItemMetadata?> getItemMetadata({
  required String containerId,
  required String relativePath,
}) async {
  if (!_validateRelativePath(relativePath)) {
    throw InvalidArgumentException('invalid relativePath: $relativePath');
  }

  final metadata = await ICloudStoragePlatform.instance.getItemMetadata(
    containerId: containerId,
    relativePath: relativePath,
  );
  if (metadata == null) return null;
  return ICloudItemMetadata.fromMap(metadata);
}
```

```dart
// test/icloud_storage_test.dart fake platform
Map<String, dynamic>? itemMetadataResult = {
  'relativePath': 'Documents/test.pdf',
  'isDirectory': false,
  'downloadStatus': 'current',
};

@override
Future<Map<String, dynamic>?> getItemMetadata({
  required String containerId,
  required String relativePath,
}) async {
  _calls.add('getItemMetadata');
  return itemMetadataResult;
}
```

```dart
// lib/icloud_storage_method_channel.dart
@override
Future<Map<String, dynamic>?> getItemMetadata({
  required String containerId,
  required String relativePath,
}) async {
  final result = await methodChannel
      .invokeMethod<Map<dynamic, dynamic>?>('getItemMetadata', {
    'containerId': containerId,
    'relativePath': relativePath,
  });
  if (result == null) return null;
  return result.map((key, value) => MapEntry(key.toString(), value));
}
```

- [ ] **Step 4: Run the public API tests again**

Run: `flutter test test/icloud_storage_test.dart -r expanded`

Expected: PASS

- [ ] **Step 5: Commit the public metadata API swap**

```bash
git add lib/icloud_storage.dart lib/icloud_storage_platform_interface.dart lib/icloud_storage_method_channel.dart test/icloud_storage_test.dart
git commit -m "feat: replace getMetadata with getItemMetadata"
```

### Task 3: Add Typed Dart Exceptions And Request/Response Mapping

**Files:**
- Create: `test/models/exceptions_test.dart`
- Modify: `lib/models/exceptions.dart`
- Modify: `lib/icloud_storage_method_channel.dart`
- Modify: `test/icloud_storage_method_channel_test.dart`

- [ ] **Step 1: Write the failing typed-exception tests**

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icloud_storage_plus/models/exceptions.dart';

void main() {
  test('maps details.category conflict to ICloudConflictException', () {
    final error = const PlatformException(
      code: 'E_CONFLICT',
      message: 'Cannot replace item with unresolved conflicts',
      details: {
        'category': 'conflict',
        'operation': 'writeInPlace',
        'retryable': false,
      },
    );

    final mapped = mapICloudPlatformException(error);
    expect(mapped, isA<ICloudConflictException>());
  });

  test('maps details.category timeout to ICloudTimeoutException', () {
    final error = const PlatformException(
      code: 'E_TIMEOUT',
      message: 'Timed out',
      details: {
        'category': 'timeout',
        'operation': 'readInPlace',
        'retryable': true,
      },
    );

    final mapped = mapICloudPlatformException(error);
    expect(mapped, isA<ICloudTimeoutException>());
  });

  test('maps details.category itemNotDownloaded to typed exception', () {
    final error = const PlatformException(
      code: 'E_NOT_DOWNLOADED',
      message: 'Item is not downloaded',
      details: {
        'category': 'itemNotDownloaded',
        'operation': 'copy',
        'retryable': true,
      },
    );

    final mapped = mapICloudPlatformException(error);
    expect(mapped, isA<ICloudItemNotDownloadedException>());
  });

  test('maps details.category coordination to typed exception', () {
    final error = const PlatformException(
      code: 'E_COORDINATION',
      message: 'Coordination failed',
      details: {
        'category': 'coordination',
        'operation': 'delete',
        'retryable': true,
      },
    );

    final mapped = mapICloudPlatformException(error);
    expect(mapped, isA<ICloudCoordinationException>());
  });
}
```

```dart
test('maps invokeMethod PlatformException to typed exception', () async {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (methodCall) async {
    throw const PlatformException(
      code: 'E_CTR',
      message: 'Container unavailable',
      details: {
        'category': 'containerAccess',
        'operation': 'getContainerPath',
        'retryable': false,
      },
    );
  });

  expect(
    () => platform.getContainerPath(containerId: containerId),
    throwsA(isA<ICloudContainerAccessException>()),
  );
});
```

- [ ] **Step 2: Run the exception tests and verify they fail**

Run: `flutter test test/models/exceptions_test.dart test/icloud_storage_method_channel_test.dart -r expanded`

Expected: FAIL because the typed exceptions and mapper do not exist.

- [ ] **Step 3: Add the typed exception hierarchy and method-channel wrapper**

```dart
// lib/models/exceptions.dart
class PlatformExceptionCode {
  static const String iCloudConnectionOrPermission = 'E_CTR';
  static const String conflict = 'E_CONFLICT';
  static const String itemNotDownloaded = 'E_NOT_DOWNLOADED';
  static const String downloadInProgress = 'E_DOWNLOAD_IN_PROGRESS';
  static const String coordination = 'E_COORDINATION';
  static const String timeout = 'E_TIMEOUT';
  static const String nativeCodeError = 'E_NAT';
}

class ICloudOperationException implements Exception {
  const ICloudOperationException({
    required this.category,
    required this.operation,
    required this.retryable,
    required this.message,
    this.relativePath,
    this.nativeDomain,
    this.nativeCode,
    this.nativeDescription,
    this.underlying,
  });

  final String category;
  final String operation;
  final bool retryable;
  final String message;
  final String? relativePath;
  final String? nativeDomain;
  final int? nativeCode;
  final String? nativeDescription;
  final Object? underlying;
}

class ICloudConflictException extends ICloudOperationException {
  const ICloudConflictException({
    required super.operation,
    required super.retryable,
    required super.message,
    super.relativePath,
    super.nativeDomain,
    super.nativeCode,
    super.nativeDescription,
    super.underlying,
  }) : super(category: 'conflict');
}

class ICloudItemNotDownloadedException extends ICloudOperationException {
  const ICloudItemNotDownloadedException({
    required super.operation,
    required super.retryable,
    required super.message,
    super.relativePath,
    super.nativeDomain,
    super.nativeCode,
    super.nativeDescription,
    super.underlying,
  }) : super(category: 'itemNotDownloaded');
}

class ICloudDownloadInProgressException extends ICloudOperationException {
  const ICloudDownloadInProgressException({
    required super.operation,
    required super.retryable,
    required super.message,
    super.relativePath,
    super.nativeDomain,
    super.nativeCode,
    super.nativeDescription,
    super.underlying,
  }) : super(category: 'downloadInProgress');
}

class ICloudCoordinationException extends ICloudOperationException {
  const ICloudCoordinationException({
    required super.operation,
    required super.retryable,
    required super.message,
    super.relativePath,
    super.nativeDomain,
    super.nativeCode,
    super.nativeDescription,
    super.underlying,
  }) : super(category: 'coordination');
}

Exception mapICloudPlatformException(PlatformException error) {
  final details = (error.details is Map)
      ? (error.details as Map).cast<Object?, Object?>()
      : const <Object?, Object?>{};
  final category = details['category'] as String?;
  final operation = (details['operation'] as String?) ?? 'unknown';
  final retryable = (details['retryable'] as bool?) ?? false;
  final message = error.message ?? 'Native operation failed';

  switch (category) {
    case 'itemNotFound':
      return ICloudItemNotFoundException(
        operation: operation,
        retryable: retryable,
        message: message,
      );
    case 'containerAccess':
      return ICloudContainerAccessException(
        operation: operation,
        retryable: retryable,
        message: message,
      );
    case 'conflict':
      return ICloudConflictException(
        operation: operation,
        retryable: retryable,
        message: message,
      );
    case 'itemNotDownloaded':
      return ICloudItemNotDownloadedException(
        operation: operation,
        retryable: retryable,
        message: message,
      );
    case 'downloadInProgress':
      return ICloudDownloadInProgressException(
        operation: operation,
        retryable: retryable,
        message: message,
      );
    case 'timeout':
      return ICloudTimeoutException(
        operation: operation,
        retryable: retryable,
        message: message,
      );
    case 'coordination':
      return ICloudCoordinationException(
        operation: operation,
        retryable: retryable,
        message: message,
      );
    default:
      return ICloudUnknownNativeException(
        operation: operation,
        retryable: retryable,
        message: message,
      );
  }
}
```

```dart
// lib/icloud_storage_method_channel.dart
Future<T?> _invokeTypedMethod<T>(
  String method,
  Map<String, Object?> arguments,
) async {
  try {
    return await methodChannel.invokeMethod<T>(method, arguments);
  } on PlatformException catch (error) {
    throw mapICloudPlatformException(error);
  }
}

Future<List<dynamic>?> _invokeTypedListMethod(
  String method,
  Map<String, Object?> arguments,
) async {
  try {
    return await methodChannel.invokeListMethod<dynamic>(method, arguments);
  } on PlatformException catch (error) {
    throw mapICloudPlatformException(error);
  }
}
```

```dart
// Apply the helpers to request/response APIs only.
// Keep _receiveTransferProgressStream unchanged so stream error payloads remain
// PlatformException-based in this slice.
```

- [ ] **Step 4: Run the Dart contract tests again**

Run: `flutter test test/models/exceptions_test.dart test/icloud_storage_method_channel_test.dart -r expanded`

Expected: PASS

- [ ] **Step 5: Commit the typed exception layer**

```bash
git add lib/models/exceptions.dart lib/icloud_storage_method_channel.dart test/models/exceptions_test.dart test/icloud_storage_method_channel_test.dart
git commit -m "feat: add typed iCloud exception mapping"
```

### Task 4: Implement Structured Metadata And Error Transport On iOS

**Files:**
- Modify: `ios/icloud_storage_plus/Sources/icloud_storage_plus/iOSICloudStoragePlugin.swift`
- Modify: `ios/icloud_storage_plus/Sources/icloud_storage_plus/CoordinatedReplaceWriter.swift`
- Modify: `ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/CoordinatedReplaceWriter.swift`
- Modify: `ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/Tests/icloud_storage_plus_foundationTests/CoordinatedReplaceWriterTests.swift`

- [ ] **Step 1: Write the failing method-channel tests for the new native contract**

```dart
test('getItemMetadata returns normalized status values', () async {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (methodCall) async {
    if (methodCall.method == 'getItemMetadata') {
      return {
        'relativePath': 'meta.txt',
        'downloadStatus': 'current',
        'hasUnresolvedConflicts': false,
      };
    }
    return null;
  });

  final metadata = await platform.getItemMetadata(
    containerId: containerId,
    relativePath: 'meta.txt',
  );
  expect(metadata?['downloadStatus'], 'current');
});

test('writeInPlace maps structured conflict payloads to typed exceptions', () async {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (methodCall) async {
    throw const PlatformException(
      code: 'E_CONFLICT',
      message: 'Cannot replace item with unresolved conflicts',
      details: {
        'category': 'conflict',
        'operation': 'writeInPlace',
        'retryable': false,
        'relativePath': 'Documents/test.json',
      },
    );
  });

  expect(
    () => platform.writeInPlace(
      containerId: containerId,
      relativePath: 'Documents/test.json',
      contents: '{}',
    ),
    throwsA(isA<ICloudConflictException>()),
  );
});
```

```swift
func testOverwriteExistingItemThrowsWhenDestinationDownloadIsInProgress() {
    let destinationURL = URL(fileURLWithPath: "/tmp/file.json")

    let writer = CoordinatedReplaceWriter(
        fileExists: { _ in true },
        verifyDestinationState: { _ in
            throw NSError(
                domain: "ICloudStoragePlusErrorDomain",
                code: 3,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Cannot replace an iCloud item while its download is in progress.",
                ]
            )
        },
        createReplacementDirectory: { _ in URL(fileURLWithPath: "/tmp/replacement") },
        coordinateReplace: { _, _ in },
        replaceItem: { _, _ in },
        removeItem: { _ in }
    )

    XCTAssertThrowsError(
        try writer.overwriteExistingItem(at: destinationURL) { _ in }
    ) { error in
        XCTAssertEqual((error as NSError).code, 3)
    }
}
```

- [ ] **Step 2: Run the focused method-channel tests**

Run:
- `flutter test test/icloud_storage_method_channel_test.dart -r expanded`
- `swift test` (workdir: `ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation`)

Expected: FAIL until the method-channel layer and native replace-state contract are aligned.

- [ ] **Step 3: Add `getItemMetadata` and structured FlutterError details on iOS**

```swift
// iOSICloudStoragePlugin.swift
private func flutterError(
  code: String,
  message: String,
  category: String,
  operation: String,
  retryable: Bool,
  relativePath: String? = nil,
  error: NSError? = nil
) -> FlutterError {
  var details: [String: Any] = [
    "category": category,
    "operation": operation,
    "retryable": retryable,
  ]
  if let relativePath { details["relativePath"] = relativePath }
  if let error {
    details["nativeDomain"] = error.domain
    details["nativeCode"] = error.code
    details["nativeDescription"] = error.localizedDescription
  }
  return FlutterError(code: code, message: message, details: details)
}
```

```swift
private func getItemMetadata(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
  guard let args = call.arguments as? Dictionary<String, Any>,
        let containerId = args["containerId"] as? String,
        let relativePath = args["relativePath"] as? String else {
    result(argumentError)
    return
  }

  guard let containerURL = FileManager.default.url(
    forUbiquityContainerIdentifier: containerId
  ) else {
    result(containerAccessError(operation: "getItemMetadata"))
    return
  }

  let fileURL = containerURL.appendingPathComponent(relativePath)
  guard FileManager.default.fileExists(atPath: fileURL.path) else {
    result(nil)
    return
  }

  do {
    let values = try fileURL.resourceValues(forKeys: [
      .isDirectoryKey,
      .fileSizeKey,
      .creationDateKey,
      .contentModificationDateKey,
      .ubiquitousItemDownloadingStatusKey,
      .ubiquitousItemIsDownloadingKey,
      .ubiquitousItemIsUploadedKey,
      .ubiquitousItemIsUploadingKey,
      .ubiquitousItemHasUnresolvedConflictsKey,
    ])
    let containerPath = containerURL.standardizedFileURL.path
    var map = mapResourceValues(
      fileURL: fileURL,
      values: values,
      containerPath: containerPath
    )
    map["downloadStatus"] = normalizeDownloadStatus(
      values.ubiquitousItemDownloadingStatus
    )
    result(map)
  } catch {
    result(nativeCodeError(error, operation: "getItemMetadata", relativePath: relativePath))
  }
}
```

```swift
switch call.method {
case "getItemMetadata":
  getItemMetadata(call, result)
case "getDocumentMetadata":
  getDocumentMetadata(call, result)
case "getContainerPath":
  getContainerPath(call, result)
default:
  result(FlutterMethodNotImplemented)
}

private func nativeCodeError(
  _ error: Error,
  operation: String,
  relativePath: String? = nil
) -> FlutterError {
  let nsError = error as NSError

  if let timeout = mapTimeoutError(error, operation: operation, relativePath: relativePath) {
    return timeout
  }
  if let fileNotFound = mapFileNotFoundError(error, operation: operation, relativePath: relativePath) {
    return fileNotFound
  }
  if let replaceState = mapReplaceStateError(error, operation: operation, relativePath: relativePath) {
    return replaceState
  }

  return flutterError(
    code: "E_NAT",
    message: "Native Code Error",
    category: "unknownNative",
    operation: operation,
    retryable: false,
    relativePath: relativePath,
    error: nsError
  )
}

private func mapReplaceStateError(
  _ error: Error,
  operation: String,
  relativePath: String?
) -> FlutterError? {
  let nsError = error as NSError
  guard nsError.domain == "ICloudStoragePlusErrorDomain" else { return nil }

  switch nsError.code {
  case 1:
    return flutterError(
      code: "E_CONFLICT",
      message: nsError.localizedDescription,
      category: "conflict",
      operation: operation,
      retryable: false,
      relativePath: relativePath,
      error: nsError
    )
  case 2:
    return flutterError(
      code: "E_NOT_DOWNLOADED",
      message: nsError.localizedDescription,
      category: "itemNotDownloaded",
      operation: operation,
      retryable: true,
      relativePath: relativePath,
      error: nsError
    )
  case 3:
    return flutterError(
      code: "E_DOWNLOAD_IN_PROGRESS",
      message: nsError.localizedDescription,
      category: "downloadInProgress",
      operation: operation,
      retryable: true,
      relativePath: relativePath,
      error: nsError
    )
  default:
    return nil
  }
}
```

```swift
// CoordinatedReplaceWriter.swift
if values.ubiquitousItemIsDownloading == true {
    throw NSError(
        domain: "ICloudStoragePlusErrorDomain",
        code: 3,
        userInfo: [
            NSLocalizedDescriptionKey:
                "Cannot replace an iCloud item while its download is in progress.",
        ]
    )
}

if downloadStatus == .notDownloaded {
    throw NSError(
        domain: "ICloudStoragePlusErrorDomain",
        code: 2,
        userInfo: [
            NSLocalizedDescriptionKey:
                "Cannot replace a nonlocal iCloud item until it is fully downloaded.",
        ]
    )
}
```

- [ ] **Step 4: Run iOS-focused verification**

Run:
- `flutter test test/icloud_storage_method_channel_test.dart -r expanded`
- `swift test` (workdir: `ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation`)
- `flutter build ios --simulator --no-codesign`

Expected: PASS

- [ ] **Step 5: Commit the iOS native transport changes**

```bash
git add ios/icloud_storage_plus/Sources/icloud_storage_plus/iOSICloudStoragePlugin.swift ios/icloud_storage_plus/Sources/icloud_storage_plus/CoordinatedReplaceWriter.swift ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/CoordinatedReplaceWriter.swift ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/Tests/icloud_storage_plus_foundationTests/CoordinatedReplaceWriterTests.swift lib/icloud_storage_method_channel.dart test/icloud_storage_method_channel_test.dart
git commit -m "feat(ios): add structured iCloud error transport"
```

### Task 5: Mirror The Native Contract On macOS

**Files:**
- Modify: `macos/icloud_storage_plus/Sources/icloud_storage_plus/macOSICloudStoragePlugin.swift`
- Modify: `macos/icloud_storage_plus/Sources/icloud_storage_plus/CoordinatedReplaceWriter.swift`
- Modify: `macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation/CoordinatedReplaceWriter.swift`
- Modify: `macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation/Tests/icloud_storage_plus_foundationTests/CoordinatedReplaceWriterTests.swift`
- Modify: `lib/icloud_storage_method_channel.dart`
- Modify: `test/icloud_storage_method_channel_test.dart`

- [ ] **Step 1: Add the failing macOS-focused method-channel expectations**

```dart
test('readInPlace maps timeout payloads to ICloudTimeoutException', () async {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (methodCall) async {
    if (methodCall.method == 'readInPlace') {
      throw const PlatformException(
        code: 'E_TIMEOUT',
        message: 'Timed out',
        details: {
          'category': 'timeout',
          'operation': 'readInPlace',
          'retryable': true,
        },
      );
    }
    return null;
  });

  expect(
    () => platform.readInPlace(
      containerId: containerId,
      relativePath: 'Documents/data.json',
    ),
    throwsA(isA<ICloudTimeoutException>()),
  );
});
```

```swift
func testOverwriteExistingItemThrowsWhenDestinationDownloadIsInProgress() {
    let destinationURL = URL(fileURLWithPath: "/tmp/file.json")

    let writer = CoordinatedReplaceWriter(
        fileExists: { _ in true },
        verifyDestinationState: { _ in
            throw NSError(
                domain: "ICloudStoragePlusErrorDomain",
                code: 3,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Cannot replace an iCloud item while its download is in progress.",
                ]
            )
        },
        createReplacementDirectory: { _ in URL(fileURLWithPath: "/tmp/replacement") },
        coordinateReplace: { _, _ in },
        replaceItem: { _, _ in },
        removeItem: { _ in }
    )

    XCTAssertThrowsError(
        try writer.overwriteExistingItem(at: destinationURL) { _ in }
    ) { error in
        XCTAssertEqual((error as NSError).code, 3)
    }
}
```

- [ ] **Step 2: Run the method-channel tests and verify the new macOS contract is still failing**

Run:
- `flutter test test/icloud_storage_method_channel_test.dart -r expanded`
- `swift test` (workdir: `macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation`)

Expected: FAIL until the macOS native side emits the structured payloads consistently.

- [ ] **Step 3: Add `getItemMetadata` and structured FlutterError details on macOS**

```swift
private func getItemMetadata(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
  guard let args = call.arguments as? Dictionary<String, Any>,
        let containerId = args["containerId"] as? String,
        let relativePath = args["relativePath"] as? String else {
    result(argumentError)
    return
  }

  guard let containerURL = FileManager.default.url(
    forUbiquityContainerIdentifier: containerId
  ) else {
    result(containerAccessError(operation: "getItemMetadata"))
    return
  }

  let fileURL = containerURL.appendingPathComponent(relativePath)
  guard FileManager.default.fileExists(atPath: fileURL.path) else {
    result(nil)
    return
  }

  do {
    let values = try fileURL.resourceValues(forKeys: [
      .isDirectoryKey,
      .fileSizeKey,
      .creationDateKey,
      .contentModificationDateKey,
      .ubiquitousItemDownloadingStatusKey,
      .ubiquitousItemIsDownloadingKey,
      .ubiquitousItemIsUploadedKey,
      .ubiquitousItemIsUploadingKey,
      .ubiquitousItemHasUnresolvedConflictsKey,
    ])
    var map = mapResourceValues(
      fileURL: fileURL,
      values: values,
      containerPath: containerURL.standardizedFileURL.path
    )
    map["downloadStatus"] = normalizeDownloadStatus(
      values.ubiquitousItemDownloadingStatus
    )
    result(map)
  } catch {
    result(nativeCodeError(error, operation: "getItemMetadata", relativePath: relativePath))
  }
}

private func mapReplaceStateError(
  _ error: Error,
  operation: String,
  relativePath: String?
) -> FlutterError? {
  let nsError = error as NSError
  guard nsError.domain == "ICloudStoragePlusErrorDomain" else { return nil }

  switch nsError.code {
  case 1:
    return flutterError(
      code: "E_CONFLICT",
      message: nsError.localizedDescription,
      category: "conflict",
      operation: operation,
      retryable: false,
      relativePath: relativePath,
      error: nsError
    )
  case 2:
    return flutterError(
      code: "E_NOT_DOWNLOADED",
      message: nsError.localizedDescription,
      category: "itemNotDownloaded",
      operation: operation,
      retryable: true,
      relativePath: relativePath,
      error: nsError
    )
  case 3:
    return flutterError(
      code: "E_DOWNLOAD_IN_PROGRESS",
      message: nsError.localizedDescription,
      category: "downloadInProgress",
      operation: operation,
      retryable: true,
      relativePath: relativePath,
      error: nsError
    )
  default:
    return nil
  }
}

private func nativeCodeError(
  _ error: Error,
  operation: String,
  relativePath: String? = nil
) -> FlutterError {
  let nsError = error as NSError

  if let timeout = mapTimeoutError(error, operation: operation, relativePath: relativePath) {
    return timeout
  }
  if let fileNotFound = mapFileNotFoundError(error, operation: operation, relativePath: relativePath) {
    return fileNotFound
  }
  if let replaceState = mapReplaceStateError(error, operation: operation, relativePath: relativePath) {
    return replaceState
  }

  return flutterError(
    code: "E_NAT",
    message: "Native Code Error",
    category: "unknownNative",
    operation: operation,
    retryable: false,
    relativePath: relativePath,
    error: nsError
  )
}
```

```swift
// CoordinatedReplaceWriter.swift
if values.ubiquitousItemIsDownloading == true {
    throw NSError(
        domain: "ICloudStoragePlusErrorDomain",
        code: 3,
        userInfo: [
            NSLocalizedDescriptionKey:
                "Cannot replace an iCloud item while its download is in progress.",
        ]
    )
}

if downloadStatus == .notDownloaded {
    throw NSError(
        domain: "ICloudStoragePlusErrorDomain",
        code: 2,
        userInfo: [
            NSLocalizedDescriptionKey:
                "Cannot replace a nonlocal iCloud item until it is fully downloaded.",
        ]
    )
}
```

- [ ] **Step 4: Run macOS verification**

Run:
- `flutter test test/icloud_storage_method_channel_test.dart -r expanded`
- `swift test` (workdir: `macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation`)
- `xcodebuild -project example/macos/Runner.xcodeproj -scheme Runner -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build`

Expected: PASS

- [ ] **Step 5: Commit the macOS transport changes**

```bash
git add macos/icloud_storage_plus/Sources/icloud_storage_plus/macOSICloudStoragePlugin.swift macos/icloud_storage_plus/Sources/icloud_storage_plus/CoordinatedReplaceWriter.swift macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation/CoordinatedReplaceWriter.swift macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation/Tests/icloud_storage_plus_foundationTests/CoordinatedReplaceWriterTests.swift lib/icloud_storage_method_channel.dart test/icloud_storage_method_channel_test.dart
git commit -m "feat(macos): add structured iCloud error transport"
```

### Task 6: Update Docs, Example, Versioning, And Final Verification

**Files:**
- Modify: `README.md`
- Modify: `CHANGELOG.md`
- Modify: `pubspec.yaml`
- Modify: `example/lib/utils.dart`
- Modify: `lib/icloud_storage.dart`
- Modify: `lib/icloud_storage_platform_interface.dart`
- Modify: `test/icloud_storage_test.dart`
- Modify: `test/icloud_storage_method_channel_test.dart`

- [ ] **Step 1: Write the failing doc/example cleanup assertions as test edits**

```dart
test('getItemMetadata accepts trailing slash and returns typed metadata', () async {
  await ICloudStorage.getItemMetadata(
    containerId: containerId,
    relativePath: 'Documents/folder/',
  );
  expect(fakePlatform.calls.last, 'getItemMetadata');
});

test('progress stream errors remain PlatformException-based', () async {
  mockStreamHandler = MockStreamHandler.inline(
    onListen: (arguments, events) {
      events.error(code: 'E_TEST', message: 'Boom', details: 'details');
    },
  );

  late Stream<ICloudTransferProgress> progressStream;
  await platform.uploadFile(
    containerId: containerId,
    localPath: '/tmp/file',
    cloudRelativePath: 'Documents/file',
    onProgress: (stream) => progressStream = stream,
  );

  final events = await progressStream.toList();
  expect(events.single.exception, isA<PlatformException>());
});
```

- [ ] **Step 2: Run the full Dart suite and verify any remaining breakages**

Run: `flutter test -r expanded`

Expected: FAIL anywhere the old `getMetadata` / `PlatformExceptionCode` contract is still referenced.

- [ ] **Step 3: Update the public docs, example, and release notes**

```yaml
# pubspec.yaml
version: 2.0.0
```

```markdown
<!-- README.md -->
- Replace `ICloudStorage.getMetadata(...)` with `ICloudStorage.getItemMetadata(...)`
- Document `ICloudItemMetadata` separately from `ICloudFile`
- Document typed exceptions for request/response APIs
- Keep progress stream examples on `PlatformException`
```

```dart
// example/lib/utils.dart
String getErrorMessage(dynamic ex) {
  if (ex is ICloudContainerAccessException) {
    return 'Container access failed: ${ex.message}';
  }
  if (ex is ICloudOperationException) {
    return '${ex.runtimeType}: ${ex.message}';
  }
  if (ex is PlatformException) {
    return 'Platform Exception: ${ex.message}; Details: ${ex.details}';
  }
  return ex.toString();
}
```

```dart
// lib/icloud_storage.dart / lib/icloud_storage_platform_interface.dart
/// Get the absolute path to the iCloud container.
///
/// This remains nullable at the type level for platform compatibility, but the
/// current Darwin implementations throw `ICloudContainerAccessException` when
/// container lookup fails.

/// [idleTimeouts] controls idle watchdog timeouts between retries.
/// [retryBackoff] controls retry delays between attempts.
///
/// The existence of both controls is part of the contract. Exact default
/// timeout/backoff schedules remain implementation details.
```

```markdown
<!-- CHANGELOG.md -->
## [2.0.0]

### Breaking
- Remove `getMetadata()` in favor of `getItemMetadata()`.
- Add `ICloudItemMetadata` as the typed known-path metadata model.
- Request/response APIs now throw typed iCloud exceptions backed by structured
  native error payloads.

### Unchanged
- Transfer-progress stream error events remain `PlatformException`-based.
```

- [ ] **Step 4: Run the full repo verification**

Run:
- `flutter analyze`
- `flutter test`
- `swift test` (workdir: `ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation`)
- `swift test` (workdir: `macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation`)
- `flutter build ios --simulator --no-codesign` (workdir: `example/`)
- `xcodebuild -project example/macos/Runner.xcodeproj -scheme Runner -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build`

Expected: PASS

- [ ] **Step 5: Commit the release-facing cleanup**

```bash
git add README.md CHANGELOG.md pubspec.yaml example/lib/utils.dart lib/icloud_storage.dart lib/icloud_storage_platform_interface.dart test/icloud_storage_test.dart test/icloud_storage_method_channel_test.dart
git commit -m "feat: ship iCloud API hardening release"
```
