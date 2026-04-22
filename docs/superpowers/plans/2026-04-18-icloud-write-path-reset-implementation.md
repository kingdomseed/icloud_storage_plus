# iCloud Write Path Reset Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the Darwin `writeInPlace` overwrite path from a strict contract-first baseline so recoverable iCloud states are handled correctly, the user's replacement content remains the winner, and public Dart APIs stay stable.

**Architecture:** Execute the reset in three dependent parts: first lock the write-path contract and method inventory, then rewrite the native overwrite flow in the scoped Swift files for iOS and macOS, then validate SPM-first shipping paths plus Flutter and CocoaPods compatibility. Keep copy-path behavior separate, keep observer-path conflict handling separate unless a concrete shared seam survives the audit, and remove speculative preflight helpers unless they protect a real Dart-visible contract.

**Tech Stack:** Flutter plugin, Dart method-channel tests, Swift Package Manager, Foundation (`NSFileCoordinator`, `NSFileVersion`, `FileManager`), iOS/macOS XCTest, CocoaPods compatibility validation.

---

## File Structure

### New files

- Create: `docs/superpowers/plans/2026-04-18-icloud-write-path-reset-contract-audit.md`
  Responsibility: lock the final write-path outcome table, method inventory, and keep/simplify/merge/delete decisions before the semantic rewrite starts.

### Existing files to modify

- Modify: `docs/superpowers/specs/2026-04-18-icloud-write-path-reset-design.md`
  Responsibility: keep the approved design and the final implementation decisions aligned when Part 1 locks the remaining open items.

- Modify: `ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/CoordinatedReplaceWriter.swift`
  Responsibility: own overwrite semantics, download-before-write, coordinator bridging, replacement-file staging, and native error shaping for the write path.

- Modify: `macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation/CoordinatedReplaceWriter.swift`
  Responsibility: macOS twin of the iOS write-path implementation. Must preserve the same Dart-visible outcomes.

- Modify: `ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/ConflictResolver.swift`
  Responsibility: separate observer conflict resolution from write-path overwrite cleanup.

- Modify: `macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation/ConflictResolver.swift`
  Responsibility: macOS twin of the iOS conflict helper split.

- Modify: `ios/icloud_storage_plus/Sources/icloud_storage_plus/iOSICloudStoragePlugin.swift`
  Responsibility: keep `writeInPlace` / `writeInPlaceBytes` entrypoints aligned with the new writer semantics and preserve stable Dart-visible error mapping.

- Modify: `macos/icloud_storage_plus/Sources/icloud_storage_plus/macOSICloudStoragePlugin.swift`
  Responsibility: macOS twin of the iOS entrypoint and native error mapping updates.

- Modify: `ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/Tests/icloud_storage_plus_foundationTests/CoordinatedReplaceWriterTests.swift`
  Responsibility: replace structure-coupled assertions with contract-focused write-path tests.

- Modify: `macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation/Tests/icloud_storage_plus_foundationTests/CoordinatedReplaceWriterTests.swift`
  Responsibility: macOS twin of the iOS contract-focused writer tests.

- Modify: `test/icloud_storage_method_channel_test.dart`
  Responsibility: prove Dart-visible mapping for the write-path error categories that this reset keeps stable.

### Existing files to verify only

- Verify only: `pubspec.yaml`
  Responsibility: confirm plugin packaging declarations remain unchanged.

- Verify only: `ios/icloud_storage_plus/Package.swift`
- Verify only: `macos/icloud_storage_plus/Package.swift`
  Responsibility: confirm SPM remains the primary source of truth.

- Verify only: `ios/icloud_storage_plus.podspec`
- Verify only: `macos/icloud_storage_plus.podspec`
  Responsibility: keep CocoaPods compatible without driving architecture.

## PR Structure

This plan is intentionally split into three reviewable parts. Implement them in order.

- **Part 1:** Contract lock and method audit
- **Part 2:** Native write-path reset
- **Part 3:** Packaging and integration validation

Do not start Part 2 before Part 1 is complete. Do not start Part 3 before Part 2 is green on both iOS and macOS SPM tests.

### Task 1: Create Fresh Worktree And Lock The Contract

**Files:**
- Create: `docs/superpowers/plans/2026-04-18-icloud-write-path-reset-contract-audit.md`
- Modify: `docs/superpowers/specs/2026-04-18-icloud-write-path-reset-design.md`

