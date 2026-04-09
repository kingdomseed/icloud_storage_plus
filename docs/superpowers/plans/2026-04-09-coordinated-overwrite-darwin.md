# Coordinated Overwrite Darwin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace existing-file overwrite behavior on iOS and macOS with coordinated atomic replacement while preserving create-path behavior and the public Dart API.

**Architecture:** Add a small Foundation-level overwrite helper in each Darwin package that detects existing destinations, stages replacement data into an item-replacement temp location, coordinates a `.forReplacing` write, calls `FileManager.replaceItemAt(...)`, and cleans up temp artifacts. Keep new-file creation on the current document-based path, and update the Dart API docs so they describe coordinated access accurately without claiming overwrite is handled only by `UIDocument` or `NSDocument` internals.

**Tech Stack:** Flutter plugin, Dart tests, Swift Package Manager, XCTest, Foundation, UIKit/AppKit, `NSFileCoordinator`, `FileManager.replaceItemAt(...)`

## Status Update: 2026-04-09

Completed on this branch:

- Added `CoordinatedReplaceWriter` and file-write helper seams on iOS and macOS.
- Routed existing-file `writeDocument`, `writeInPlaceDocument`, and
  `writeInPlaceBinaryDocument` through coordinated atomic replacement on both
  Darwin platforms.
- Added a follow-up helper path so existing-destination `copy()` also uses
  coordinated atomic replacement on both Darwin platforms.
- Added standalone Foundation Swift packages on iOS and macOS for helper-level
  XCTest coverage.
- Helper XCTest coverage verifies replacement orchestration and preflight
  contract behavior; live iCloud conflict/download integration still relies on
  manual validation.
- Updated public Dart docs to describe Darwin overwrite behavior accurately.

Fresh verification completed:

- `swift test` in both Darwin Foundation helper packages
- `flutter test`
- `flutter analyze`
- macOS example debug build via `xcodebuild`
- iOS simulator build via `flutter build ios --simulator --no-codesign`

Remaining follow-ups:

- Run targeted manual iCloud validation on real Darwin environments.
- Keep changelog and repo docs aligned with the shipped Darwin behavior.

---

### Task 1: Add Native Test Seams for Coordinated Overwrite

**Files:**
- Modify: `ios/icloud_storage_plus/Package.swift`
- Create: `ios/icloud_storage_plus/Tests/icloud_storage_plusTests/CoordinatedReplaceWriterTests.swift`
- Modify: `macos/icloud_storage_plus/Package.swift`
- Create: `macos/icloud_storage_plus/Tests/icloud_storage_plusTests/CoordinatedReplaceWriterTests.swift`

- [x] **Step 1: Add Swift test targets to both native packages**

```swift
// ios/icloud_storage_plus/Package.swift and macos/icloud_storage_plus/Package.swift
targets: [
    .target(
        name: "icloud_storage_plus",
        dependencies: [],
        resources: [],
        cSettings: [
            .headerSearchPath("include/icloud_storage_plus"),
        ]
    ),
    .testTarget(
        name: "icloud_storage_plusTests",
        dependencies: ["icloud_storage_plus"]
    ),
]
```

- [x] **Step 2: Write the failing iOS helper tests**

```swift
import XCTest
@testable import icloud_storage_plus

final class CoordinatedReplaceWriterTests: XCTestCase {
    func testOverwriteExistingItemReturnsFalseWhenDestinationDoesNotExist() throws {
        var preparedReplacement = false

        let writer = CoordinatedReplaceWriter(
            fileExists: { _ in false },
            createReplacementDirectory: { _ in XCTFail("should not create replacement directory"); return URL(fileURLWithPath: "/tmp") },
            coordinateReplace: { _, _ in XCTFail("should not coordinate replace") },
            replaceItem: { _, _ in XCTFail("should not replace item") },
            removeItem: { _ in }
        )

        let handled = try writer.overwriteExistingItem(
            at: URL(fileURLWithPath: "/tmp/file.json")
        ) { _ in
            preparedReplacement = true
        }

        XCTAssertFalse(handled)
        XCTAssertFalse(preparedReplacement)
    }

    func testOverwriteExistingItemCleansUpReplacementArtifactWhenReplaceFails() {
        let destinationURL = URL(fileURLWithPath: "/tmp/file.json")
        let replacementDirectory = URL(fileURLWithPath: "/tmp/replacement")
        let expectedError = NSError(domain: NSCocoaErrorDomain, code: 512)
        var cleanedURL: URL?

        let writer = CoordinatedReplaceWriter(
            fileExists: { _ in true },
            createReplacementDirectory: { _ in replacementDirectory },
            coordinateReplace: { url, accessor in try accessor(url) },
            replaceItem: { _, _ in throw expectedError },
            removeItem: { cleanedURL = $0 }
        )

        XCTAssertThrowsError(
            try writer.overwriteExistingItem(at: destinationURL) { url in
                XCTAssertEqual(url.deletingLastPathComponent(), replacementDirectory)
            }
        ) { error in
            XCTAssertEqual((error as NSError).code, expectedError.code)
        }

        XCTAssertNotNil(cleanedURL)
    }
}
```

