# 2026-04-17 — iCloud writeInPlace auto-resolution — Plugin plan

## Overview

Plugin 2.0.0 → 2.1.0. Step 0 (no-op refactor): unify duplicates + extract async-throws helpers. Step 1 (new behavior): `writeInPlace` auto-downloads + auto-resolves unresolved conflicts, symmetric with `readInPlace`.

**Spec**: `ai_specs/2026-04-17-icloud-plugin-auto-resolution-spec.md` (read for full requirements)

## Context

- **Repo**: `icloud_storage_plus` Flutter plugin. 2.0.0 published on pub.dev.
- **Structure**: iOS + macOS native Swift, SPM. Dual modules per platform: `icloud_storage_plus` + `icloud_storage_plus_foundation`.
- **Known pre-existing debt**: `CoordinatedReplaceWriter.swift` has 4 textual copies (iOS × 2 modules, macOS × 2 modules). Step 0 unifies.
- **Apple documentation**: `/Users/jholt/apple-foundation-study-vault/apple-docs/rendered/documentation/foundation/` — authoritative local cache for `NSFileVersion`, `NSFileCoordinator`, `startDownloadingUbiquitousItem`, etc.
- **Reference implementations** (to read):
  - Existing callback-based waiter: `ios/icloud_storage_plus/Sources/icloud_storage_plus/iOSICloudStoragePlugin.swift:921-1031` (and macOS mirror at `:901`)
  - Existing conflict resolver (streaming-only, to delete): `ios/icloud_storage_plus/Sources/icloud_storage_plus/ICloudDocument.swift:107-140`
  - Pre-flight check (kept as last-resort guard): `ios/icloud_storage_plus/Sources/icloud_storage_plus/CoordinatedReplaceWriter.swift:69-113`
  - XCTest target (exists): `ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/Tests/icloud_storage_plus_foundationTests/CoordinatedReplaceWriterTests.swift`
- **Assumptions/Gaps**:
  - SPM `target.sources` can share `CoordinatedReplaceWriter.swift` between both modules per platform; each target compiles its own copy; `internal` visibility survives.
  - `withCheckedThrowingContinuation` wraps the existing `NSMetadataQuery`+`CompletionGate` loop; `CompletionGate` already enforces resume-once.
  - `CoordinatedReplaceWriter.live` static-let may require promotion to `static var` or factory `static func make()` for async-closure binding — keep DI-via-closures idiom either way.
  - MethodChannel handlers calling `overwriteExistingItem` need `Task { do { try await ...; result(v) } catch { result(FlutterError) } }` bridge after async conversion.
  - Plugin `example/` has no integration tests discoverable; audit step is grep-confirm-empty.

## Plan

### Phase 1: Step 0 prerequisite refactor (behavioral no-op)

- **Goal**: unify duplicates, extract helpers to async throws, delete `ICloudDocument.resolveConflicts()`; plugin behavior identical to 2.0.0.
- [x] `{ios,macos}/icloud_storage_plus/Package.swift` — share `CoordinatedReplaceWriter.swift` via `target.sources` for both `icloud_storage_plus` and `icloud_storage_plus_foundation` modules. Delete 2 of 4 textual copies per platform.
- [x] `{ios,macos}/.../Sources/<shared>/DownloadWaiter.swift` (new) — `func waitForDownloadCompletion(at:idleTimeouts:retryBackoff:) async throws` wrapping existing `NSMetadataQuery`+`CompletionGate` via `withCheckedThrowingContinuation`. Move support cluster: `addObserver`, `removeObservers`, `querySearchScopes`, `evaluateDownloadStatus`, `timeoutNativeError`, `CompletionGate`. Export named configs:
  ```swift
  enum DownloadSchedule {
    static let interactiveWrite = (idleTimeouts: [10.0, 20.0], retryBackoff: [2.0])
    static let backgroundRead   = (idleTimeouts: [60.0, 90.0, 180.0], retryBackoff: [2.0, 4.0])
  }
  ```