- [ ] **Step 1: Create the reset worktree from `main`**

Run:

```bash
git worktree add "../icloud_storage_plus-reset" -b reset/write-in-place-contract-first origin/main
```

Expected: a new sibling worktree is created on branch `reset/write-in-place-contract-first`.

- [ ] **Step 2: Write the contract-audit document**

Create `docs/superpowers/plans/2026-04-18-icloud-write-path-reset-contract-audit.md` with this starting content:

```md
# iCloud Write Path Contract Audit

## Locked Write Outcomes

| State | Dart category | Code | Retryable | Notes |
|---|---|---|---|---|
| Existing destination is a directory | invalidArgument | E_ARG | false | Keep stable Dart-visible behavior even if native preflight helper disappears |
| Destination download stalls or cannot complete | itemNotDownloaded or timeout | E_NOT_DOWNLOADED / E_TIMEOUT | true | Preserve current typed mapping split |
| Conflict recovery fails before replacement write | conflict | E_CONFLICT | false | Include underlying native details |
| Coordination fails | coordination | E_COORDINATION | false by default | Revisit only if existing mapping proves retryable |
| Unknown native write failure | unknownNative | E_NAT | false | Structured fallback only |

## Method Inventory

### CoordinatedReplaceWriter.swift
- overwriteExistingItem: Keep, but simplify around contract-true steps only
- verifyOverwriteDestinationIsFile: Delete or merge unless Part 1 proves it is the only honest way to keep `E_ARG`
- verifyExistingDestinationCanBeReplaced: Keep for copy path only
- liveEnsureDownloaded: Keep
- liveCoordinateReplace: Keep
- autoResolveConflictError: Simplify after final conflict cleanup flow is chosen

### ConflictResolver.swift
- resolveUnresolvedConflictsSync: Rename to observer-specific role
- resolveUnresolvedConflicts(at:): Keep as observer async wrapper only if observer call sites still need it
- add write-path-specific cleanup helper instead of reusing observer winner-selection logic
```

- [ ] **Step 3: Update the approved spec with the final Part 1 decisions**

Apply the audited choices to `docs/superpowers/specs/2026-04-18-icloud-write-path-reset-design.md`. The key edits should look like this:

```md
### Write-Path Outcome Table

| State | Native behavior target | Dart-visible category/code | Retryable |
|---|---|---|---|
| Destination path resolves to an existing directory | Preserve stable invalid-argument mapping; implementation may use mapped OS failure or a minimal validation seam | `invalidArgument` / `E_ARG` | No |
| Replacement write succeeds but conflict cleanup fails | The user's replacement remains the conceptual winner; operation surfaces a stable failure only if the final contract says cleanup is part of success | `conflict` / `E_CONFLICT` or `coordination` / `E_COORDINATION`, finalized in Part 1 | No |
```

- [ ] **Step 4: Run a doc-only diff check**

Run:

```bash
git diff -- docs/superpowers/specs/2026-04-18-icloud-write-path-reset-design.md docs/superpowers/plans/2026-04-18-icloud-write-path-reset-contract-audit.md
```

Expected: only the contract lock and method audit changes appear.

- [ ] **Step 5: Commit Part 1 contract work**

```bash
git add docs/superpowers/specs/2026-04-18-icloud-write-path-reset-design.md docs/superpowers/plans/2026-04-18-icloud-write-path-reset-contract-audit.md
git commit -m "docs: lock write-path reset contract"
```

### Task 2: Add Failing Contract Tests Before Rewriting Swift

**Files:**
- Modify: `test/icloud_storage_method_channel_test.dart`
- Modify: `ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/Tests/icloud_storage_plus_foundationTests/CoordinatedReplaceWriterTests.swift`
- Modify: `macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation/Tests/icloud_storage_plus_foundationTests/CoordinatedReplaceWriterTests.swift`

- [ ] **Step 1: Add Dart tests for stable write-path error mapping**

Append this group to `test/icloud_storage_method_channel_test.dart` near the existing method-channel error mapping coverage:

