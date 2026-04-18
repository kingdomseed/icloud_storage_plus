# 2026-04-18 — PR #25 architectural correction — Plan

## Overview

Stack 4 commits on `feat/writeinplace-auto-resolution`. Phase 1 = vertical slice that activates the feature (pre-flight reduction). Phases 2–3 = deadlock-free seams + podspec / CocoaPods plumbing. Phase 4 = reconciliation + push.

**Spec**: `ai_specs/2026-04-18-icloud-plugin-pr25-architectural-correction-spec.md` (read for full requirements)

## Context

- **Repo**: Flutter plugin, dual-platform Swift Package Manager + CocoaPods (`*.podspec`). 2.0.0 published; correcting 2.1.0 in flight on `feat/writeinplace-auto-resolution`.
- **Branch state**: 2 PR commits already pushed (`915b589` Phase 1 refactor, `fecdfef` Phase 2 behavior). Adding 4 more.
- **Layout**: `ios/.../Sources/icloud_storage_plus_foundation/` is the canonical location; `macos/...` mirror is updated in lockstep. SPM `target.sources` shares the file across plugin + foundation modules per platform. Podspecs do NOT — must enumerate explicitly.
- **Reference implementations to mirror**:
  - Sync coord-on-DispatchQueue.global pattern: `iOSICloudStoragePlugin.swift` `copyOverwritingExistingItem` (already runs NSFileCoordinator on `DispatchQueue.global` indirectly via the call-site Task.detached).
  - DI-via-closures test seams: existing `CoordinatedReplaceWriterTests.swift` fixtures.
- **Actor-based test fixtures to migrate**: `testHappyPathDoesNotReinvokePreFlight` (line ~375, `actor Callbacks`), `testEnsureDownloadedRunsBeforeVerifyDestination` (line ~414, `actor CallLog`). Both must move to `NSLock`-based sync counters when accessor closures become sync.
- **Example app `ios/Podfile` / `macos/Podfile`** absent until `flutter pub get` runs. Generate before `pod install`.
- **Assumptions/Gaps**:
  - `CocoaPods` available locally (validation requirement, not implementation). If `pod` binary missing, fall back to `pod lib lint --allow-warnings` only and document in commit message.
  - `NSError` `as NSError` cast is idempotent under Swift bridging; storing `underlyingNSError` once and reusing for both `localizedDescription` extraction and `NSUnderlyingErrorKey` is safe.
  - Concurrent-load test for deadlock contract: bound at 5s timeout; `ProcessInfo.processInfo.activeProcessorCount * 2` Tasks should complete in <1s on Apple Silicon. If flaky on CI, raise the timeout, do not relax the assertion.
  - macOS `ICloudDocument.documentStateChanged`-equivalent (`presentedItemDidChange`) keeps the `Task { try await resolveUnresolvedConflicts(...) }` wrapper. Async wrapper stays in `ConflictResolver.swift` alongside the new sync sibling.

## Plan

### Phase 1: Pre-flight reduction (Slice A — vertical slice that activates the feature)

