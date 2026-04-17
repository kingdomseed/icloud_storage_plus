# 2026-04-17 — iCloud plugin auto-resolution + autosave double-report fix

<goal>
Make `icloud_storage_plus.writeInPlace` behavior symmetric with `readInPlace`: proactively trigger iCloud download when the local copy isn't current, and proactively resolve unresolved file-version conflicts using the most-recent-wins strategy (matching UIDocument defaults and the plugin's existing `ICloudDocument.resolveConflicts()` logic). The plugin's pre-flight `E_CONFLICT` / `E_NOT_DOWNLOADED` / `E_DOWNLOAD_IN_PROGRESS` errors should become last-resort signals thrown only when auto-resolution itself fails.

Ship a corresponding app update that consumes the new plugin version, removes the single remaining double-report site in `JournalAutosaveNotifier`, and performs a bounded `Error.throwWithStackTrace` debt audit across storage-feature catch blocks to align with `docs/architecture/ERROR_HANDLING.md:167`.

Why it matters: a cluster of ~319 Sentry events in release 1.6.2 (issues WA–WJ) traces to the plugin refusing to write while iCloud is in normal, recoverable coordination states (unresolved conflicts, not-yet-downloaded placeholders, downloads in progress). Apple's documented contract is that the app must proactively call `startDownloadingUbiquitousItem` and `NSFileVersion.removeOtherVersionsOfItem` to resolve these states — the system does not auto-resolve. The plugin has the code for conflict resolution (`ICloudDocument.resolveConflicts()`) but only wires it to the UIDocument streaming path, not to `writeInPlace`. Users are unaffected — autosave retries naturally and the app recovers — but Sentry noise masks real issues. The plugin is owned by the same developer (kingdomseed), so the correct fix is at the plugin layer rather than by filtering symptoms in the app.
</goal>

<background>
**Tech stack:**
- Flutter app `mythicgme2e` (`/Users/jholt/development/jhd-business/mythicgme2e`) at version `1.6.2+1111` — consumes `icloud_storage_plus: ^2.0.0` from pub.dev.
- Plugin `icloud_storage_plus` (`/Users/jholt/development/jhd-business/icloud_storage_plus`) at version `2.0.0` (pub-published 2026-04-09). Supports iOS and macOS. Swift Package Manager layout with iOS/macOS mirrors.
- Dart error/reporting wrapper at `lib/src/features/error_reporting/data/error_reporting_service.dart`.

**Files to examine:**

Plugin (native to change):
- Four current copies of `CoordinatedReplaceWriter.swift` exist across iOS/macOS × `icloud_storage_plus` / `icloud_storage_plus_foundation` SPM modules:
  - `/Users/jholt/development/jhd-business/icloud_storage_plus/ios/icloud_storage_plus/Sources/icloud_storage_plus/CoordinatedReplaceWriter.swift`
  - `/Users/jholt/development/jhd-business/icloud_storage_plus/ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/CoordinatedReplaceWriter.swift`
  - `/Users/jholt/development/jhd-business/icloud_storage_plus/macos/icloud_storage_plus/Sources/icloud_storage_plus/CoordinatedReplaceWriter.swift`
  - `/Users/jholt/development/jhd-business/icloud_storage_plus/macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation/CoordinatedReplaceWriter.swift`
  This is pre-existing technical debt that the prerequisite refactor (Step 0) eliminates before new behavior lands.
- `/Users/jholt/development/jhd-business/icloud_storage_plus/ios/icloud_storage_plus/Sources/icloud_storage_plus/ICloudDocument.swift:107-140` — existing `resolveConflicts()` instance method. Will be **deleted** and replaced by a shared extracted async-throws helper.
- `/Users/jholt/development/jhd-business/icloud_storage_plus/ios/icloud_storage_plus/Sources/icloud_storage_plus/iOSICloudStoragePlugin.swift:921-1031` — existing `private` callback-based `waitForDownloadCompletion`. Support cluster to extract together: `addObserver`, `removeObservers`, `querySearchScopes`, `evaluateDownloadStatus` (at `:1039-1061`), `timeoutNativeError`, `CompletionGate`. Will be converted to `async throws` and promoted from instance-private to a shared free helper.
- macOS equivalent at `/Users/jholt/development/jhd-business/icloud_storage_plus/macos/icloud_storage_plus/Sources/icloud_storage_plus/macOSICloudStoragePlugin.swift:901` follows the same shape and receives the same treatment.
- `/Users/jholt/development/jhd-business/icloud_storage_plus/CHANGELOG.md` — `[Unreleased]` section exists; add `2.1.0` entry.
- `/Users/jholt/development/jhd-business/icloud_storage_plus/pubspec.yaml` — version bump `2.0.0` → `2.1.0` (non-breaking: no public API change; internal behavior only).
- Plugin tests: `/Users/jholt/development/jhd-business/icloud_storage_plus/test/` (Dart), plugin example app's integration tests, and an XCTest target (verified present / added in Step 0).

App (Dart to change):
- `lib/src/features/journal_manager/presentation/controllers/journal_autosave_notifier.dart:93-121` — `_doSave` double-reports `StorageException` at `:101` and `IOException` at `:106`. Both reports are redundant with the data-layer boundary in `ICloudStorageRepository`.
- `lib/src/features/manage_file_storage/data/repositories/icloud_storage_repository.dart:771,794,814` — three `throw StorageException(...)` sites inside catch blocks that lose the original stack trace.
- `lib/src/features/manage_file_storage/` and `lib/src/features/rollable_tables/` — audit for other catch-block throws that should use `Error.throwWithStackTrace`. Pre-seeded candidate list in `<implementation>` below.
- `pubspec.yaml:45` — bump `icloud_storage_plus: ^2.0.0` → `^2.1.0`.
- `CHANGELOG.md` (project-level, if present) — release note.