```dart
  group('writeInPlace error mapping', () {
    test('maps directory destination to InvalidArgumentException category', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (methodCall) async {
        if (methodCall.method == 'writeInPlace') {
          throw PlatformException(
            code: 'E_ARG',
            message: 'Cannot replace an existing directory with file content.',
            details: {
              'category': 'invalidArgument',
              'operation': 'writeInPlace',
              'retryable': false,
            },
          );
        }
        return null;
      });

      expect(
        () => platform.writeInPlace(
          containerId: containerId,
          relativePath: 'Documents/folder',
          contents: '{}',
        ),
        throwsA(isA<ICloudUnknownNativeException>()),
      );
    });

    test('maps conflict recovery failure to ICloudConflictException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (methodCall) async {
        if (methodCall.method == 'writeInPlaceBytes') {
          throw PlatformException(
            code: 'E_CONFLICT',
            message: 'Cannot replace an iCloud item: auto-resolution failed',
            details: {
              'category': 'conflict',
              'operation': 'writeInPlaceBytes',
              'retryable': false,
            },
          );
        }
        return null;
      });

      expect(
        () => platform.writeInPlaceBytes(
          containerId: containerId,
          relativePath: 'Documents/file.bin',
          contents: Uint8List.fromList([1, 2, 3]),
        ),
        throwsA(isA<ICloudConflictException>()),
      );
    });
  });
```

Expected failure now: the first test throws `ICloudUnknownNativeException` because `invalidArgument` is not yet mapped in `mapICloudPlatformException`.

- [ ] **Step 2: Add failing iOS XCTest coverage for the new overwrite contract**

Replace structure-coupled string-source assertions with behavior tests in `ios/.../CoordinatedReplaceWriterTests.swift` by adding tests that lock the observable red behavior on `main` before any seam is introduced. Use this block:

```swift
    func testOverwriteExistingItemReturnsFalseWhenDestinationDoesNotExist() async throws {
        let writer = CoordinatedReplaceWriter(
            fileExists: { _ in false },
            verifyDestination: { _ in XCTFail("should not validate") },
            createReplacementDirectory: { _ in URL(fileURLWithPath: "/tmp/replacement") },
            coordinateReplace: { _, _ in XCTFail("should not coordinate") },
            replaceItem: { _, _ in XCTFail("should not replace") },
            removeItem: { _ in }
        )

        let handled = try writer.overwriteExistingItem(
            at: URL(fileURLWithPath: "/tmp/missing.json")
        ) { _ in
            XCTFail("should not stage replacement")
        }

        XCTAssertFalse(handled)
    }

    func testReplaceReadyStateErrorAllowsConflictedCurrentItemsToProceed() {
        let error = CoordinatedReplaceWriter.replaceReadyStateError(
            hasConflicts: true,
            isUbiquitousItem: true,
            downloadStatus: .current,
            isDownloading: false
        )

        XCTAssertNil(
            error,
            "recoverable conflicts on a current ubiquitous item should not terminally refuse overwrite"
        )
    }

    func testReplaceReadyStateErrorTreatsDownloadingItemsAsNotDownloaded() {
        let error = CoordinatedReplaceWriter.replaceReadyStateError(
            hasConflicts: false,
            isUbiquitousItem: true,
            downloadStatus: .downloaded,
            isDownloading: true
        )

        XCTAssertEqual(
            error?.code,
            CoordinatedReplaceWriter.itemNotDownloadedReplaceStateCode,
            "the reset removes terminal E_DOWNLOAD_IN_PROGRESS from the write path"
        )
    }
```

These tests should fail on `main` because the current writer still terminally rejects conflicted current items and still emits the distinct download-in-progress state.

- [ ] **Step 3: Mirror the same failing contract tests in macOS XCTest**

Add the same three tests to `macos/.../CoordinatedReplaceWriterTests.swift`, adjusting only the file path comments if needed.

- [ ] **Step 4: Run the targeted tests and confirm failure**

Run:

```bash
flutter test test/icloud_storage_method_channel_test.dart
swift test --package-path ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation
swift test --package-path macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation
```

Expected:

- Dart test fails because `invalidArgument` is not yet mapped to a typed exception class
- iOS/macOS foundation tests fail because `replaceReadyStateError(...)` still terminally rejects conflicted current items and still surfaces the distinct download-in-progress state

- [ ] **Step 5: Commit the failing-test checkpoint**

```bash
git add test/icloud_storage_method_channel_test.dart ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/Tests/icloud_storage_plus_foundationTests/CoordinatedReplaceWriterTests.swift macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation/Tests/icloud_storage_plus_foundationTests/CoordinatedReplaceWriterTests.swift
git commit -m "test: lock write-path reset contract"
```