- [x] `{ios,macos}/.../Sources/<shared>/ConflictResolver.swift` (new) — `func resolveUnresolvedConflicts(at:) async throws` matching Apple's canonical pattern (mirror existing `ICloudDocument.resolveConflicts()` verbatim):
  ```swift
  func resolveUnresolvedConflicts(at url: URL) async throws {
    guard let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: url),
          !conflicts.isEmpty else { return }
    let sorted = conflicts.sorted {
      ($0.modificationDate ?? .distantPast) > ($1.modificationDate ?? .distantPast)
    }
    if let latest = sorted.first {
      try latest.replaceItem(at: url, options: [])
    }
    conflicts.forEach { $0.isResolved = true }
    try NSFileVersion.removeOtherVersionsOfItem(at: url)
  }
  ```
- [x] `iOSICloudStoragePlugin.swift` + `macOSICloudStoragePlugin.swift` — delete private callback-based `waitForDownloadCompletion` at `:921-1031` (iOS) / `:901` (macOS) and its support cluster. Callers updated to `try await waitForDownloadCompletion(...)`. Same name; signature/body change.
- [x] `ICloudDocument.swift` — delete `resolveConflicts()` (lines 107-140). `documentStateChanged()` wraps the shared helper:
  ```swift
  @objc private func documentStateChanged() {
    if documentState.contains(.inConflict) {
      Task {
        do { try await resolveUnresolvedConflicts(at: fileURL) }
        catch {
          DebugHelper.log("Failed to resolve conflicts: \(error.localizedDescription)")
          lastError = error
        }
      }
    }
    // existing .savingError / .editingDisabled handling unchanged
  }
  ```
- [x] `CoordinatedReplaceWriter.swift` (unified) — NO behavior change in Phase 1. Retain existing `verifyDestination` pre-flight as-is. Only the refactor lands.
- [x] TDD: shared-helper unit coverage —
  - `DownloadWaiterTests.swift` (new): schedule constants + timeout/domain invariants; watchdog timeout fires on non-ubiquitous path; retry schedule walks before timing out. `CompletionGate` single-complete behavior covered.
  - `ConflictResolverTests.swift` (new): empty/nil → no-op; sorted replace → markResolved → removeOther order verified via injected fakes; `replaceItem` failure skips marks+remove; `removeOther` failure still leaves marks; real async wrapper no-ops on local files.
  - Existing `CoordinatedReplaceWriterTests.swift`: duplication-check swapped for `testProductionSourceIsNotDuplicated` (unified layout proof); behavioral tests pass unchanged.
- [x] Grep `example/` + `test/` for `ICloudConflictException|ICloudItemNotDownloadedException|E_CONFLICT|E_NOT_DOWNLOADED` — matches are category/mapping assertions, not refuse-to-write assertions; no changes required.
- [x] Verify: iOS + macOS foundation `swift test` (28 + 30 tests passing), plugin `flutter test` (115 passing), `flutter analyze` clean.

### Phase 2: Step 1 new behavior + 2.1.0 release prep

- **Goal**: `writeInPlace` symmetric with `readInPlace` — auto-download + auto-resolve. Prepare 2.1.0 for publish.
- [ ] `CoordinatedReplaceWriter.swift` (unified) — add async-throws seams:
  ```swift
  typealias EnsureDownloaded = (URL) async throws -> Void
  typealias ResolveConflicts = (URL) async throws -> Void
  ```
  Convert `overwriteExistingItem` to `async throws`. Call `ensureDownloaded(url)` before existing pre-flight. Inside the coordinator write block (use `coordinateReplaceAsync` or bridge the existing closure), call `resolveConflicts(coordinatedURL)` before `replaceItem`. Existing pre-flight remains as last-resort guard. Add comment at the `resolveConflicts` call site noting the next `replaceItem` line clobbers the resolve output — acknowledging the canonical-Apple-pattern micro-cost to keep one way.