**Rulebook:**
- `docs/architecture/ERROR_HANDLING.md` — the authority. Key clauses: `:167` (Error.throwWithStackTrace mandate), `:482-497` (filtering strategy — don't report non-actionable states), `:140-175` (data layer responsibility).
- Apple documentation cached locally: `/Users/jholt/apple-foundation-study-vault/apple-docs/rendered/documentation/foundation/nsfileversion.md`, `/.../nsfileversion/removeotherversionsofitem(at:).md`, `/.../nsfileversion/unresolvedconflictversionsofitem(at:).md`, `/.../filemanager/startdownloadingubiquitousitem(at:).md`, `/.../nsfilecoordinator.md`. These are authoritative.

**Prior art:**
- `docs/superpowers/plans/2026-03-24-icloud-error-deduplication.md` + PR #1375 (merged in `c2f2fec47`) established the "single reporting boundary" rule. The split-catch pattern landed across 22 files. `journal_autosave_notifier.dart:101` was missed — that's what the app-side rider fixes.
- `docs/current-sentry-issues/1.6.2/clusters/writeinplace-icloud-conflict.md` — the cluster analysis driving this work.
- `docs/current-sentry-issues/1.6.2/issues/MYTHIC-GME-MOBILE-WA.md` — representative issue (293 events, migration loop).

**Out of scope (documented for later):**
- Classifier + filter for recoverable iCloud exceptions in `ErrorReportingService._recordError`. Not needed if the plugin stops throwing them; add later only if evidence shows they still land.
- Migration download gate in `CoordinatedUserTableRepository.migrateFromDirectory`. Becomes redundant once plugin auto-downloads.
- Reconciliation-backup relocation out of the iCloud container. Correctness nit; file as follow-up.
- Dead `uploadFile` method at `icloud_storage_repository.dart:368`. File as follow-up; harmless as-is.
- Sentry URLSession-swizzle 5xx filter for RevenueCat (issue WK). Unrelated.
</background>

<user_flows>
This is infrastructure, not user-facing UI. Describing behavior flows.

**Primary flow — normal autosave after this change:**
1. User edits journal; autosave timer or debounce fires.
2. `JournalAutosaveNotifier._doSave` calls down through `CoordinatedJournalStorageRepository` → `ICloudStorageRepository.writeInPlace`.
3. Plugin `writeInPlace` calls `CoordinatedReplaceWriter.overwriteExistingItem`:
   a. Pre-flight verifies destination. If `downloadStatus != .current`, plugin calls `startDownloadingUbiquitousItem` and waits via `waitForDownloadCompletion` (existing helper, bounded timeout).
   b. Inside the coordinator write block, before `replaceItem`: if `NSFileVersion.unresolvedConflictVersionsOfItem(at:)` is non-empty, sort by modification date, call `replaceItem(at:)` on the newest, mark all `isResolved = true`, and call `NSFileVersion.removeOtherVersionsOfItem(at:)` (satisfies Apple's "always inside a coordinator write" rule).
   c. Atomic replace proceeds.
4. Write succeeds. No exception. No Sentry event.

**Alternative flow — download wait times out or fails:**
1. Plugin's `waitForDownloadCompletion` hits its timeout, or `startDownloadingUbiquitousItem` throws (e.g., iCloud account disabled, quota exceeded).
2. Plugin throws `ICloudItemNotDownloadedException` (or `ICloudTimeoutException` if the wait itself times out) — actionable; reaches Sentry through the existing data-layer boundary.

**Alternative flow — conflict resolution itself fails:**
1. Plugin calls `removeOtherVersionsOfItem` inside coordinator block; it throws (disk full, file vanished mid-operation).
2. Plugin bubbles the error as `ICloudConflictException` (keep the existing category) — this now represents a genuine failure, not a refuse-to-write. Reaches Sentry.

**Error flow — app-side double-report removed:**
1. Data layer reports exactly once at `icloud_storage_repository.dart:788` (unchanged — still the single boundary).
2. Wrapper `StorageException` throws via `Error.throwWithStackTrace`, preserving original stack.
3. `JournalAutosaveNotifier._doSave:100-107` catches `StorageException` and `IOException`; logs via `_logger`, sets `rethrowOnFailure` behavior. **Does NOT call `ErrorReportingService.recordError`** — the data layer already reported.

**Error flow — genuine non-iCloud storage failure (e.g., disk full, file-system permission):**
1. `ICloudStorageRepository.writeInPlace` catches `PlatformException` (non-iCloud) at `:795-814`, reports to Sentry, throws `StorageException`.
2. `JournalAutosaveNotifier._doSave` catches, logs, does not re-report. Report count: 1. Unchanged behavior; just no longer double-counted.
</user_flows>

<requirements>
**Functional — plugin, Step 0 (prerequisite refactor, MUST land before Step 1):**

The plugin has pre-existing tech debt that blocks doing Step 1 cleanly. Step 0 eliminates it. The explicit principle: one idiomatic Apple-recommended way, no duplication, no parallel old/new code paths.

0a. **Unify the 4 `CoordinatedReplaceWriter.swift` copies** into a single source of truth per platform (2 files total: one iOS, one macOS). SPM module boundaries between `icloud_storage_plus` and `icloud_storage_plus_foundation` may require a single source file compiled into both modules (via SPM `target.sources` sharing or a symbolic link) rather than two copies. Pick the approach that produces one textual definition; do NOT keep duplicates. After this step, a change to the writer edits one file per platform.

0b. **Extract `waitForDownloadCompletion` as `waitForDownloadCompletion(at:idleTimeouts:retryBackoff:) async throws`.** Move from the plugin-instance-private callback API at `iOSICloudStoragePlugin.swift:921-1031` (and macOS mirror at `:901`) into a shared Swift file (e.g. `DownloadWaiter.swift`) inside the same module(s) as `CoordinatedReplaceWriter`. Convert from completion-handler to Swift Concurrency (`withCheckedThrowingContinuation` internally is acceptable). Extract these support symbols together into the shared module: `addObserver`, `removeObservers`, `querySearchScopes`, `evaluateDownloadStatus`, `timeoutNativeError`, `CompletionGate`. Delete the old private callback version — callers switch to the async API (one way to wait, not two).

0c. **Define two named default schedules** in the shared module — this is ONE helper parameterized by caller intent, not two helpers:
    ```
    static let interactiveWriteSchedule: [TimeInterval] = [10, 20]
    static let interactiveWriteBackoff:  [TimeInterval] = [2]
    static let backgroundReadSchedule:   [TimeInterval] = [60, 90, 180]
    static let backgroundReadBackoff:    [TimeInterval] = [2, 4]
    ```
    Read paths pass `backgroundReadSchedule`. Write paths (Step 1) pass `interactiveWriteSchedule`.

0d. **Extract `resolveUnresolvedConflicts(at:) async throws`** as a shared free helper in the same module. Signature and semantics match Apple's canonical conflict-resolution pattern exactly (the same pattern the deleted `ICloudDocument.resolveConflicts()` used): if `unresolvedConflictVersionsOfItem(at:)` returns nil or empty, return; else sort by `modificationDate` descending, `try latest.replaceItem(at: url, options: [])`, mark every conflict version `isResolved = true`, `try NSFileVersion.removeOtherVersionsOfItem(at: url)`. Throws on any underlying failure — callers decide error handling.

0e. **Delete `ICloudDocument.resolveConflicts()`.** `ICloudDocument.documentStateChanged()` now calls the extracted shared helper via a small do/catch adapter that preserves the existing `lastError` instance-state behavior. Result: one implementation, two call sites (observer + write path), zero duplication.

0f. **Verify or add an XCTest target** in the plugin. If no XCTest bundle exists under `ios/` or `macos/` today, add it in this step. The new helpers must have test coverage before Step 1 builds on them. Test doubles for the shared helpers use the DI-via-closures idiom already established by `CoordinatedReplaceWriter.live` — keep the one pattern.

0g. **Example-app test audit**: grep `example/` and `test/` for any assertion that `ICloudConflictException` / `ICloudItemNotDownloadedException` fires from `writeInPlace`. Those tests encoded the old broken contract. Update to the new behavior or delete.

After Step 0 lands: the plugin compiles, all existing tests pass, behavior is unchanged from 2.0.0. The refactor is a no-op from the outside. Only then does Step 1 add new behavior.

**Functional — plugin, Step 1 (new behavior):**

1. `CoordinatedReplaceWriter.overwriteExistingItem` becomes `async throws`. Before invoking `coordinateReplace`, call a new `ensureDownloaded(at: URL) async throws` seam (DI closure, same idiom as existing seams; `live` binding calls the shared `waitForDownloadCompletion` helper with `interactiveWriteSchedule` / `interactiveWriteBackoff`). The seam:
   a. Reads `URLResourceValues` for `.isUbiquitousItemKey`, `.ubiquitousItemDownloadingStatusKey`, `.ubiquitousItemIsDownloadingKey`, `.ubiquitousItemDownloadingErrorKey`.
   b. If `isUbiquitousItem == false` OR `downloadStatus == .current`: returns immediately (no-op, local file or already downloaded).
   c. If `ubiquitousItemDownloadingError != nil`: throws that error unchanged (genuine download failure).
   d. Otherwise: `try FileManager.default.startDownloadingUbiquitousItem(at: url)`, then `try await waitForDownloadCompletion(at: url, idleTimeouts: interactiveWriteSchedule, retryBackoff: interactiveWriteBackoff)`. Timeout surfaces as `ICloudTimeoutException`.

2. Inside the `coordinateReplace` closure (per Apple's contract that `removeOtherVersionsOfItem` must run inside a coordinator write block), call a new `resolveConflicts(at: URL) async throws` seam (DI closure; `live` binding calls the shared `resolveUnresolvedConflicts(at:)` helper from Step 0d) BEFORE calling `replaceItem`. If the seam throws, map to `ICloudConflictException` with a localized description distinguishing "auto-resolution failed" from the original pre-flight refusal; the outer error-mapping path continues to map this category to `ICloudConflictException` at the Dart surface.

   **Note on the ordering**: the shared helper calls `latest.replaceItem(at: url)` per Apple's canonical pattern, and then the coordinator closure immediately replaces `url` with the replacement file the user actually wanted to write. The `replaceItem` step is semantically redundant for the write case but it is the single canonical Apple pattern used across both call sites. We accept the micro-cost to avoid a second variant of conflict resolution. Add a `// ` comment at the call site noting that the next line clobbers it.

3. The pre-flight check in `replaceReadyStateError` at `CoordinatedReplaceWriter.swift:69-113` is retained as a last-resort error surface. It runs AFTER the new `ensureDownloaded` / `resolveConflicts` seams. Under normal operation it no longer fires; under pathological conditions (download times out, resolve fails) it still provides a stable typed error for Dart consumers.

4. Plugin version bump: `pubspec.yaml` `2.0.0` → `2.1.0`. CHANGELOG entry under `[2.1.0] - <publish date>` describes: auto-download and auto-conflict-resolution in `writeInPlace`, symmetric with `readInPlace`; Step 0 extraction refactor. Mark as non-breaking — public Dart API unchanged; new internal behavior only.

**Functional — app (narrow rider):**

6. `JournalAutosaveNotifier._doSave` (`lib/src/features/journal_manager/presentation/controllers/journal_autosave_notifier.dart:93-111`): REMOVE both `unawaited(ErrorReportingService.recordError(e, st))` calls at `:101` and `:106`. Keep the `rethrowOnFailure` rethrow semantics, keep `_activeSave = null` in `finally`, keep the catch clauses for control flow. Add a log line at `fine` or `warning` level using the existing `Logger` pattern (see peer controllers; do NOT introduce `dart:developer`).

7. `ICloudStorageRepository.writeInPlace` (`lib/src/features/manage_file_storage/data/repositories/icloud_storage_repository.dart:771,794,814`): migrate the three `throw StorageException(...)` inside catch blocks to `Error.throwWithStackTrace(StorageException(...), stack)` per `ERROR_HANDLING.md:167`. Preserves causal stack for Sentry.

8. `Error.throwWithStackTrace` debt audit: bounded to `lib/src/features/manage_file_storage/` and `lib/src/features/rollable_tables/`. For each `throw *Exception(...)` inside a `catch (_, stack)` or `catch (_, stackTrace)` block where a stack variable is in scope: migrate to `Error.throwWithStackTrace`. Do NOT migrate fresh throws where no stack trace is available. Candidate sites identified upstream (verify and expand during implementation):
   - `icloud_storage_repository.dart:771,794,814` (known)
   - `coordinated_user_table_repository.dart:166,372` (verify catch-block context)
   - `raw_user_table_repository.dart:101,117,163,188,214,252,272,288,318,343` (verify)
   - `raw_dart_io_journal_storage_repository.dart:130,255,285` (verify)
   - `coordinated_journal_storage_repository.dart:279,465,503` (verify)
   - `change_journal_storage_location_use_case.dart:208,270` (verify)
   - `repair_persisted_storage_root_use_case.dart:109` (verify)
   - `file_share_service.dart:553` (verify)

   For each, read the enclosing catch-block to confirm a stack is in scope before migrating. Skip if no stack available.

9. App pubspec: bump `icloud_storage_plus: ^2.0.0` to `^2.1.0` after the plugin's `2.1.0` is published to pub.dev. The existing `2.0.0` is already pub-published so publish cadence is a known good path. No `dependency_overrides` — if local-path iteration is needed mid-development, that is local-only git state and must not be committed.

**Error Handling:**

10. Plugin download-wait timeout must surface as `ICloudTimeoutException` (existing category), NOT `ICloudItemNotDownloadedException`. Rationale: we tried to download and the OS took too long — that's a timeout, not a "refusing to write." The existing category mapping supports this; just ensure the code path throws the right type.

11. Plugin conflict-resolution failure must surface as `ICloudConflictException` with a localized description distinguishing "auto-resolution failed" from the current "refusing to replace." Update the `userInfo[NSLocalizedDescriptionKey]` accordingly. Dart consumers rely on the type, not the string, so this is a UX/logging improvement only.

12. App autosave: `rethrowOnFailure: true` callers (rename flow, forced saves via `forceSaveStrict`) MUST still receive the exception. The rider only removes Sentry reports, not control flow.

**Edge Cases:**

13. Plugin: if `unresolvedConflictVersionsOfItem` returns `nil` (file doesn't exist), proceed normally — the overwrite path already handles the non-existent case at `:22-24` of `CoordinatedReplaceWriter.swift`.

14. Plugin: if `removeOtherVersionsOfItem` fails but all conflicts are already marked `isResolved`, the atomic replace can still proceed. Design choice: attempt the replace anyway and let it either succeed (desired outcome) or throw naturally. Document this tolerance in code comments.

15. Plugin: concurrent `writeInPlace` calls on the same file — the existing `NSFileCoordinator` serializes these. Auto-resolution happens inside the coordinator block, so no race. No additional locking needed.

16. App: `ICloudStorageRepository.writeInPlace` is used for journal saves, table saves, formula saves, reconciliation backups, journal backups, and migration. All of these are fed through the same reporting boundary; the app rider (step 6) is scoped ONLY to `_doSave`. Other call sites are already handled by the 2026-03-24 dedup work's split-catch pattern.

17. App: Dart-side `ICloudItemNotDownloadedException` and `ICloudConflictException` will still compile and still be mapped — they're just expected to arrive rarely after Phase C. No Dart API changes required.

**Validation:**

18. Plugin XCTest coverage (verify XCTest target per Step 0f):
    - Step 0 refactor regression coverage: each extracted helper (`waitForDownloadCompletion`, `resolveUnresolvedConflicts`) has direct tests independent of `CoordinatedReplaceWriter`. Existing tests relying on the old private callback API are migrated to the async variant and continue to pass.
    - Happy path: write succeeds when downloadStatus is `.current` (verify unchanged from 2.0.0 behavior).
    - Download path: write triggers the injected `ensureDownloaded` seam, proceeds after the seam completes. Inject a test-double seam that records the call and returns.
    - Download failure: test-double `ensureDownloaded` throws → `overwriteExistingItem` rethrows the typed error.
    - Conflict auto-resolution: test-double `resolveConflicts` seam that returns quietly; verify the coordinator block still calls `replaceItem`. Test-double that throws; verify error bubbles and the pre-flight last-resort check does NOT fire.
    - Idempotence: resolving a file with zero unresolved conflicts is a no-op and proceeds to replace.

19. Plugin Dart test coverage: `writeInPlace` tests at the method-channel layer pass with no Dart API changes. Add one test that exercises the new success modes (previously-conflicted-now-resolved; previously-not-downloaded-now-downloaded) with the method channel mocked to simulate success.

20. App test coverage: **extend the existing test file** at `test/src/features/journal_manager/presentation/controllers/journal_autosave_notifier_test.dart`. The file already installs `MockErrorReportingService` in `setUp` and uses a `_TestSessionNotifier` with `_SessionAutosaveInteractions` for controlling flush behavior — reuse this harness, do NOT introduce parallel mocking. New tests to add:
    - `_doSave` on `StorageException`: assert `MockErrorReportingService.recordError` was invoked 0 times. Use the existing interactions' `saveException` field to throw.
    - `_doSave` on `IOException` (use `FileSystemException`, which is an `IOException` subclass): assert `recordError` invoked 0 times.
    - `rethrowOnFailure: true` path still rethrows `StorageException` and `IOException` (regression check against the existing `forceSaveStrict` path).
    - `_activeSave` nulled in `finally` regardless of outcome (regression check).

21. App test ordering (per `act-flutter-tdd`, behavior-first):
    **New-behavior TDD slices (RED → GREEN → refactor):**
    - Slice 1: "`_doSave` does not call `ErrorReportingService.recordError` on `StorageException`" — write test FIRST, confirm RED (currently calls `recordError`), remove the `recordError` line, confirm GREEN.
    - Slice 2: "`_doSave` does not call `ErrorReportingService.recordError` on `IOException`" — same cycle for the `IOException` branch.

    **Regression verifications (tests green both before and after; they guard against accidental behavior changes):**
    - Regression 1: "`_doSave` rethrows `StorageException` when `rethrowOnFailure: true`".
    - Regression 2: "`_activeSave` returns to `null` in `finally` after success, `StorageException`, and `IOException`."

22. `Error.throwWithStackTrace` audit — for each migrated site, add or confirm a test that asserts the thrown exception's cause chain is preserved. Existing `throwsA(isA<StorageException>())` matchers remain valid; add an additional matcher that checks `e.cause` is the original exception type (where applicable).
</requirements>

<boundaries>
**Edge cases:**

- Plugin: file deleted between `unresolvedConflictVersionsOfItem` and the coordinator block — OS raises `NSFileNoSuchFileError`. Bubble as-is; don't wrap. Rare and diagnostic.
- Plugin: iCloud account signed out mid-operation — `startDownloadingUbiquitousItem` throws `NSCocoaError` with ubiquity error code. Surface as `ICloudContainerAccessException` (existing category).
- Plugin: extreme pathological case — user device on airplane mode with large unmerged conflict history. Resolution may take longer than the wait budget. `ICloudTimeoutException` fires. App logs and moves on. Acceptable.
- Plugin: simultaneous writes from multiple processes (rare) — NSFileCoordinator serializes. No explicit handling required.
- App: `_doSave` removal race — if the controller is disposed mid-save (`ref.invalidate` or `ref.mounted` check elsewhere), the rethrow still occurs but no one listens. Same as today; no change.

**Error scenarios:**

- Plugin conflict-resolution failure mid-coordinator — partial state possible if the replace-to-latest succeeded but `removeOtherVersionsOfItem` failed. Next write attempt will re-run resolution and complete cleanup. Document in code comments that partial resolution is tolerable.
- Plugin download timeout — must be tunable via the existing timeout knobs in `waitForDownloadCompletion`. Do not add a new timeout constant; reuse the read path's for parity. If the read path's default is too short for writes (writes often follow user intent more urgently than reads), consider making it a plugin-level configurable — but only if evidence shows the read-default is wrong. Default for this spec: reuse read-default.

**Limits:**

- Plugin: do not add retries inside `writeInPlace` itself. One download attempt, one resolution attempt, one replace attempt. Callers (the app) retry if desired via their own policy. Keeps plugin behavior predictable.
- Interactive-write download schedule: `idleTimeouts: [10, 20]` with `retryBackoff: [2]` — maximum ~32s before `ICloudTimeoutException`. This is distinct from the existing read schedule `[60, 90, 180]` / `[2, 4]` (~5.5 min) because writes are invoked from user-triggered saves that cannot reasonably block minutes. ONE parameterized helper, TWO named default configs documented in Step 0c.
- App: the rider does not introduce any retry logic or new reporting. Pure subtraction of the double-report at `_doSave`.
- Audit scope: strictly `lib/src/features/manage_file_storage/` + `lib/src/features/rollable_tables/`. Do NOT chase `Error.throwWithStackTrace` across the whole codebase in this spec — that's a separate cross-cutting cleanup.
</boundaries>

<implementation>
**Plugin changes (Swift) — Step 0 (prerequisite refactor):**

1. **Unify `CoordinatedReplaceWriter.swift`**: reduce from 4 copies to one textual source per platform (iOS, macOS). If SPM constrains sharing between `icloud_storage_plus` and `icloud_storage_plus_foundation` modules, use a single source file referenced by both targets' `Package.swift` `sources` declaration. No textual duplication.

2. **Extract the shared helpers** into a new Swift file (e.g. `Sources/icloud_storage_plus_shared/DownloadWaiter.swift` — exact name up to implementer; constraint: single source of truth accessible from both `CoordinatedReplaceWriter` and the plugin entry class). The file contains:

   ```swift
   public enum DownloadSchedule {
       public static let interactiveWrite: (idleTimeouts: [TimeInterval], retryBackoff: [TimeInterval])
           = (idleTimeouts: [10, 20], retryBackoff: [2])
       public static let backgroundRead: (idleTimeouts: [TimeInterval], retryBackoff: [TimeInterval])
           = (idleTimeouts: [60, 90, 180], retryBackoff: [2, 4])
   }

   /// Wait for an iCloud item to reach .current or fail.
   /// Uses NSMetadataQuery with idle-watchdog semantics; one attempt per
   /// entry in `idleTimeouts`, backoff per `retryBackoff`.
   func waitForDownloadCompletion(
       at url: URL,
       idleTimeouts: [TimeInterval],
       retryBackoff: [TimeInterval]
   ) async throws

   /// Resolve unresolved conflict versions using Apple's canonical pattern:
   /// pick most-recent, replaceItem, mark resolved, removeOtherVersions.
   /// MUST be called from within an NSFileCoordinator write block.
   func resolveUnresolvedConflicts(at url: URL) async throws
   ```

   Internally, `waitForDownloadCompletion` wraps the existing `NSMetadataQuery` + observer + `CompletionGate` logic in `withCheckedThrowingContinuation`. The old private callback-based `waitForDownloadCompletion` is **deleted**, not kept as an alternative path. Its support symbols (`addObserver`, `removeObservers`, `querySearchScopes`, `evaluateDownloadStatus`, `timeoutNativeError`, `CompletionGate`) move into the same shared module.

3. **Delete `ICloudDocument.resolveConflicts()`** (`ICloudDocument.swift:107-140`). Update `documentStateChanged()` (`:93-105`) to call the shared helper:

   ```swift
   @objc private func documentStateChanged() {
       if documentState.contains(.inConflict) {
           Task {
               do {
                   try await resolveUnresolvedConflicts(at: fileURL)
               } catch {
                   DebugHelper.log("Failed to resolve conflicts: \(error.localizedDescription)")
                   lastError = error
               }
           }
       }
       // ...remaining state-change handling unchanged...
   }
   ```

   Existing `lastError` semantics preserved via the call-site adapter. Do NOT duplicate the resolution logic inside this method.

4. **Verify or add XCTest target.** If `ios/icloud_storage_plus/Tests/` (or SPM test product in `Package.swift`) is absent, add it. Run existing tests to confirm the refactor is a behavioral no-op from 2.0.0. Publish-not-yet — plugin stays at `2.0.0` internally until Step 1 lands.

5. **Audit plugin `example/` and `test/` directories**: `Grep 'ICloudConflictException\|ICloudItemNotDownloadedException\|E_CONFLICT\|E_NOT_DOWNLOADED'` across both. For every match inside a test asserting these fire from `writeInPlace`, update the expectation to the new auto-resolve behavior or delete the test (it encoded the old broken contract).

**Plugin changes (Swift) — Step 1 (new behavior in `CoordinatedReplaceWriter`):**

Add two new `async throws` closure seams to the `CoordinatedReplaceWriter` struct, matching the existing DI-via-closure idiom:

```swift
typealias EnsureDownloaded = (URL) async throws -> Void
typealias ResolveConflicts = (URL) async throws -> Void
```

Convert `overwriteExistingItem` to `async throws` and wire the new seams:

```swift
func overwriteExistingItem(
    at destinationURL: URL,
    prepareReplacementFile: (URL) throws -> Void
) async throws -> Bool {
    guard fileExists(destinationURL.path) else { return false }

    // Step 1: proactive download if ubiquitous and not current
    try await ensureDownloaded(destinationURL)

    // Existing pre-flight check now runs as last-resort guard
    try verifyDestination(destinationURL)

    let replacementDirectory = try createReplacementDirectory(destinationURL)
    let replacementURL = replacementDirectory
        .appendingPathComponent(destinationURL.lastPathComponent)

    do {
        try prepareReplacementFile(replacementURL)
        try await coordinateReplaceAsync(destinationURL) { coordinatedURL in
            // Step 2: resolve any unresolved conflict versions inside the
            // coordinator write block per Apple's contract. The shared helper
            // calls replaceItem(at:) on the latest conflict version; the next
            // line clobbers it with the user's replacement content. That's
            // the canonical Apple pattern — we accept the micro-cost to avoid
            // a second variant of conflict resolution.
            try await resolveConflicts(coordinatedURL)
            try replaceItem(coordinatedURL, replacementURL)
        }
    } catch {
        try? removeItem(replacementDirectory)
        throw error
    }

    try? removeItem(replacementDirectory)
    return true
}
```

`coordinateReplaceAsync` is an async-bridging variant of the existing `coordinateReplace` closure. Replace the existing seam with the async one (not both); update call sites.

Wire `live` to call the shared helpers from Step 0:

```swift
static let live = CoordinatedReplaceWriter(
    // ...existing seams unchanged...
    ensureDownloaded: { url in
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
            idleTimeouts: DownloadSchedule.interactiveWrite.idleTimeouts,
            retryBackoff: DownloadSchedule.interactiveWrite.retryBackoff
        )
    },
    resolveConflicts: { url in
        try await resolveUnresolvedConflicts(at: url)
    }
)
```

Because Swift actor-isolation does not allow static-let closures to capture async work directly, `live` may need to become a computed `static var` or a factory `static func make() -> CoordinatedReplaceWriter` if the compiler requires it. Pick the form the compiler accepts without changing the DI-via-closures idiom — do NOT introduce a second instantiation pattern.

Apply the behavioral change to the unified `CoordinatedReplaceWriter.swift` (now 1 per platform after Step 0a).

**App changes (Dart):**

Modify `journal_autosave_notifier.dart:93-111`:

```dart
Future<void> _doSave({required bool rethrowOnFailure}) async {
  final future = ref
      .read(journalSessionProvider.notifier)
      .applyJournalOperation(const JournalOperation.flush());
  _activeSave = future;
  try {
    await future;
  } on StorageException catch (e, st) {
    _log.warning('Autosave failed (already reported by data layer)', e, st);
    if (rethrowOnFailure) rethrow;
  } on IOException catch (e, st) {
    _log.warning('Autosave failed on IO (already reported by data layer)', e, st);
    if (rethrowOnFailure) rethrow;
  } finally {
    _activeSave = null;
  }
}
```

Inject a `Logger` field at the top of the class using the project's `logger_compat.dart` pattern (see `error_reporting_service.dart:12` for the import, and any peer notifier — e.g., `journal_catalog_notifier.dart` — for the field pattern).

Modify the three throw sites in `icloud_storage_repository.dart`:

```dart
// At :771 (InvalidArgumentException branch):
Error.throwWithStackTrace(
  StorageException('Failed to write file in place: invalid argument', e),
  stack,
);

// At :794 (ICloudOperationException branch):
Error.throwWithStackTrace(
  StorageException('Failed to write file in place', e),
  stack,
);

// At :814 (PlatformException branch):
Error.throwWithStackTrace(
  StorageException('Failed to write file in place', e),
  stack,
);
```

Repeat for every verified catch-block throw site identified in the audit (requirement 8).

**Audit procedure (deterministic, executable):**

1. Run: `Grep 'throw \w+Exception\(' --path lib/src/features/manage_file_storage --path lib/src/features/rollable_tables --output_mode content --n true`.
2. For each match, read ±5 lines of surrounding context.
3. If the enclosing `catch` clause is of the form `catch (e, stack)` or `catch (e, stackTrace)` (or equivalent named-stack pattern), the site qualifies for migration. Replace `throw XException(...)` with `Error.throwWithStackTrace(XException(...), stack)` using the actual stack variable name in scope.
4. If the enclosing block has no stack in scope (bare `catch (e)` or a fresh throw outside any catch), skip. Do not invent a stack trace variable.
5. Record before/after line counts; the diff should only add `Error.throwWithStackTrace(` and `, stack)` around existing `throw ...()` expressions — no other logic changes.
6. Run `flutter analyze` after each file to confirm the imports include `dart:core` (the `Error` class is always available; no new import needed, but verify no analyzer warnings).

**Version and publish coordination:**

- Plugin Step 0 (refactor): do NOT publish yet. The extraction must be internally verified (XCTest, existing integration tests) as a behavioral no-op before Step 1 adds new behavior.
- Plugin Step 1 (new behavior): after Step 0 + Step 1 both land and tests pass, update CHANGELOG with `[2.1.0]`, bump `pubspec.yaml` to `2.1.0`, run `flutter pub publish --dry-run`, then publish to pub.dev.
- App: after the plugin's `2.1.0` is live on pub.dev, bump `pubspec.yaml:45` `icloud_storage_plus: ^2.0.0` → `^2.1.0`. Run `flutter pub get`, confirm no version conflicts, run full test suite.
- No `dependency_overrides` in committed state. Local-path overrides during development are fine but must not be merged.

**Patterns to follow:**

- Swift: dependency injection via closures (the existing `CoordinatedReplaceWriter` pattern). Keeps everything testable without mocking Foundation APIs.
- Dart: `Logger` from `logger_compat.dart`, not `dart:developer`. `unawaited()` for fire-and-forget — but the point of the rider is to REMOVE the `unawaited` calls to `recordError`.
- Tests: mocktail, `group`/`test` per VGV conventions. Existing test seams on `ErrorReportingService` (`recordError`, `addBreadcrumb` — `error_reporting_service.dart:212,217`) make verification straightforward.

**Anti-patterns to avoid:**

- Do NOT introduce a Dart-side conflict-resolution classifier, filter, or tracker in `ErrorReportingService`. Scope confirmed out.
- Do NOT introduce a Dart-side migration download gate in `migrateFromDirectory`. Obsolete after plugin change.
- Do NOT change the public Dart API of `icloud_storage_plus` — adding the behavior internally keeps the bump a minor (2.1.0).
- Do NOT add retries inside the plugin. One attempt per high-level operation.
- Do NOT expand the `Error.throwWithStackTrace` audit beyond `manage_file_storage/` + `rollable_tables/` in this spec.
- Do NOT keep the old callback-based `waitForDownloadCompletion` alongside the new async API. One way to wait; the old one is deleted.
- Do NOT keep `ICloudDocument.resolveConflicts()` as a duplicate of the extracted shared helper. Delete it; rewire the observer.
- Do NOT add a runtime feature flag / kill-switch to toggle the new behavior. The new behavior IS the behavior. Rollback is via pubspec revert (see Risk/Rollback below).
- Do NOT introduce `dependency_overrides` in committed state.
</implementation>

<validation>
**Plugin test expectations:**

- XCTest target covers the four new code paths: happy (already-current), download-then-write, download-fails, conflict-resolve-then-write, conflict-resolve-fails. Each uses injected closure seams — no real iCloud required.
- Existing plugin integration tests on the example app continue to pass. If any test was coded around the old "throws on not-current" pre-flight, update it to reflect new behavior.
- Plugin Dart-side tests (if any exist for `writeInPlace`'s method-channel surface) continue to pass — Dart API is unchanged.

**App test expectations — TDD vertical slices (per `act-flutter-tdd`):**

For each slice: write the failing test first (RED), confirm it fails for the right reason, implement the minimal code to pass (GREEN), refactor if warranted.

1. **`JournalAutosaveNotifier._doSave` StorageException does not call recordError**
   - Seam: override `ErrorReportingService.recordError` via the existing static test seam (`error_reporting_service.dart:217`) with a counter closure.
   - Arrange: a mocked `journalSessionProvider` whose `applyJournalOperation` throws `StorageException('test')`.
   - Act: call `_doSave(rethrowOnFailure: false)`.
   - Assert: `recordError` called 0 times; no rethrow.

2. **`_doSave` IOException does not call recordError**
   - Same shape as #1 with `FileSystemException` (subclass of `IOException`) thrown.

3. **`_doSave` with `rethrowOnFailure: true` still rethrows StorageException**
   - Arrange/act same as #1 but `rethrowOnFailure: true`.
   - Assert: rethrow occurs; `recordError` still called 0 times.

4. **`_doSave` nulls `_activeSave` in finally regardless of outcome**
   - Parameterized test: success path, StorageException path, IOException path. After each, `_activeSave` is null.

5. **Stack-trace preservation for `writeInPlace` throws**
   - For each migrated throw site: capture the thrown `StorageException`, inspect its `stackTrace` (via the `Error.throwWithStackTrace` propagation). Assert that the stack trace string contains frames from the original exception's origin, not merely the wrapping throw line.

**Integration / smoke:**

- Full `flutter test` passes.
- `flutter analyze` clean. (`custom_lint` was removed from the project in commit `3c7d24d06` and replaced by `riverpod_lint` via the analyzer plugin; no separate `dart run custom_lint` step is required.)
- Manual smoke on a simulator with iCloud sign-in: force a conflict (write a file, then write it again while offline on a second device, bring online), observe the plugin auto-resolves silently. Verify Sentry does NOT receive events for this flow (check Sentry project `jason-holt-digital-llc/mythic-gme-mobile`).
- Manual smoke for download: evict a file via `evictUbiquitousItem` (or delete the local copy from the simulator file system), trigger a save, observe auto-download + write.

**Test-split rationale (per TDD / robot-testing guidance):**

- Unit: all new plugin logic (closure-injected; no Foundation dependency in tests) and all `_doSave` branches (existing notifier test file pattern).
- Widget: no new widget surface.
- Robot: not applicable — no user journeys added. The existing autosave robot coverage (if any) should continue to pass unchanged.

**Observable Sentry effect (post-ship, next release cycle):**

- WA event volume drops ≥ 95% (the 293-event migration burst stops because plugin auto-downloads).
- WB–WJ event volumes drop ≥ 90% (plugin auto-resolves conflicts before throwing).
- Remaining events in these issues represent genuine edge cases: download timeouts, quota exceeded, permission revoked. Those ARE worth reporting.
- Zero double-reports from `JournalAutosaveNotifier._doSave` — verifiable by searching Sentry for events whose stack frames include both `journal_autosave_notifier.dart:_doSave` AND `icloud_storage_repository.dart:writeInPlace` for the same trace. Post-fix, such pairings should only appear as distinct issues, never duplicates.

**Measurement window:** the spec author (kingdomseed / developer@jasonholtdigital.com) verifies the drop by inspecting Sentry event counts 7 days after the App Store release reaches general availability. Mark WA–WJ as resolved in Sentry once the drop is confirmed.

**Shippability:**

- Plugin: native iOS/macOS Swift changes. NOT Shorebird-patchable. Ships in next App Store release of the app.
- App rider: pure Dart. Co-ships with the plugin bump in the same release.
</validation>

<risk_rollback>
**If a regression ships:**

Rollback path is a pubspec revert, not a runtime toggle:

1. Revert app `pubspec.yaml:45` from `icloud_storage_plus: ^2.1.0` back to `^2.0.0`.
2. Run `flutter pub get`, run full test suite, ship an expedited App Store release.
3. Leave the plugin's `2.1.0` published — other consumers (if any) can stay on it or downgrade independently.

**Why no kill switch / feature flag**: adding a runtime toggle would be a second way to run the same code (flag-off = old 2.0.0 behavior, flag-on = new 2.1.0 behavior), which is exactly the "multiple ways to do the same thing" this spec rejects. One path, one release, one rollback vehicle.

**What a regression would look like**:
- Plugin-originated: `NSFileVersion.removeOtherVersionsOfItem` fails on some device/state the tests didn't cover; visible as new `ICloudConflictException` events with the "auto-resolution failed" localized description.
- Plugin-originated: `startDownloadingUbiquitousItem` loop behavior on edge-case ubiquity identities not exercised by tests; visible as `ICloudTimeoutException` or `ICloudContainerAccessException` spikes.
- App-rider-originated: autosave silently swallows a genuine non-iCloud error because the spec removed the reporting line unconditionally — visible as "tables/journals not saving" user complaints without Sentry events. Mitigation: the data layer still reports non-iCloud errors via the existing `on PlatformException` branch at `icloud_storage_repository.dart:795-814` (already `recordError`s). Only iCloud-originated errors are dedup'd; pure file-system failures still report.

**Pre-ship gate**: if any plugin test suite or app test suite is red before publish, do not ship. The extraction refactor (Step 0) must be a full behavioral no-op before Step 1 runs.
</risk_rollback>

<done_when>
**Step 0 — prerequisite refactor:**

1. `CoordinatedReplaceWriter.swift` exists as a single source per platform (no textual duplication across SPM modules). Grep confirms: at most one file per platform matches `grep -r 'struct CoordinatedReplaceWriter' <plugin-root>`.
2. `waitForDownloadCompletion(at:idleTimeouts:retryBackoff:) async throws` and `resolveUnresolvedConflicts(at:) async throws` are defined in a shared module reachable from both the plugin entry class and `CoordinatedReplaceWriter`.
3. The old private callback-based `waitForDownloadCompletion` and its support cluster (`addObserver`, `removeObservers`, `querySearchScopes`, `evaluateDownloadStatus`, `timeoutNativeError`, `CompletionGate`) are removed from `iOSICloudStoragePlugin.swift` / `macOSICloudStoragePlugin.swift` — grep for their names returns matches ONLY in the shared module.
4. `ICloudDocument.resolveConflicts()` is deleted from `ICloudDocument.swift`; `documentStateChanged` calls the shared `resolveUnresolvedConflicts(at:)` via a do/catch adapter that preserves `lastError` semantics.
5. XCTest target exists and runs; all pre-existing plugin tests pass with the refactor applied (behavioral no-op proof).
6. `DownloadSchedule.interactiveWrite` and `DownloadSchedule.backgroundRead` named configs exist in the shared module.
7. Plugin example app's tests updated or deleted where they previously asserted the old refuse-to-write behavior.

**Step 1 — new behavior:**

8. `CoordinatedReplaceWriter.overwriteExistingItem` is `async throws` and invokes `ensureDownloaded` then `resolveConflicts` seams in the documented order.
9. `live` instantiation binds `ensureDownloaded` to call the shared `waitForDownloadCompletion` helper with `DownloadSchedule.interactiveWrite`, and `resolveConflicts` to the shared `resolveUnresolvedConflicts`.
10. Plugin XCTest suite covers: happy path, download-needed path, download-fails path, conflict-auto-resolve path, conflict-resolve-fails path, no-op-on-already-current path, no-op-on-no-conflicts path. All pass.
11. Plugin CHANGELOG has `[2.1.0]` entry (dated) describing: Step 0 extraction refactor + Step 1 auto-download + auto-conflict-resolution. Marked non-breaking.
12. Plugin `pubspec.yaml` at `2.1.0`. Plugin published to pub.dev.

**App rider:**

13. App `pubspec.yaml:45` bumped to `icloud_storage_plus: ^2.1.0` (after pub publish); `flutter pub get` succeeds.
14. `journal_autosave_notifier.dart._doSave` no longer calls `ErrorReportingService.recordError` in either `on StorageException` or `on IOException` branch. Tests verify zero `recordError` invocations for both paths.
15. `icloud_storage_repository.dart:771,794,814` use `Error.throwWithStackTrace`; stack-preservation tests pass.
16. All other catch-block throw sites in `lib/src/features/manage_file_storage/` and `lib/src/features/rollable_tables/` audited per the deterministic grep procedure and migrated where a stack variable is in scope.
17. Full app test suite passes. `flutter analyze` clean.
18. Cluster doc `docs/current-sentry-issues/1.6.2/clusters/writeinplace-icloud-conflict.md` updated with a "Resolved in app release X.Y.Z + plugin 2.1.0" footer.

**Post-ship verification (7 days after App Store GA):**

19. WA (`ICloudItemNotDownloadedException.migrateFromDirectory`) event count in Sentry drops ≥ 95%.
20. WB–WJ (`ICloudConflictException.writeInPlace`) combined event count drops ≥ 90%.
21. Zero double-reports from `JournalAutosaveNotifier._doSave` (verified by Sentry search for events whose stack includes both `journal_autosave_notifier.dart` and `icloud_storage_repository.dart` in the same trace).
22. MYTHIC-GME-MOBILE-WA through -WJ marked resolved in Sentry by the spec author.
</done_when>
</content>