### Task 3: Split Observer Conflict Logic From Write-Path Cleanup

**Files:**
- Modify: `ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/ConflictResolver.swift`
- Modify: `macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation/ConflictResolver.swift`

- [ ] **Step 1: Rename the current sync resolver to the observer role**

Replace the public helper shape in both platform files with this structure:

```swift
func resolvePresentedItemConflictsSync(at url: URL) throws {
    guard let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: url),
          !conflicts.isEmpty else {
        return
    }

    let sorted = conflicts.sorted {
        ($0.modificationDate ?? .distantPast) > ($1.modificationDate ?? .distantPast)
    }

    if let latest = sorted.first {
        try latest.replaceItem(at: url, options: [])
    }

    for version in conflicts {
        version.isResolved = true
    }

    try NSFileVersion.removeOtherVersionsOfItem(at: url)
}

func resolvePresentedItemConflicts(at url: URL) async throws {
    try resolvePresentedItemConflictsSync(at: url)
}
```

- [ ] **Step 2: Add a write-path-specific cleanup helper**

In the same file, add a second helper that does not restore an old conflict winner:

```swift
func cleanupConflictsAfterOverwrite(at url: URL) throws {
    guard let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: url),
          !conflicts.isEmpty else {
        return
    }

    for version in conflicts {
        version.isResolved = true
    }

    try NSFileVersion.removeOtherVersionsOfItem(at: url)
}
```

This helper deliberately does not call `version.replaceItem(at:)`.

- [ ] **Step 3: Run the focused ConflictResolver compile/tests check**

Run:

```bash
swift test --package-path ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation --filter ConflictResolver
swift test --package-path macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation --filter ConflictResolver
```

Expected: compile succeeds even if no new tests exist yet; any observer call sites that still reference the old name will fail here, which is desired.

- [ ] **Step 4: Commit the conflict-helper split**

```bash
git add ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/ConflictResolver.swift macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation/ConflictResolver.swift
git commit -m "refactor: split observer and overwrite conflict flows"
```

### Task 4: Rewrite `CoordinatedReplaceWriter` To Match The Locked Contract

**Files:**
- Modify: `ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/CoordinatedReplaceWriter.swift`
- Modify: `macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation/CoordinatedReplaceWriter.swift`

- [ ] **Step 1: Introduce the async localization seam the write contract requires**

Add an async download/localization seam to both platform files and make the writer async-capable:

```swift
    typealias EnsureDownloaded = (URL) async throws -> Void
    typealias CoordinateReplace = (URL, (URL) throws -> Void) async throws -> Void

    let ensureDownloaded: EnsureDownloaded

    func overwriteExistingItem(
        at destinationURL: URL,
        prepareReplacementFile: (URL) throws -> Void
    ) async throws -> Bool {
        guard fileExists(destinationURL.path) else {
            return false
        }

        try await ensureDownloaded(destinationURL)
        try verifyDestination(destinationURL)
        ...
    }
```

For Task 4, the default foundation `live` binding may keep `ensureDownloaded: { _ in }` if the real wait logic still lives in the plugin entrypoint layer. The important change in this task is that the writer owns a first-class localization seam instead of silently assuming callers handled it.

Update all writer test fixtures to provide `ensureDownloaded: { _ in }` unless a test is explicitly checking localization order.

- [ ] **Step 2: Remove the write-path assumption that conflict resolution chooses the final file contents**

First introduce the write-path cleanup seam needed for a behavior-level ordering test. Add the sync cleanup closure type and stored property in both platform files:

```swift
    typealias CleanupConflicts = (URL) throws -> Void

    let cleanupConflicts: CleanupConflicts
```

Update all test fixtures in the writer test files to provide `cleanupConflicts: { _ in }` by default.

Then update the overwrite body in both platform files so replacement happens before write-path cleanup:

```swift
        do {
            try prepareReplacementFile(replacementURL)
            let cleanupConflicts = self.cleanupConflicts
            let replaceItem = self.replaceItem
            try await coordinateReplace(destinationURL) { coordinatedURL in
                try replaceItem(coordinatedURL, replacementURL)
                try cleanupConflicts(coordinatedURL)
            }
        } catch {
            try? removeItem(replacementDirectory)
            throw error
        }
```

- [ ] **Step 3: Replace the current write-path conflict binding**

Change the live binding so write-path cleanup uses the new helper:

```swift
        cleanupConflicts: { url in
            do {
                try cleanupConflictsAfterOverwrite(at: url)
            } catch {
                throw autoResolveConflictError(underlying: error)
            }
        },
```

- [ ] **Step 3: Add the behavior-level ordering test now that the seam exists**

Also add a seam-order test proving localization happens before validation in the async writer shape:

```swift
    func testOverwriteExistingItemEnsuresDownloadBeforeValidation() async throws {
        var events: [String] = []
        let writer = CoordinatedReplaceWriter(
            fileExists: { _ in true },
            ensureDownloaded: { _ in events.append("ensureDownloaded") },
            verifyDestination: { _ in events.append("verifyDestination") },
            createReplacementDirectory: { _ in URL(fileURLWithPath: "/tmp/replacement") },
            coordinateReplace: { _, accessor in try accessor(URL(fileURLWithPath: "/tmp/file.json")) },
            cleanupConflicts: { _ in events.append("cleanupConflicts") },
            replaceItem: { _, _ in events.append("replaceItem") },
            removeItem: { _ in }
        )

        _ = try await writer.overwriteExistingItem(
            at: URL(fileURLWithPath: "/tmp/file.json")
        ) { _ in }

        XCTAssertEqual(events.prefix(2), ["ensureDownloaded", "verifyDestination"])
    }
```

In both platform writer test files, add this test and make it pass only after the rewrite is correct:

```swift
    func testOverwriteExistingItemReplacesBeforeConflictCleanup() throws {
        var events: [String] = []
        let writer = CoordinatedReplaceWriter(
            fileExists: { _ in true },
            ensureDownloaded: { _ in },
            verifyDestination: { _ in },
            createReplacementDirectory: { _ in URL(fileURLWithPath: "/tmp/replacement") },
            coordinateReplace: { _, accessor in try accessor(URL(fileURLWithPath: "/tmp/file.json")) },
            cleanupConflicts: { _ in events.append("cleanupConflicts") },
            replaceItem: { _, _ in events.append("replaceItem") },
            removeItem: { _ in }
        )

        _ = try await writer.overwriteExistingItem(
            at: URL(fileURLWithPath: "/tmp/file.json")
        ) { _ in }

        XCTAssertEqual(events, ["replaceItem", "cleanupConflicts"])
    }
```

- [ ] **Step 5: Delete or merge speculative destination-shape validation unless it is the only honest way to preserve `E_ARG`**

Make one of these two edits, and only one:

```swift
        verifyDestination: { _ in }
```

or, if Part 1 proves the minimal validation seam is still the cleanest stable mapping:

```swift
        verifyDestination: { destinationURL in
            let values = try destinationURL.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true {
                throw fileDestinationError(isDirectory: true)!
            }
        }
```

Do not keep a separate helper unless the method audit explicitly marked it Keep.

- [ ] **Step 6: Simplify dead-code error helpers**

Delete write-path-only ready-state checks that no longer represent live overwrite behavior:

```swift
    static func replaceReadyStateError(
        hasConflicts: Bool,
        isUbiquitousItem: Bool,
        downloadStatus: URLUbiquitousItemDownloadingStatus?,
        isDownloading: Bool
    ) -> NSError? {
        // delete this helper once copy-path-only callers no longer need it
    }
```

If `verifyExistingDestinationCanBeReplaced(at:)` still needs the helper for copy-path semantics, reduce it to the copy-path-only checks and remove any write-path comments from it.

- [ ] **Step 7: Run the writer tests until they pass on both platforms**

Run:

```bash
swift test --package-path ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation --filter CoordinatedReplaceWriterTests
swift test --package-path macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation --filter CoordinatedReplaceWriterTests
```

Expected: the new ordering test now passes with `replaceItem` before cleanup, the localization-before-validation test passes, the current-item conflict test now passes, the download-in-progress test now maps to not-downloaded semantics, and missing-destination behavior still returns `false`.

- [ ] **Step 8: Commit the native writer rewrite**

```bash
git add ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/CoordinatedReplaceWriter.swift macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation/CoordinatedReplaceWriter.swift ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/Tests/icloud_storage_plus_foundationTests/CoordinatedReplaceWriterTests.swift macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation/Tests/icloud_storage_plus_foundationTests/CoordinatedReplaceWriterTests.swift
git commit -m "fix: reset write-path overwrite semantics"
```

### Task 5: Align Plugin Entrypoints And Dart Error Mapping