- **Goal**: stop refusing on `hasConflicts == true` so `resolveConflicts` actually runs. Feature becomes functional end-to-end.
- [x] TDD: 4 new Slice A tests per platform (`testLiveWriterDoesNotInvokeFullLegacyPreflight` — structural assertion live binding uses the new helper; `testVerifyOverwriteDestinationIsFileRejectsDirectory`, `testVerifyOverwriteDestinationIsFileAcceptsRegularFile` — behavior on the new helper; `testLegacyFullPreflightStillExistsForCopyPath` — copy path symbol survives). RED first (helper doesn't exist), GREEN after split. Note: a "behavior test on the live binding's conflict bypass" requires fabricating NSFileVersion conflicts which isn't tractable in unit tests; structural assertion on the live binding is the most direct RED-GREEN signal achievable without iCloud test infrastructure.
- [x] `ios/icloud_storage_plus/Sources/icloud_storage_plus_foundation/CoordinatedReplaceWriter.swift` — replaced `private static func verifyFileDestinationCanBeOverwritten` with `static func verifyOverwriteDestinationIsFile(at:)` (directory-only). `live.verifyDestination` calls the new helper.
- [x] `macos/icloud_storage_plus/Sources/icloud_storage_plus_foundation/CoordinatedReplaceWriter.swift` — same split, mirrored verbatim.
- [x] `verifyExistingDestinationCanBeReplaced` and `replaceReadyStateError` untouched (copy path still uses them via `copyOverwritingExistingItem` in plugin entry classes).
- [x] `testHappyPathDoesNotReinvokePreFlight` + `testEnsureDownloadedRunsBeforeVerifyDestination` still green (step order intact).
- [x] Verify: iOS foundation `swift test` 38/38 passing; macOS foundation `swift test` 40/40 passing; `flutter analyze` clean; `flutter test` 115/115 passing.
- [ ] Commit: `fix(ios,macos): pre-flight stops refusing on unresolved conflicts (Slice A)`.

### Phase 2: Sync seams + deadlock-free bridge + NSError bridging (Slices B + C + D)

- **Goal**: eliminate `DispatchSemaphore` cooperative-pool deadlock surface; honest type signatures for the now-sync conflict resolver; robust NSUnderlyingError bridging.
- [ ] `ConflictResolver.swift` (both platforms) — add `resolveUnresolvedConflictsSync(at:) throws` sibling. Keep async wrapper for the iOS `ICloudDocument.documentStateChanged` and macOS `presentedItemDidChange` Task callers.
- [ ] `CoordinatedReplaceWriter.swift` (both platforms) — typealias edits:
  - `typealias ResolveConflicts = (URL) throws -> Void` (was `async throws`).
  - `typealias CoordinateReplace = (URL, @Sendable (URL) throws -> Void) async throws -> Void` (drop `@escaping`, drop inner `async`).
- [ ] `CoordinatedReplaceWriter.swift` `overwriteExistingItem` — accessor closure becomes `{ coordinatedURL in try resolveConflicts(coordinatedURL); try replaceItem(coordinatedURL, replacementURL) }` (no `await`).
- [ ] `CoordinatedReplaceWriter.swift` rewrite `liveCoordinateReplace`: `withCheckedThrowingContinuation` on `DispatchQueue.global(qos: .userInitiated).async`, sync coordinator accessor capturing `accessError` into local var, single resume per terminal branch. NO `DispatchSemaphore`. Delete `CoordinatedReplaceErrorBox`.
- [ ] `CoordinatedReplaceWriter.swift` `live.resolveConflicts` binding switches to `resolveUnresolvedConflictsSync`.
- [ ] `CoordinatedReplaceWriter.swift` `autoResolveConflictError(underlying:)` — `let underlyingNSError = underlying as NSError` once; reuse for `localizedDescription` and `NSUnderlyingErrorKey`.
- [ ] Migrate `CoordinatedReplaceWriterTests.swift` fixtures (both platforms): every `coordinateReplace: { url, accessor in try await accessor(url) }` → `try accessor(url)`; every `resolveConflicts: { _ in ... }` async closure → sync.
- [ ] Migrate `actor Callbacks` (in `testHappyPathDoesNotReinvokePreFlight`) and `actor CallLog` (in `testEnsureDownloadedRunsBeforeVerifyDestination`) to `final class` with `NSLock`-guarded counters/event arrays; remove `await` from now-sync closure bodies.
- [ ] TDD: `testLiveCoordinateReplaceDoesNotStarveCooperativePool` (Slice C) — `withTaskGroup` spawning `ProcessInfo.processInfo.activeProcessorCount * 2` concurrent calls to `liveCoordinateReplace` against unique temp files; assert all complete within 5s. Add to both platform test suites.
- [ ] TDD: strengthen `testLiveAutoResolveConflictErrorPreservesCoordinationDomain` (Slice D) — `XCTAssertTrue(wrapped.userInfo[NSUnderlyingErrorKey] is NSError)` then `XCTAssertEqual((... as? NSError)?.code, NSFileWriteOutOfSpaceError)`.
- [ ] Verify: `swift test` passes on both platforms (count up by 2 — one new test per platform); test suite total runtime <5s; `flutter analyze && flutter test` clean.
- [ ] Commit: `fix(ios,macos): sync ResolveConflicts seam + deadlock-free coord bridge (Slices B/C/D)`.

### Phase 3: Podspec source_files widening + version bump (Slice E)

- **Goal**: Flutter's CocoaPods build path picks up the new shared foundation sources; podspec/pubspec versions agree.
- [ ] `ios/icloud_storage_plus.podspec` — `s.version = '2.1.0'`. Replace `s.source_files = '...'` with array form listing 4 entries: `Sources/icloud_storage_plus/**/*.{h,m,swift}` plus the three foundation files (`CoordinatedReplaceWriter`, `DownloadWaiter`, `ConflictResolver`).
- [ ] `macos/icloud_storage_plus.podspec` — same edits.
- [ ] Run: `pod lib lint ios/icloud_storage_plus.podspec --allow-warnings --no-clean` (exit 0).
- [ ] Run: `pod lib lint macos/icloud_storage_plus.podspec --allow-warnings --no-clean` (exit 0).
- [ ] CocoaPods integration smoke (best-effort, tools-permitting):
  - [ ] `cd example && flutter pub get && cd ios && pod install` — Podfile auto-generated, install succeeds.
  - [ ] `cd example && flutter build ios --no-codesign --debug --simulator` (or `xcodebuild ... -sdk iphonesimulator clean build` substitute) — plugin compiles via CocoaPods.
  - [ ] `cd example && flutter build macos --debug` — plugin compiles via CocoaPods on macOS.
  - [ ] If any tooling unavailable in this environment, document substitute (`pod lib lint` only) in commit body.
- [ ] Verify: `flutter pub publish --dry-run` from repo root reports `Package has 0 warnings`.
- [ ] Commit: `fix(ios,macos): podspec source_files include shared foundation sources; bump to 2.1.0 (Slice E)`.

### Phase 4: Plan reconciliation + final validation + push

- **Goal**: document the deviation from the original Phase 2 plan typealiases; final all-green check; update PR #25.
- [ ] `ai_specs/2026-04-17-icloud-plugin-auto-resolution-plan.md` — append "Post-merge correction" note under Phase 2 documenting: pre-flight reduction, sync `ResolveConflicts` deviation, deadlock-free bridge, podspec sync, NSError bridging fix.
- [ ] Cross-cutting verify: `flutter analyze` clean; `flutter test` 115/115; iOS foundation `swift test` ≥36 passing; macOS foundation `swift test` ≥38 passing; `flutter pub publish --dry-run` 0 warnings.
- [ ] Commit: `docs(plan): note PR #25 architectural correction in 2026-04-17 plan`.
- [ ] `git push` to `origin feat/writeinplace-auto-resolution` — PR #25 auto-updates.
- [ ] Post a single PR comment summarizing the 4 commits and which review threads each one resolves (Sentry / Codex P0 / Codex P1 / Copilot ×3).

## Risks / Out of scope

**Risks**:
- Concurrent-load deadlock test could be flaky if cooperative pool size assumption is wrong on a given runner. Mitigation: use `withTaskGroup` (structured concurrency, deterministic teardown) and bound timeout at 5s — fail closed, not flaky-skip.
- `pod lib lint` requires Ruby + CocoaPods; not all environments have it. Acceptable substitute: `flutter build ios/macos` against the example app (which exercises the same source_files path). If neither works, ship anyway with explicit Slice-E manual-verify-required note in the commit body.
- Static-let async-closure compile fragility: by removing async from the resolveConflicts seam and the coordinator accessor, this risk shrinks substantially. `liveEnsureDownloaded` remains `static let` async — already proven to compile in Phase 2.

**Out of scope**:
- `copy()` symmetric auto-resolve (separate future PR per spec §background).
- App-side `JournalAutosaveNotifier._doSave` rider (parent app's plan).
- `mythicgme2e` pubspec bump to `^2.1.0` (post-publish, not part of this PR).
- Public Dart API changes — none. Wire contract preserved by `autoResolveConflictError`.