- [ ] `CoordinatedReplaceWriter.live` — bind `ensureDownloaded`:
  ```swift
  ensureDownloaded: { url in
    let values = try url.resourceValues(forKeys: [
      .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey,
      .ubiquitousItemDownloadingErrorKey,
    ])
    guard values.isUbiquitousItem == true else { return }
    if let err = values.ubiquitousItemDownloadingError { throw err }
    guard values.ubiquitousItemDownloadingStatus != .current else { return }
    try FileManager.default.startDownloadingUbiquitousItem(at: url)
    try await waitForDownloadCompletion(
      at: url,
      idleTimeouts: DownloadSchedule.interactiveWrite.idleTimeouts,
      retryBackoff: DownloadSchedule.interactiveWrite.retryBackoff
    )
  }
  ```
  and `resolveConflicts: { url in try await resolveUnresolvedConflicts(at: url) }`. If the static-let closure-async binding fails to compile, promote `live` to `static var` or `static func make()` — keep DI-via-closures idiom, do not introduce a second instantiation pattern.
- [ ] `iOSICloudStoragePlugin.swift` + `macOSICloudStoragePlugin.swift` — method-channel handlers calling `overwriteExistingItem` wrap in `Task { do { try await ...; result(value) } catch { result(FlutterError(code:, message:, details:)) } }`. Mirror existing async-bridge shape.
- [ ] TDD: inject closure test doubles into `CoordinatedReplaceWriter` for:
  - (a) happy-path (already-current, no conflicts) → write succeeds; pre-flight last-resort NOT fired.
  - (b) download-needed success → `ensureDownloaded` invoked exactly once, write completes.
  - (c) download-fails → seam throws → `overwriteExistingItem` rethrows typed; write NOT attempted.
  - (d) conflict-resolve needed → `resolveConflicts` invoked inside coordinator block; write completes.
  - (e) resolve-fails → seam throws → bubbled; localized description matches "auto-resolution failed" marker distinguishing from old pre-flight text.
  - (f) no-op when already `.current` (ubiquitous but current) → `ensureDownloaded` returns without calling `startDownloadingUbiquitousItem`.
  - (g) no-op when no conflicts → `resolveConflicts` returns silently.
  - Pre-flight last-resort path MUST NOT fire in (a)–(d).
- [ ] `CHANGELOG.md` — add `[2.1.0] - <release date>` under `[Unreleased]`:
  ```
  ### Changed
  - `writeInPlace` now proactively downloads non-current iCloud items and
    resolves unresolved conflict versions using Apple's canonical pattern
    (`NSFileVersion.unresolvedConflictVersionsOfItem` →
    `replaceItem` → `isResolved = true` → `removeOtherVersionsOfItem`),
    symmetric with `readInPlace`. Pre-flight refusal errors
    (E_CONFLICT / E_NOT_DOWNLOADED / E_DOWNLOAD_IN_PROGRESS) now fire only
    when auto-resolution itself fails.
  - Internal refactor: unified duplicate `CoordinatedReplaceWriter.swift`
    across iOS/macOS SPM modules; extracted `waitForDownloadCompletion`
    as a shared `async throws` helper (same name, signature change from
    callback to Swift Concurrency). Public Dart API unchanged.
  ```
  Non-breaking — public API unchanged; only internal behavior.
- [ ] `pubspec.yaml` — bump `version: 2.0.0` → `2.1.0`.
- [ ] `flutter pub publish --dry-run` clean. (Actual publish is user's call.)
- [ ] Verify: `swift test`, `flutter test`, `flutter analyze`, dry-run clean.

## Risks / Out of scope

**Risks**:
- `CoordinatedReplaceWriter.live` static-let async closure compile — fallback: `static var` or factory.
- SPM `target.sources` cross-module sharing on CI — validate macOS + Linux runner before tagging; symlinks as fallback.
- Quota/signout mid-operation — XCTest failure injection must cover; consumer rollback = revert app pubspec to `^2.0.0`.

**Out of scope** (per spec):
- App-side rider (`journal_autosave_notifier.dart` dedup + `Error.throwWithStackTrace` audit) — covered by mythicgme2e's own plan at `mythicgme2e/ai_specs/2026-04-17-icloud-plugin-auto-resolution-plan.md`.
- Manual smoke test, App Store release, post-ship Sentry verification — user-owned.
- Dart-side recoverable-iCloud classifier, migration download gate, reconciliation-backup relocation — explicitly deferred by spec.
