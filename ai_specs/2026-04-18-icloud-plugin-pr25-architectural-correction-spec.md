# 2026-04-18 — PR #25 architectural correction (writeInPlace auto-resolve)

<goal>
Fix the architectural defects in PR #25 (`feat/writeinplace-auto-resolution`) so the writeInPlace auto-download + auto-resolve feature actually activates, runs without deadlock surface, and ships through Flutter's CocoaPods build path. Two findings are architectural (the entire feature is currently a no-op because the legacy pre-flight refuses on `hasConflicts == true` before the new resolveConflicts seam can run; and the `DispatchSemaphore`-bridged async accessor inside `NSFileCoordinator.coordinate` can deadlock the Swift cooperative thread pool under load); three are mechanical (both platform podspecs still glob-include only `Sources/icloud_storage_plus/**/*` so the new shared foundation files never reach a CocoaPods build, both podspecs still declare `s.version = '2.0.0'`, and `autoResolveConflictError` stores `Error` under `NSUnderlyingErrorKey` instead of `NSError`).

Why it matters: PR #25 is on the critical path for the parent app's autosave Sentry-noise reduction (cluster of ~319 events in release 1.6.2, issues WA–WJ). Shipping it as-is would publish 2.1.0 to pub.dev with the headline behavior silently disabled, leave the Flutter CocoaPods build broken on the new shared sources, and embed a deadlock surface that only manifests under cooperative-pool starvation. None of those is acceptable for a public pub.dev release.

This spec corrects PR #25 in place on the existing branch — no new branch, no rebase, additional commits stacked on `feat/writeinplace-auto-resolution`.
</goal>

<background>
**PR under correction**: https://github.com/kingdomseed/icloud_storage_plus/pull/25 (branch `feat/writeinplace-auto-resolution`, base `main`).

**Tech stack**:
- Flutter plugin `icloud_storage_plus` 2.0.0 → 2.1.0, dual-platform (iOS + macOS) Swift Package Manager layout with a sub-SPM-package per platform for testability (`icloud_storage_plus` outer + `icloud_storage_plus_foundation` inner).
- Native code: Swift 5.9, async/await throughout the new seams, `NSFileCoordinator` + `NSFileVersion` + `NSMetadataQuery`.
- Distribution: pub.dev for the Dart layer; Flutter consuming apps build the native side via CocoaPods (the `*.podspec` files), NOT directly via SPM. This is the critical fact missed by PR #25 as committed.

**Files to examine**:
- @ios/icloud_storage_plus.podspec — currently `source_files = 'icloud_storage_plus/Sources/icloud_storage_plus/**/*.{h,m,swift}'`, version `2.0.0`. Needs widening + version bump.
- @macos/icloud_storage_plus.podspec — same shape, same fix.
- @ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/CoordinatedReplaceWriter.swift — the async overwrite path with the broken pre-flight ordering, the semaphore bridge, and `autoResolveConflictError`.
- @macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation/CoordinatedReplaceWriter.swift — identical content (shared via SPM `target.sources`); both must be updated in lockstep.
- @ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/Tests/icloud_storage_plus_foundationTests/CoordinatedReplaceWriterTests.swift — needs new behavior tests + updated seam types.
- @macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation/Tests/icloud_storage_plus_foundationTests/CoordinatedReplaceWriterTests.swift — mirror.
- @ios/icloud_storage_plus/Sources/icloud_storage_plus/iOSICloudStoragePlugin.swift and @macos/icloud_storage_plus/Sources/icloud_storage_plus/macOSICloudStoragePlugin.swift — `copyOverwritingExistingItem` calls `verifyExistingDestinationCanBeReplaced`; that copy path keeps the legacy full-pre-flight (out of scope for auto-resolve in this PR).
- @example/ — Flutter example app. Used to validate that Flutter's CocoaPods build path actually compiles after the podspec change.

**Apple-doc references** (all locally cached at `/Users/jholt/apple-foundation-study-vault/apple-docs/rendered/documentation/foundation/`):
- `nsfilecoordinator.md` — synchronous accessor contract; "Methods invoke their accessor blocks on the current thread, which means that the calling thread must remain alive until the block executes."
- `nsfileversion/unresolvedconflictversionsofitem(at:).md` — synchronous API; recommends resolving (not refusing).
- `nsfileversion/replaceitem(at:options:).md` — synchronous.
- `nsfileversion/removeotherversionsofitem(at:).md` — synchronous; "Call this method only after you've called the `replaceItem(at:options:)` method or otherwise resolved a conflict."
- `filemanager/startdownloadingubiquitousitem(at:).md` — synchronous trigger; observe `URLUbiquitousItemDownloadingStatusKey` for completion.