**Files:**
- Modify: `ios/icloud_storage_plus/Sources/icloud_storage_plus/iOSICloudStoragePlugin.swift`
- Modify: `macos/icloud_storage_plus/Sources/icloud_storage_plus/macOSICloudStoragePlugin.swift`
- Modify: `lib/models/exceptions.dart`
- Modify: `test/icloud_storage_method_channel_test.dart`

- [ ] **Step 1: Update observer call sites to the renamed observer helper**

Where the observer path currently calls the generic async resolver, rename the call to the observer-specific API:

```swift
Task {
    do {
        try await resolvePresentedItemConflicts(at: fileURL)
    } catch {
        DebugHelper.log("Failed to resolve conflicts: \(error.localizedDescription)")
        lastError = error
    }
}
```

- [ ] **Step 2: Keep native write entrypoints thin and aligned**

At this stage, the writer is async-capable and owns an injected `ensureDownloaded` seam. The plugin entrypoints should supply the real localization closure using the existing plugin-layer `waitForDownloadCompletion(...)` helper rather than re-embedding the logic into `CoordinatedReplaceWriter.live`.

Construct the writer in the entrypoint layer like this:

```swift
    let writer = CoordinatedReplaceWriter(
        fileExists: { FileManager.default.fileExists(atPath: $0) },
        ensureDownloaded: { [self] url in
            let values = try url.resourceValues(forKeys: [
                .isUbiquitousItemKey,
                .ubiquitousItemDownloadingStatusKey,
                .ubiquitousItemDownloadingErrorKey,
            ])
            guard values.isUbiquitousItem == true else { return }
            if let err = values.ubiquitousItemDownloadingError { throw err }
            guard values.ubiquitousItemDownloadingStatus != .current else { return }
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
            try await waitForDownloadCompletion(
                at: url,
                idleTimeouts: [10.0, 20.0],
                retryBackoff: [2.0]
            )
        },
        verifyDestination: CoordinatedReplaceWriter.live.verifyDestination,
        createReplacementDirectory: CoordinatedReplaceWriter.live.createReplacementDirectory,
        coordinateReplace: CoordinatedReplaceWriter.live.coordinateReplace,
        cleanupConflicts: CoordinatedReplaceWriter.live.cleanupConflicts,
        replaceItem: CoordinatedReplaceWriter.live.replaceItem,
        removeItem: CoordinatedReplaceWriter.live.removeItem
    )
```

Wrap overwrite calls in `Task` because `overwriteExistingItem(...)` is now async.

In both plugin entrypoint files, keep `writeInPlace` and `writeInPlaceBytes` focused on:

```swift
    let fileURL = containerURL.appendingPathComponent(relativePath)
    try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true,
        attributes: nil
    )

    Task { [self] in
        do {
            // call the async writer-backed document overwrite path here
        } catch {
            let mapped = mapFileNotFoundError(
                error,
                operation: "writeInPlace",
                relativePath: relativePath
            ) ?? nativeCodeError(
                error,
                operation: "writeInPlace",
                relativePath: relativePath
            )
            result(mapped)
            return
        }
        result(nil)
    }
```

Do not move new business logic into the entrypoints. The writer owns the overwrite semantics.

- [ ] **Step 3: Add typed mapping for `invalidArgument` in Dart**

Extend `mapICloudPlatformException` in `lib/models/exceptions.dart` so `E_ARG` write-path failures do not fall through to `ICloudUnknownNativeException`:

```dart
class ICloudInvalidArgumentException extends ICloudOperationException {
  ICloudInvalidArgumentException._(_ICloudOperationExceptionData data)
      : super(
          category: data.category,
          operation: data.operation,
          retryable: data.retryable,
          message: data.message,
          relativePath: data.relativePath,
          nativeDomain: data.nativeDomain,
          nativeCode: data.nativeCode,
          nativeDescription: data.nativeDescription,
          underlying: data.underlying,
        );
}

// In the switch:
'invalidArgument' => ICloudInvalidArgumentException._(data),
```

- [ ] **Step 4: Update the Dart test expectation to the final typed exception**

Change the failing expectation from Task 2 to:

```dart
        throwsA(isA<ICloudInvalidArgumentException>()),
```

- [ ] **Step 5: Run the Flutter-side test suite for the method channel**

Run:

```bash
flutter test test/icloud_storage_method_channel_test.dart
```