- [x] **Step 3: Copy the same failing tests to macOS**

```swift
// macos/icloud_storage_plus/Tests/icloud_storage_plusTests/CoordinatedReplaceWriterTests.swift
// Same test body as the iOS version.
```

- [x] **Step 4: Run native tests to verify RED**

Run:
`swift test --package-path ios/icloud_storage_plus && swift test --package-path macos/icloud_storage_plus`

Expected:
- Both packages fail because `CoordinatedReplaceWriter` does not exist yet.

### Task 2: Implement the Shared Overwrite Orchestration Helper in iOS

**Files:**
- Create: `ios/icloud_storage_plus/Sources/icloud_storage_plus/CoordinatedReplaceWriter.swift`
- Modify: `ios/icloud_storage_plus/Sources/icloud_storage_plus/ICloudDocument.swift`

- [x] **Step 1: Add the failing helper type in iOS**

```swift
import Foundation

struct CoordinatedReplaceWriter {
    typealias CoordinateReplace = (URL, (URL) throws -> Void) throws -> Void
    typealias ReplaceItem = (URL, URL) throws -> Void
    typealias RemoveItem = (URL) throws -> Void
    typealias CreateReplacementDirectory = (URL) throws -> URL
    typealias FileExists = (String) -> Bool

    var fileExists: FileExists
    var createReplacementDirectory: CreateReplacementDirectory
    var coordinateReplace: CoordinateReplace
    var replaceItem: ReplaceItem
    var removeItem: RemoveItem

    func overwriteExistingItem(
        at destinationURL: URL,
        prepareReplacementFile: (URL) throws -> Void
    ) throws -> Bool {
        fatalError("implement in Step 2")
    }
}
```

- [x] **Step 2: Implement minimal helper behavior to pass the tests**

```swift
func overwriteExistingItem(
    at destinationURL: URL,
    prepareReplacementFile: (URL) throws -> Void
) throws -> Bool {
    guard fileExists(destinationURL.path) else {
        return false
    }

    let replacementDirectory = try createReplacementDirectory(destinationURL)
    let replacementURL = replacementDirectory
        .appendingPathComponent(destinationURL.lastPathComponent)
    var cleanupError: Error?

    defer {
        do {
            try removeItem(replacementDirectory)
        } catch {
            cleanupError = error
        }
    }

    try prepareReplacementFile(replacementURL)
    try coordinateReplace(destinationURL) { coordinatedURL in
        try replaceItem(coordinatedURL, replacementURL)
    }

    if let cleanupError {
        throw cleanupError
    }

    return true
}
```

- [x] **Step 3: Add the production iOS helper factory**

```swift
extension CoordinatedReplaceWriter {
    static let live = CoordinatedReplaceWriter(
        fileExists: { FileManager.default.fileExists(atPath: $0) },
        createReplacementDirectory: { destinationURL in
            try FileManager.default.url(
                for: .itemReplacementDirectory,
                in: .userDomainMask,
                appropriateFor: destinationURL,
                create: true
            )
        },
        coordinateReplace: { destinationURL, accessor in
            let coordinator = NSFileCoordinator(filePresenter: nil)
            var coordinationError: NSError?
            var accessError: Error?

            coordinator.coordinate(
                writingItemAt: destinationURL,
                options: .forReplacing,
                error: &coordinationError
            ) { coordinatedURL in
                do {
                    try accessor(coordinatedURL)
                } catch {
                    accessError = error
                }
            }

            if let coordinationError {
                throw coordinationError
            }

            if let accessError {
                throw accessError
            }
        },
        replaceItem: { destinationURL, replacementURL in
            _ = try FileManager.default.replaceItemAt(
                destinationURL,
                withItemAt: replacementURL
            )
        },
        removeItem: { url in
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
    )
}
```