**Reviewer attribution** (all 5 findings come from automated reviews on PR #25):
- Sentry [CRITICAL]: `DispatchSemaphore.wait()` inside Swift `Task` deadlock surface (`CoordinatedReplaceWriter.swift:254`, iOS).
- Codex [P0]: podspec missing shared foundation sources (`iOSICloudStoragePlugin.swift:642`).
- Codex [P1]: pre-flight conflict guard blocks auto-resolution (`CoordinatedReplaceWriter.swift:47`).
- Copilot: same podspec finding (both platforms); same NSError-bridging finding (both platforms); pubspec ↔ podspec version drift.

**Architectural principle established with the user** (mermaid diagram in conversation): pre-flight conflict/download REFUSAL was a 2.0.0 workaround for missing recovery, not a feature. In a well-architected iCloud writer, "pre-flight" reduces to validation of categorical impossibilities (directory destination). Conflict/download states are recovered by the new seams (`ensureDownloaded` before the coordinator block, `resolveUnresolvedConflicts` inside it), not refused. The `async throws` decoration on `ResolveConflicts` was symmetry-driven, not reality-driven; the underlying NSFileVersion APIs are synchronous, and forcing async around them is what introduced the deadlock surface.

**Out of scope for this correction**:
- The `copy()` path. Its `copyOverwritingExistingItem` keeps calling `verifyExistingDestinationCanBeReplaced` with full pre-flight (conflict + download). Symmetric auto-resolve for copy is a separate future PR.
- The downstream app's pubspec bump (`mythicgme2e`, `^2.0.0` → `^2.1.0`). Happens after this PR ships and 2.1.0 is published to pub.dev.
- The `JournalAutosaveNotifier._doSave` double-report rider. Tracked separately in the parent app's plan.
- Adding NSFileCoordinator-based copy auto-resolve, or a Dart-side recoverable-iCloud classifier. Both explicitly deferred by the original 2026-04-17 spec.
</background>

<user_flows>
This is plugin infrastructure, not user-facing UI. Flows are described as native + Dart behavior contracts.

**Primary flow — autosave write to a previously-conflicted iCloud file (the regression that 2.0.0 produced and 2.1.0 must fix)**:
1. Flutter app calls `icloud_storage_plus.writeInPlace(containerId:, relativePath:, contents:)`.
2. iOS/macOS plugin enters `writeInPlace`, builds `fileURL`, ensures parent directory exists.
3. Plugin calls `writeInPlaceDocument(at: fileURL, contents:)` which routes through `performBackgroundOverwriteIfNeeded` → `Task.detached` → `try await CoordinatedReplaceWriter.live.overwriteExistingItem(at: fileURL)`.
4. Inside `overwriteExistingItem`:
   a. `fileExists(fileURL.path)` returns true → continue.
   b. `try await ensureDownloaded(fileURL)` — file is `.current` already; returns immediately.
   c. `try verifyDestination(fileURL)` — directory check only; passes (it's a regular file).
   d. `try createReplacementDirectory(fileURL)` → `replacementURL` in temp.
   e. `try prepareReplacementFile(replacementURL)` writes new contents.
   f. `try await coordinateReplace(fileURL) { coordinatedURL in try resolveConflicts(coordinatedURL); try replaceItem(coordinatedURL, replacementURL) }`. Inside the coordinator block (synchronous per Apple's contract): `resolveUnresolvedConflicts` runs the canonical pattern (`unresolvedConflictVersionsOfItem` → sort → `replaceItem(at:)` on most-recent → mark all `isResolved` → `removeOtherVersionsOfItem`), then `FileManager.replaceItemAt(coordinatedURL, withItemAt: replacementURL)` clobbers with the user's content. `removeItem(replacementDirectory)` cleans up.
5. `overwriteExistingItem` returns `true`. Plugin completion fires `result(nil)`. Dart side receives success.
6. **Net behavior**: write succeeds despite pre-existing conflicts. No `ICloudConflictException`. No Sentry event. (This is the regression-fix this PR exists to deliver — currently broken because step 4c throws on `hasConflicts == true`.)

**Alternative flow — write to a non-current ubiquitous file**:
1. Steps 1–3 as above.
2. Step 4b: `ensureDownloaded` reads `URLResourceValues`, sees `isUbiquitousItem == true`, `downloadStatus != .current`, no `downloadingError`. Calls `FileManager.startDownloadingUbiquitousItem(at: fileURL)`. Awaits `waitForDownloadCompletion` with `DownloadSchedule.interactiveWrite` (~32s budget). When `.current` reached, returns.
3. Steps 4c–4f as above. Resolve handles any conflicts that landed during the download window.
4. Write succeeds.

**Alternative flow — write to a local (non-ubiquitous) file**:
1. Steps 1–3 as above.
2. Step 4b: `ensureDownloaded` reads `URLResourceValues`, sees `isUbiquitousItem == false`. Returns immediately (no-op).
3. Steps 4c–4f. Resolve is a no-op for local files (`unresolvedConflictVersionsOfItem` returns nil).
4. Write succeeds.

**Error flow — download exhausts the interactive-write budget**:
1. Steps 1–3.
2. Step 4b: `waitForDownloadCompletion` exhausts `[10, 20]` idle timeouts with `[2]` retry backoff. Throws `iCloudDownloadTimeoutError()` (NSError domain `ICloudStorageTimeout`, code 1, "Download idle timeout").
3. Plugin's `mapTimeoutError` wraps it as `FlutterError(code: "E_TIMEOUT", category: "timeout", retryable: true)`.
4. Dart side maps to `ICloudTimeoutException`. Reaches Sentry through the data-layer boundary (this is genuinely actionable — distinct from refuse-to-write noise).

**Error flow — startDownloadingUbiquitousItem throws (account signed out, quota exceeded)**:
1. Steps 1–3.
2. Step 4b: `ensureDownloaded` reads `URLResourceValues`, observes `ubiquitousItemDownloadingError != nil`. Throws that error directly.
3. Plugin maps via `nativeCodeError`. Dart side sees the typed system error.

**Error flow — auto-resolution fails inside the coordinator (disk full during `removeOtherVersionsOfItem`, file vanishes mid-operation)**:
1. Steps 1–4e.
2. Step 4f: `resolveConflicts` (via the `live` binding) throws. The `live` binding catches and wraps via `autoResolveConflictError(underlying:)` → NSError with domain `ICloudStoragePlusErrorDomain`, code `conflictReplaceStateCode` (1), localized description containing the marker `"auto-resolution failed"`, and `NSUnderlyingErrorKey` populated with the original `NSError`.
3. The coordinator block exits without calling `replaceItem`. `overwriteExistingItem` cleans up the replacement directory and rethrows.
4. Plugin maps the `ICloudStoragePlusErrorDomain` / code 1 NSError to `FlutterError(code: "E_CONFLICT", category: "conflict")`.
5. Dart side maps to `ICloudConflictException`. The `auto-resolution failed` marker in the localized description distinguishes this from the legacy refuse-to-write text in logs and crash reports.

**Error flow — destination is a directory**:
1. Steps 1–3.
2. Step 4c: `verifyDestination` reads `isDirectoryKey`, sees `true`. Throws `fileDestinationError(isDirectory: true)` — NSError domain `ICloudStoragePlusErrorDomain`, code `directoryReplaceStateCode` (4), description "Cannot replace an existing directory with file content."
3. Plugin maps to `FlutterError(code: "E_ARG", category: "invalidArgument")`.
4. Dart side surfaces as the existing typed argument exception.

**Concurrent flow — two writes to the same file in flight**:
1. Both writes enter `overwriteExistingItem`.
2. Both reach `coordinateReplace`. `NSFileCoordinator` serializes them per Apple's documented behavior. The second waits for the first.
3. Resolve runs inside each coordinator block; second write sees a clean state.
4. Both succeed, in serial order. No additional locking required.
</user_flows>

<requirements>

**Functional — pre-flight reduction (architectural fix #1, addresses Codex P1):**

1. The `live` binding's `verifyDestination` MUST check only categorical impossibilities — specifically, "is the destination a regular file (not a directory)?" — and MUST NOT refuse on `hasConflicts == true`, `downloadStatus != .current`, or `isDownloading == true`. The current `verifyFileDestinationCanBeOverwritten` private helper's coupling of directory-rejection with `verifyExistingDestinationCanBeReplaced` MUST be split: a new private helper (suggested name: `verifyOverwriteDestinationIsFile(at:)`) handles directory rejection only, and the `live` binding uses that.

2. `verifyExistingDestinationCanBeReplaced(at:)` (the full pre-flight including conflict + download checks) MUST remain accessible as a static helper because `copyOverwritingExistingItem` in both `iOSICloudStoragePlugin.swift` and `macOSICloudStoragePlugin.swift` still calls it. Do NOT delete or modify its behavior; symmetric auto-resolve for copy is out of scope.

3. After this change, the typed errors `E_CONFLICT`, `E_NOT_DOWNLOADED`, and `E_DOWNLOAD_IN_PROGRESS` MUST become unreachable from `writeInPlace` / `writeInPlaceBytes` / `writeDocument` under normal operation. `E_CONFLICT` is reachable only when `resolveConflicts` itself throws (then via `autoResolveConflictError` with the `auto-resolution failed` marker). `E_NOT_DOWNLOADED` and `E_DOWNLOAD_IN_PROGRESS` become unreachable from the writeInPlace path entirely (download timeouts surface as `E_TIMEOUT`, system download errors surface as `E_NAT`-class via `nativeCodeError`). This is the spec's "now fire only when auto-resolution itself fails" clause made literal.

**Functional — sync seams (architectural fix #2, addresses Sentry CRITICAL):**

4. The `ResolveConflicts` typealias MUST change from `(URL) async throws -> Void` to `(URL) throws -> Void`. The async wrapping was symmetry-driven and added no real suspension; the live binding wraps three synchronous `NSFileVersion` calls. This deviates from the Phase 2 plan typealias by intent — the spec's behavior contract (resolve-inside-coordinator, Apple's canonical pattern) is preserved either way.

5. The `CoordinateReplace` typealias's accessor parameter MUST change from `@escaping @Sendable (URL) async throws -> Void` to `@Sendable (URL) throws -> Void` (sync). This matches `NSFileCoordinator.coordinate(writingItemAt:options:error:byAccessor:)`'s actual contract — the accessor is invoked synchronously on the calling thread.

6. The OUTER `CoordinateReplace` signature stays `async throws` because the bridge from `NSFileCoordinator.coordinate` (sync, blocking) to the async caller still must happen.

7. The shared resolver's async wrapper `resolveUnresolvedConflicts(at:) async throws` (defined in `ConflictResolver.swift`) MAY remain async-decorated for the iOS observer call site (`ICloudDocument.documentStateChanged` already uses `Task { try await resolveUnresolvedConflicts(at: targetURL) }` — leaving that signature alone avoids touching the observer). A new sync sibling (suggested name: `resolveUnresolvedConflictsSync(at:) throws`) MUST exist for the `live` binding to call from the now-sync coordinator accessor. Both wrappers share the generic `resolveUnresolvedConflicts<Version>(...)` core.

**Functional — `liveCoordinateReplace` deadlock-free bridge:**

8. `liveCoordinateReplace` MUST be rewritten to bridge sync `NSFileCoordinator.coordinate` into async via `withCheckedThrowingContinuation` running on a non-cooperative thread (`DispatchQueue.global(qos: .userInitiated).async`). NO `DispatchSemaphore` shall remain in the implementation. The `CoordinatedReplaceErrorBox` private class becomes unnecessary and MUST be deleted.

9. The sync coordinator accessor inside the bridge MUST invoke the typed accessor parameter (now `(URL) throws -> Void`) directly — no inner `Task.detached`, no semaphore, no continuation inside the closure. Coordinator accessor errors MUST be captured into a local `var accessError: Error?` and surfaced via the outer continuation after `coordinator.coordinate` returns.

10. The continuation MUST resume exactly once. Use a single `cont.resume()` / `cont.resume(throwing:)` per terminal branch (coordination error → throw; access error → throw; success → resume).

**Functional — podspec mechanical fix (addresses Codex P0 + Copilot):**

11. `ios/icloud_storage_plus.podspec` `s.source_files` MUST widen to include the three shared foundation files. Suggested form:
    ```ruby
    s.source_files = [
      'icloud_storage_plus/Sources/icloud_storage_plus/**/*.{h,m,swift}',
      'icloud_storage_plus/Sources/icloud_storage_plus_foundation/CoordinatedReplaceWriter.swift',
      'icloud_storage_plus/Sources/icloud_storage_plus_foundation/DownloadWaiter.swift',
      'icloud_storage_plus/Sources/icloud_storage_plus_foundation/ConflictResolver.swift',
    ]
    ```
    Do NOT use a wildcard like `Sources/**/*.swift` because the `Tests/` and `Placeholder.swift` subtree under `icloud_storage_plus_foundation/` MUST NOT be compiled into the plugin. Explicit file enumeration per the SPM `target.sources` declaration is the correct mirror.

12. `macos/icloud_storage_plus.podspec` `s.source_files` MUST receive the same three additions. Both podspecs MUST stay in sync with the outer `Package.swift` `target.sources` arrays.

13. Both podspec `s.version` declarations MUST bump from `'2.0.0'` to `'2.1.0'` to match `pubspec.yaml`. Drift between pub.dev version and podspec version is a `pod lib lint` warning at minimum and a CocoaPods resolution failure at worst.

**Functional — NSError bridging (addresses Copilot):**

14. `autoResolveConflictError(underlying:)` MUST cast `underlying as NSError` exactly once, store the result under `NSUnderlyingErrorKey`, and use the same `as NSError` value when extracting `localizedDescription` for the wrapping message. This guarantees `NSUnderlyingErrorKey` round-trips as `NSError` for downstream consumers (Dart-side `details["underlying"]` mapping, Sentry breadcrumbs, system `os_log`).

**Error Handling:**

15. The behavior of `iOSICloudStoragePlugin.nativeCodeError` and `macOSICloudStoragePlugin.nativeCodeError` MUST NOT change. They continue mapping `ICloudStoragePlusErrorDomain` codes to `E_CONFLICT` / `E_NOT_DOWNLOADED` / `E_DOWNLOAD_IN_PROGRESS` / `E_ARG`. The architectural change is upstream — what reaches `nativeCodeError` from writeInPlace shifts, but the mapping table stays intact.

16. `mapTimeoutError`'s domain match (`ICloudStorageTimeout`) MUST continue working. The `iCloudDownloadTimeoutError()` helper in `DownloadWaiter.swift` already produces this domain; do not alter it.

**Edge Cases:**

17. Concurrent writes to the same file: `NSFileCoordinator` already serializes. The bridge change does not affect serialization semantics. The `DispatchQueue.global` hop simply moves the blocking wait off the cooperative pool.

18. A file that becomes ubiquitous between `ensureDownloaded` (which sees `isUbiquitousItem == false` and returns) and the coordinator block: extremely rare. The coordinator block's `resolveConflicts` returns no-op (no conflicts). The atomic replace proceeds normally. Acceptable.

19. A file that gains a new conflict version between the coordinator opening and `replaceItem`: cannot happen — the coordinator's `.forReplacing` write option holds an exclusive lock during the accessor block.

20. The Phase 2 `live` binding currently captures `self.resolveConflicts` and `self.replaceItem` via `[replacementURL]` capture list before invoking `coordinateReplace`. After the seam-type change, these captures stay valid; only the typealias and the closure body change shape (no `await` before `resolveConflicts`).

**Validation:**

21. Foundation-level XCTest must verify the new pre-flight ordering with a behavior test (not just an absence test): construct a `CoordinatedReplaceWriter` with a `verifyDestination` seam that records when it fires and a `resolveConflicts` seam that records when it fires; on the `live`-equivalent ordering, `verifyDestination` MUST run before the coordinator opens AND MUST NOT throw on hasConflicts (since the test seam represents the new directory-only check). Verify both call counts.

22. Foundation-level XCTest must verify `liveCoordinateReplace` does not deadlock under concurrent load. Spin up N concurrent `Task`s (where N >= cooperative pool size as observed via `ProcessInfo.processInfo.activeProcessorCount`), each calling `liveCoordinateReplace` with a synthetic accessor that performs filesystem work and returns. All must complete within a reasonable bound (e.g., 5s). A pre-fix DispatchSemaphore implementation would deadlock under this test; the post-fix implementation must not.

23. Existing 36 macOS / 34 iOS foundation tests must continue to pass post-correction (modulo the typealias-driven test-double signature changes, which MUST be migrated as part of this work — closures `try await accessor(url)` become `try accessor(url)`, etc.).

24. CocoaPods integration test: MUST run `pod install` against the plugin example app's `ios/Podfile` AND a `flutter build ios --no-codesign --debug --simulator` (or `xcodebuild -workspace … -scheme Runner` equivalent) MUST succeed end-to-end. This is the only test that catches the podspec source-files defect — `swift test` and `flutter test` both pass even with the broken podspec because they don't exercise the CocoaPods build path. If the example app's `ios/` is not in a buildable state, document that explicitly and run `pod install` + `pod lib lint ios/icloud_storage_plus.podspec --allow-warnings` as the minimum substitute.

25. The macOS equivalent MUST be exercised: `flutter build macos --debug` against the example app, OR `pod lib lint macos/icloud_storage_plus.podspec --allow-warnings` as the minimum substitute.

26. `flutter pub publish --dry-run` MUST report `Package has 0 warnings` post-commit (currently passes, must continue passing).

27. `flutter analyze` (Dart) MUST remain clean.

28. The 115 Dart tests in `test/` MUST remain green — the architectural changes are entirely native; no Dart API surface moves.

29. **TDD discipline for the architectural changes**: write the failing tests for fixes #1, #2, and the deadlock contract FIRST, watch them go red, then make the source change, then watch them go green. Specifically:
    - **Slice A (pre-flight reduction)**: write a test that builds the writer with a `verifyDestination` seam asserting it is invoked with a destination URL whose `unresolvedConflictVersionsOfItem` returns a non-empty array, and a `resolveConflicts` seam that records its invocation count. Assert `resolveConflicts` count == 1 and the overall write succeeds. RED on current code (pre-flight throws), GREEN after splitting `verifyDestination` to directory-only.
    - **Slice B (sync seam migration)**: change the test fixture closures from `try await accessor(url)` to `try accessor(url)`. Compile-fail RED until `CoordinateReplace` typealias and `ResolveConflicts` typealias are sync; GREEN after.
    - **Slice C (deadlock contract)**: the concurrent-load test described in requirement 22. RED if the implementation still uses `DispatchSemaphore` under cooperative-pool starvation; GREEN after the bridge swap.
    - **Slice D (NSError bridging)**: assert `wrapped.userInfo[NSUnderlyingErrorKey] is NSError` AND `(wrapped.userInfo[NSUnderlyingErrorKey] as? NSError)?.code` matches a numeric code. RED if `underlying` is stored as plain `Error`; GREEN after the cast.
    - **Slice E (podspec)**: a Ruby/text assertion test inside the foundation Swift tests is impractical — instead, this slice is verified by the CocoaPods integration test (requirement 24) and by `pod lib lint`. Mark explicitly as "tested via build, not via unit test."

30. **No mocking of Foundation**: continue the established DI-via-closures idiom for test seams. Do NOT introduce mockito/mocktail-equivalent for `NSFileVersion` — the generic `resolveUnresolvedConflicts<Version>(...)` already accepts a test-double `Version` type.
</requirements>

<boundaries>

**Edge cases:**

- **File deleted between fileExists check and the coordinator opening**: `fileExists` returns true → continue → coordinator opens → `replaceItem` fails with `NSFileNoSuchFileError`. Bubble through `nativeCodeError` and Dart's `mapFileNotFoundError`. Existing behavior; no change.
- **Coordinator timeout**: `NSFileCoordinator.coordinate` does not have a timeout parameter. If another process holds an exclusive write coordination indefinitely, this call blocks. Acceptable for now — surfacing a timeout would require a separate watchdog. Out of scope.
- **`resolveConflicts` succeeds on `replaceItem(at:)` but fails on `removeOtherVersionsOfItem`**: per the original spec, partial resolution is tolerable. The `replaceItem` happened, conflict-marker may have been set on some versions but not all. The `live` binding will throw via `autoResolveConflictError`, the user retries, the next attempt's `unresolvedConflictVersionsOfItem` returns the remaining unresolved versions, resolution completes. Document this in code comments.
- **`URLResourceValues` throws inside `ensureDownloaded`** (file deleted during the resource-key fetch): bubbles through unchanged.

**Error scenarios:**

- **Deadlock surface elimination**: the post-fix `liveCoordinateReplace` performs `NSFileCoordinator.coordinate` on a `DispatchQueue.global` thread, NOT on a cooperative pool thread. This guarantees the cooperative pool is never blocked by file coordination, regardless of how many concurrent writes are in flight or how exhausted the pool is.
- **Continuation leak**: the bridge MUST guarantee exactly-one continuation resume even if both `coordError` AND `accessError` are set (the latter cannot happen in practice — coordinator only invokes accessor if coordination succeeds — but defensive ordering: throw `coordError` if set, else throw `accessError` if set, else resume successfully). Use `withCheckedThrowingContinuation` (not `unsafeContinuation`) so leaks fail loudly during testing.
- **Sync accessor throws on a thread the continuation expects to resume on**: not a concern — `withCheckedThrowingContinuation` allows resumption from any thread.

**Limits:**

- The `interactiveWrite` schedule (`[10, 20]` idle timeouts, `[2]` retry backoff) yields a maximum ~32s wait inside `ensureDownloaded`. This bound is unchanged by this correction.
- `resolveUnresolvedConflicts` performs O(N log N) sort over conflict versions; in practice N is small (<10). No new bounds.
- The architectural correction does NOT introduce new retries, new caches, new locks, new feature flags, or new public Dart API. Pure subtraction of bugs.
</boundaries>

<implementation>

**Order of operations** (matters for keeping the working tree compilable at every commit):

**Commit 1: pre-flight reduction (Slice A).**
- @ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/CoordinatedReplaceWriter.swift: split `verifyFileDestinationCanBeOverwritten` into two helpers. New private helper `verifyOverwriteDestinationIsFile(at:)` does `let values = try destinationURL.resourceValues(forKeys: [.isDirectoryKey]); if let err = fileDestinationError(isDirectory: values.isDirectory == true) { throw err }`. The `live` binding's `verifyDestination` calls the new helper instead of the old one. Leave `verifyExistingDestinationCanBeReplaced` (the full pre-flight) and `verifyFileDestinationCanBeOverwritten` (its private wrapper) intact for the copy path, but the private wrapper becomes unused by the writeInPlace path. If the unused-private warning fires, either delete `verifyFileDestinationCanBeOverwritten` (since the only caller was the live binding) and inline the directory-only logic, or annotate. Prefer inline + delete to keep one path.
- Mirror to @macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation/CoordinatedReplaceWriter.swift verbatim.
- Add the foundation test described in Slice A to both test files.

**Commit 2: sync seam migration + deadlock-free bridge (Slices B + C).**
- @ConflictResolver.swift (both platforms): add `resolveUnresolvedConflictsSync(at:) throws` as a sync sibling to the existing async wrapper. Both delegate to the generic `resolveUnresolvedConflicts<Version>(...)`. Keep the async wrapper for the iOS `ICloudDocument.documentStateChanged` observer (it already uses `Task { try await ... }`).
- @CoordinatedReplaceWriter.swift (both platforms):
  - Change `typealias ResolveConflicts = (URL) async throws -> Void` to `typealias ResolveConflicts = (URL) throws -> Void`.
  - Change `typealias CoordinateReplace = (URL, @escaping @Sendable (URL) async throws -> Void) async throws -> Void` to `typealias CoordinateReplace = (URL, @Sendable (URL) throws -> Void) async throws -> Void`. Note that `@escaping` is no longer needed (the closure isn't captured into a Task).
  - In `overwriteExistingItem`, the accessor passed to `coordinateReplace` becomes `{ coordinatedURL in try resolveConflicts(coordinatedURL); try replaceItem(coordinatedURL, replacementURL) }` — no `await` before `resolveConflicts`.
  - Rewrite `liveCoordinateReplace`:
    ```swift
    static let liveCoordinateReplace: CoordinateReplace = {
        destinationURL, accessor in
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
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
                    continuation.resume(throwing: coordinationError)
                    return
                }
                if let accessError {
                    continuation.resume(throwing: accessError)
                    return
                }
                continuation.resume()
            }
        }
    }
    ```
  - Update the live binding for `resolveConflicts` to use the new sync wrapper:
    ```swift
    resolveConflicts: { url in
        do {
            try resolveUnresolvedConflictsSync(at: url)
        } catch {
            throw autoResolveConflictError(underlying: error)
        }
    }
    ```
  - Delete `private final class CoordinatedReplaceErrorBox: @unchecked Sendable` — no longer used.
- Mirror file changes to macOS.
- Update @CoordinatedReplaceWriterTests.swift (both platforms): every test that constructs a `CoordinatedReplaceWriter` directly MUST switch its inline `coordinateReplace: { url, accessor in try await accessor(url) }` closures to `coordinateReplace: { url, accessor in try accessor(url) }`, and every `resolveConflicts: { _ in ... }` async closure becomes sync. The `actor Callbacks` / `actor CallLog` patterns in `testHappyPathDoesNotReinvokePreFlight` and `testEnsureDownloadedRunsBeforeVerifyDestination` need re-examination — the actor's `await callbacks.bumpX()` calls inside what used to be async closures must move out (e.g., use a thread-safe class with NSLock, or use a sync-callable counter). Prefer a simple `final class Counter { let lock = NSLock(); private var count = 0; func bump() { lock.lock(); defer { lock.unlock() }; count += 1 }; var value: Int { lock.lock(); defer { lock.unlock() }; return count } }` for these tests to keep them sync.
- Add the Slice C concurrent-load test. Use `await withTaskGroup(of: Void.self)` to spawn `ProcessInfo.processInfo.activeProcessorCount * 2` tasks each calling `CoordinatedReplaceWriter.liveCoordinateReplace` with a temp-directory accessor that writes a small file. Assert all tasks complete within 5 seconds via XCTest's timeout.

**Commit 3: NSError bridging (Slice D).**
- @CoordinatedReplaceWriter.swift `autoResolveConflictError(underlying:)`:
    ```swift
    static func autoResolveConflictError(
        underlying: Error
    ) -> NSError {
        let underlyingNSError = underlying as NSError
        return NSError(
            domain: replaceStateErrorDomain,
            code: conflictReplaceStateCode,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Cannot replace an iCloud item: "
                    + "\(autoResolveFailedDescriptionMarker) — "
                    + underlyingNSError.localizedDescription,
                NSUnderlyingErrorKey: underlyingNSError,
            ]
        )
    }
    ```
- Mirror to macOS.
- Strengthen the existing `testLiveAutoResolveConflictErrorPreservesCoordinationDomain` assertion: change `XCTAssertEqual(wrapped.userInfo[NSUnderlyingErrorKey] as? NSError, underlying)` to assert `wrapped.userInfo[NSUnderlyingErrorKey] is NSError` first, then check `(... as? NSError)?.code == NSFileWriteOutOfSpaceError`.

**Commit 4: podspec correction (Slice E mechanical).**
- @ios/icloud_storage_plus.podspec: bump `s.version` to `'2.1.0'`. Replace `s.source_files = '...'` with the array form listing the four entries from requirement 11.
- @macos/icloud_storage_plus.podspec: same.
- Validate via `pod lib lint ios/icloud_storage_plus.podspec --allow-warnings` and `pod lib lint macos/icloud_storage_plus.podspec --allow-warnings`. If those don't exit 0, iterate.
- If the example app's `ios/` and `macos/` directories support full `flutter build`, run those — they're the gold-standard validation.

**Commit 5: plan reconciliation + branch update.**
- @ai_specs/2026-04-17-icloud-plugin-auto-resolution-plan.md: append a "Post-merge correction" note under Phase 2 that documents the architectural changes (pre-flight reduction, sync seams, deadlock-free bridge, podspec sync).
- Push to `feat/writeinplace-auto-resolution`. The PR auto-updates.

**Patterns to follow:**
- DI-via-closures for all native test seams (existing convention).
- One sync, one async wrapper for `resolveUnresolvedConflicts` — matches the two distinct call sites (observer Task vs. coordinator-block sync).
- `withCheckedThrowingContinuation` (not `unsafe...`) so any leaked continuation fails loudly.

**Anti-patterns to avoid:**
- Do NOT add a feature flag to toggle the pre-flight behavior. The new behavior IS the behavior. Rollback is via pubspec revert.
- Do NOT add `await` calls inside the synchronous coordinator accessor. The whole point of this correction is that the accessor is sync — that's NSFileCoordinator's contract and that's what eliminates the deadlock surface.
- Do NOT keep `CoordinatedReplaceErrorBox` "just in case." Delete it; the bridge no longer needs cross-thread error mailboxing.
- Do NOT delete `verifyExistingDestinationCanBeReplaced` or `replaceReadyStateError`. Copy still calls them. Their tests MUST still pass.
- Do NOT update the Dart-side `ICloudConflictException` mapping. The wire contract is preserved by `autoResolveConflictError`.
- Do NOT bundle unrelated cleanup. This PR has a tight scope: fix the 5 review findings, ship 2.1.0.
</implementation>

<validation>

**Test expectations** — a phase is not complete until each gate below passes.

**Slice A — pre-flight reduction:**
1. New foundation test `testLiveBindingDoesNotRefuseOnUnresolvedConflicts`: build a writer with a `verifyDestination` seam matching the new directory-only contract (test by passing a sentinel URL whose existence-check returns true and whose `isDirectoryKey` returns false), a `resolveConflicts` seam that records its call count, and assert: `verifyDestination` runs once, `resolveConflicts` runs once, write returns `true`, and no error is thrown — even when the test's `unresolvedConflictVersionsOfItem` stand-in would have indicated conflicts. RED on the current implementation; GREEN after the split.
2. Confirm `testHappyPathDoesNotReinvokePreFlight` still passes. Confirm `testEnsureDownloadedRunsBeforeVerifyDestination` still passes (the order remains: download → verifyDestination → coordinateReplace → resolveConflicts → replaceItem; the directory-only verifyDestination still runs first).

**Slice B — sync seam migration:**
3. The full foundation suite compiles after the typealias change and after every test fixture's accessor closure is updated. RED via compile error first; GREEN after all 9–10 fixture closures are migrated.
4. `testHappyPathDoesNotReinvokePreFlight` and `testEnsureDownloadedRunsBeforeVerifyDestination` migrate from `actor`-based bookkeeping to `NSLock`-based `Counter` instances (sync-callable). Step-order assertion remains identical; only the synchronization primitive changes.

**Slice C — deadlock contract:**
5. New foundation test `testLiveCoordinateReplaceDoesNotStarveCooperativePool`: spawn `ProcessInfo.processInfo.activeProcessorCount * 2` concurrent tasks via `withTaskGroup`, each calling `CoordinatedReplaceWriter.liveCoordinateReplace` against a unique temp file with a synthetic accessor that writes 1KB and returns. Assert all tasks complete within 5 seconds. RED on a `DispatchSemaphore`-based bridge under cooperative-pool starvation; GREEN after the `DispatchQueue.global` rewrite.
6. Manual smoke after the rewrite: `swift test` MUST complete in less than 5 seconds total per platform (current ~0.25s — should not regress).

**Slice D — NSError bridging:**
7. Update `testLiveAutoResolveConflictErrorPreservesCoordinationDomain`: replace `XCTAssertEqual(wrapped.userInfo[NSUnderlyingErrorKey] as? NSError, underlying)` with two assertions — `XCTAssertTrue(wrapped.userInfo[NSUnderlyingErrorKey] is NSError)` and `XCTAssertEqual((wrapped.userInfo[NSUnderlyingErrorKey] as? NSError)?.code, NSFileWriteOutOfSpaceError)`. RED if `underlying` is stored as plain `Error` (the `is NSError` check still passes due to bridging, but the `?.code` access reveals the lack of explicit cast — strengthen by also asserting that `wrapped.userInfo[NSUnderlyingErrorKey] as? NSError === underlying as NSError` via identity comparison if that's tractable).
8. Slice D is best validated by code review of the diff — the explicit `let underlyingNSError = underlying as NSError` cast is the contract; the test guards against future regressions.

**Slice E — podspec:**
9. `pod lib lint ios/icloud_storage_plus.podspec --allow-warnings --no-clean` exits 0. Run this command from the repo root. RED on the current podspec (because compilation will fail referencing `waitForDownloadCompletion` / `resolveUnresolvedConflictsSync` / `iCloudMetadataQuerySearchScopes` from the plugin sources without the foundation files); GREEN after the source_files widening.
10. `pod lib lint macos/icloud_storage_plus.podspec --allow-warnings --no-clean` exits 0.
11. Inside `example/`, run `cd example && flutter pub get && cd ios && pod install && cd .. && flutter build ios --no-codesign --debug --simulator`. Build must succeed. If the simulator build is unavailable in this environment (no Xcode SDK / no simulator runtime), substitute `xcodebuild -workspace example/ios/Runner.xcworkspace -scheme Runner -configuration Debug -sdk iphonesimulator clean build` and accept any iOS-provisioning failures as long as Swift compilation completes for the plugin target.
12. Same on macOS: `cd example && flutter build macos --debug` (or `xcodebuild` on `Runner.xcworkspace`). The plugin's macOS target must compile cleanly.
13. `flutter pub publish --dry-run` (from plugin root, post-commit) MUST report `Package has 0 warnings`.

**Cross-cutting:**
14. `flutter analyze` (plugin root): clean.
15. `flutter test` (plugin root): 115/115 pass.
16. iOS foundation `swift test` (in `ios/.../icloud_storage_plus_foundation/`): all tests pass, including the 2 new tests added in Slices A and C (count goes from 34 to ≥36).
17. macOS foundation `swift test`: all tests pass, count goes from 36 to ≥38.

**TDD enforcement:**
18. Each architectural slice (A, B, C, D) follows RED → GREEN → REFACTOR strictly. The agent executing this MUST commit (or at least show via `git diff` + test output) the failing test before the source change. Slice E's RED is `pod lib lint` failure; that's still RED-first if the lint runs before the source_files widening commit.
19. No mocking of NSFileCoordinator or NSFileVersion. Use the existing DI-via-closures seams. The generic `resolveUnresolvedConflicts<Version>(...)` already supports test doubles via parametric `Version`.

**Manual smoke (post-merge, pre-publish):**
20. On a real device or simulator with iCloud signed in: call `icloud_storage_plus.writeInPlace` against a file known to have unresolved conflict versions (set up via a second device or by manipulating `~/Library/Mobile Documents/`). Verify the write succeeds silently and `NSFileVersion.unresolvedConflictVersionsOfItem` returns empty afterward. This is the regression test for the pre-flight architectural fix.
21. On the same device, evict a file via `evictUbiquitousItem` (`brctl evict <path>` on macOS), call `writeInPlace`, observe auto-download + write succeed.
22. Sentry: 7 days post-publish, verify the WA–WJ event clusters drop ≥90% (already in original spec; documents the post-ship measurement window).
</validation>

<done_when>

1. All 5 review findings on PR #25 are addressed at the architectural level (not as workarounds): pre-flight reduced, sync seams adopted, deadlock-free bridge in place, podspecs corrected, NSError properly bridged.
2. Every test in the foundation test suites passes on both iOS and macOS, including the new tests for Slices A, C, and the strengthened D assertion.
3. `pod lib lint` passes on both podspecs.
4. CocoaPods integration: `flutter build ios` and `flutter build macos` succeed against the example app (or `pod lib lint` + `xcodebuild`-build substitutes as documented in validation step 11).
5. `flutter pub publish --dry-run` reports `Package has 0 warnings`.
6. The plan file `ai_specs/2026-04-17-icloud-plugin-auto-resolution-plan.md` has a "Post-merge correction" note documenting the architectural changes and explicitly noting the deviation from the plan's `ResolveConflicts = (URL) async throws -> Void` typealias.
7. PR #25 description is updated to reflect the architectural correction (a follow-up comment is acceptable).
8. Reviewer threads on PR #25 (Sentry, Codex P0, Codex P1, Copilot ×3) can each be marked resolved with reference to the corresponding commit SHA.
9. The branch is in a single-merge-commit-mergeable state on `main`. No rebase required; additional commits stack on top of the existing `feat/writeinplace-auto-resolution` history.
</done_when>