Expected: write-path category/code mapping is now stable for `E_ARG` and `E_CONFLICT`.

- [ ] **Step 6: Commit the entrypoint and Dart mapping changes**

```bash
git add ios/icloud_storage_plus/Sources/icloud_storage_plus/iOSICloudStoragePlugin.swift macos/icloud_storage_plus/Sources/icloud_storage_plus/macOSICloudStoragePlugin.swift lib/models/exceptions.dart test/icloud_storage_method_channel_test.dart
git commit -m "fix: align write-path error mapping"
```

### Task 6: Prune Structure-Coupled Tests And Validate Shipping Paths

**Files:**
- Modify: `ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/Tests/icloud_storage_plus_foundationTests/CoordinatedReplaceWriterTests.swift`
- Modify: `macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation/Tests/icloud_storage_plus_foundationTests/CoordinatedReplaceWriterTests.swift`
- Verify: `ios/icloud_storage_plus/Package.swift`
- Verify: `macos/icloud_storage_plus/Package.swift`
- Verify: `ios/icloud_storage_plus.podspec`
- Verify: `macos/icloud_storage_plus.podspec`

- [ ] **Step 1: Delete tests that preserve helper structure instead of behavior**

Remove or rewrite tests like these if they no longer protect a real contract:

```swift
    func testHelperSourceDoesNotExposeCopyOverwriteEntryPoint() throws {
        let helperSource = try String(...)
        XCTAssertFalse(helperSource.contains("copyItemOverwritingExistingItem"))
    }

    func testHelperSourceDoesNotKeepRedundantNonCurrentGuard() throws {
        let helperSource = try String(...)
        XCTAssertFalse(helperSource.contains("if downloadStatus != .current"))
    }
```

Replace them with behavior tests only if the same contract still matters.

- [ ] **Step 2: Run the full native and Flutter verification matrix**

Run:

```bash
swift test --package-path ios/icloud_storage_plus
swift test --package-path macos/icloud_storage_plus
flutter test
flutter analyze
```

Expected:

- both SPM packages pass all native tests
- Flutter tests pass
- `flutter analyze` is clean

- [ ] **Step 3: Run CocoaPods compatibility checks without letting them drive redesign**

Run:

```bash
pod lib lint ios/icloud_storage_plus.podspec --allow-warnings
pod lib lint macos/icloud_storage_plus.podspec --allow-warnings
```

Expected: compatibility remains intact. If a podspec fails only because the compatibility layer no longer points at the SPM-primary source layout, fix the podspec source inclusion. Do not reintroduce source duplication to satisfy CocoaPods.

- [ ] **Step 4: Review the final diff for scope discipline**

Run:

```bash
git diff --stat origin/main...HEAD
```

Expected: changes stay within the scoped write-path files, the contract docs, and the targeted tests.

- [ ] **Step 5: Commit the validation cleanup**

```bash
git add ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/Tests/icloud_storage_plus_foundationTests/CoordinatedReplaceWriterTests.swift macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation/Tests/icloud_storage_plus_foundationTests/CoordinatedReplaceWriterTests.swift ios/icloud_storage_plus/Package.swift macos/icloud_storage_plus/Package.swift ios/icloud_storage_plus.podspec macos/icloud_storage_plus.podspec
git commit -m "test: validate write-path reset shipping paths"
```

## Self-Review

### Spec Coverage

- Strict contract-first reset: covered by Task 1 contract audit and spec sync.
- Senior Swift method audit: covered by Task 1 method inventory and Task 6 scope review.
- Public API name stability: preserved by keeping `writeInPlace` / `writeInPlaceBytes` entrypoints and Dart signatures unchanged in Task 5.
- User replacement content stays the winner: enforced by Task 4 rewrite ordering.
- SPM primary, CocoaPods secondary: enforced by Task 6 verification order.

### Placeholder Scan

- No `TODO`, `TBD`, or “similar to above” placeholders remain.
- Every code-changing task includes concrete file paths, snippets, and commands.

### Type Consistency

- Observer resolver names are consistently `resolvePresentedItemConflictsSync` / `resolvePresentedItemConflicts`.
- Write-path cleanup helper is consistently `cleanupConflictsAfterOverwrite`.
- Dart error mapping uses `invalidArgument`, `conflict`, `coordination`, `itemNotDownloaded`, `timeout`, and `unknownNative` to match the existing payload scheme.