- [x] **Step 4: Run iOS native tests to verify GREEN**

Run:
`swift test --package-path ios/icloud_storage_plus`

Expected:
- iOS package tests pass.

### Task 3: Route iOS Existing-File Writes Through the Helper

**Files:**
- Modify: `ios/icloud_storage_plus/Sources/icloud_storage_plus/ICloudDocument.swift`

- [x] **Step 1: Add a small staging helper for in-memory and file-backed payloads**

```swift
private func writeText(_ contents: String, to url: URL) throws {
    try contents.write(to: url, atomically: true, encoding: .utf8)
}

private func writeData(_ contents: Data, to url: URL) throws {
    try contents.write(to: url, options: .atomic)
}
```

- [x] **Step 2: Update `writeDocument` to use coordinated replace for existing files**

```swift
func writeDocument(
    at url: URL,
    sourceURL: URL,
    completion: @escaping (Error?) -> Void
) {
    do {
        let handled = try CoordinatedReplaceWriter.live.overwriteExistingItem(at: url) {
            try self.streamCopy(from: sourceURL, to: $0)
        }

        if handled {
            completion(nil)
            return
        }
    } catch {
        completion(error)
        return
    }

    let document = ICloudDocument(fileURL: url)
    document.sourceURL = sourceURL
    document.save(to: url, for: .forCreating) { success in
        // keep current success/error handling
    }
}
```

- [x] **Step 3: Update `writeInPlaceDocument` and `writeInPlaceBinaryDocument` the same way**

```swift
let handled = try CoordinatedReplaceWriter.live.overwriteExistingItem(at: url) {
    try self.writeText(contents, to: $0)
}

let handled = try CoordinatedReplaceWriter.live.overwriteExistingItem(at: url) {
    try self.writeData(contents, to: $0)
}
```

- [x] **Step 4: Run iOS package tests again**

Run:
`swift test --package-path ios/icloud_storage_plus`

Expected:
- iOS package tests stay green.

### Task 4: Mirror the Same Overwrite Helper on macOS

**Files:**
- Create: `macos/icloud_storage_plus/Sources/icloud_storage_plus/CoordinatedReplaceWriter.swift`
- Modify: `macos/icloud_storage_plus/Sources/icloud_storage_plus/ICloudDocument.swift`

- [x] **Step 1: Copy the helper implementation into the macOS package**

```swift
// macOS helper matches the iOS helper API and behavior.
```

- [x] **Step 2: Route macOS existing-file `writeDocument`, `writeInPlaceDocument`, and `writeInPlaceBinaryDocument` through the helper**

```swift
let handled = try CoordinatedReplaceWriter.live.overwriteExistingItem(at: url) {
    try self.streamCopy(from: sourceURL, to: $0)
}

let handled = try CoordinatedReplaceWriter.live.overwriteExistingItem(at: url) {
    try self.writeText(contents, to: $0)
}

let handled = try CoordinatedReplaceWriter.live.overwriteExistingItem(at: url) {
    try self.writeData(contents, to: $0)
}
```

- [x] **Step 3: Run macOS native tests to verify GREEN**

Run:
`swift test --package-path macos/icloud_storage_plus`

Expected:
- macOS package tests pass.

### Task 5: Align Public Dart Docs and Run Full Verification

**Files:**
- Modify: `lib/icloud_storage.dart`
- Modify: `lib/icloud_storage_platform_interface.dart`
- Test: `test/icloud_storage_test.dart`
- Test: `test/icloud_storage_method_channel_test.dart`

- [x] **Step 1: Update public docs to describe coordinated overwrite accurately**

```dart
/// Write a file in place inside the iCloud container using coordinated
/// access.
///
/// On Darwin platforms, existing-file overwrites use coordinated atomic
/// replacement so the user-visible document path stays stable.
/// New-file creation remains on the platform document create path.
```

- [x] **Step 2: Run Dart tests to verify no public API regression**

Run:
`flutter test`

Expected:
- All Dart tests pass.

- [x] **Step 3: Run native package tests together**

Run:
`swift test --package-path ios/icloud_storage_plus && swift test --package-path macos/icloud_storage_plus`

Expected:
- Both native packages pass.

- [x] **Step 4: Run static verification**

Run:
`flutter analyze`

Expected:
- Analysis completes without new errors.
